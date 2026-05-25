import Foundation
import ffmpegkit

@MainActor
final class TranscodeEngine: ObservableObject {
    @Published private(set) var tasks: [TranscodeTask] = []
    @Published private(set) var isRunning = false

    // sessionId → task.id, for cancel support
    private var sessionMap: [Int: UUID] = [:]
    private var runningJob: Task<Void, Never>?

    // MARK: – Public API

    func enqueue(sources: [FileItem], sourceRoot: URL, destinationRoot: URL, settings: AppSettings) {
        let newTasks = buildTasks(sources: sources, sourceRoot: sourceRoot,
                                  destinationRoot: destinationRoot, settings: settings)
        guard !newTasks.isEmpty else { return }
        tasks.append(contentsOf: newTasks)

        isRunning = true
        let parallelism = settings.parallelTasks
        runningJob = Task { [weak self] in
            await self?.runAll(newTasks, parallelism: parallelism, settings: settings)
            await MainActor.run { self?.isRunning = false }
        }
    }

    func cancelAll() {
        FFmpegKit.cancel()
        tasks.filter { $0.status == .running || $0.status == .pending }
            .forEach { $0.setStatus(.cancelled) }
        runningJob?.cancel()
        isRunning = false
    }

    func cancel(id: UUID) {
        if let sessionId = sessionMap.first(where: { $0.value == id })?.key {
            FFmpegKit.cancel(sessionId)
        }
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .done || $0.status == .cancelled || $0.status == .error }
    }

    // MARK: – Private: task building

    private func buildTasks(sources: [FileItem], sourceRoot: URL,
                            destinationRoot: URL, settings: AppSettings) -> [TranscodeTask] {
        sources.flatMap { $0.collectLosslessFiles() }.map { file in
            TranscodeTask(
                source: file.url,
                destination: resolveDestination(source: file.url, sourceRoot: sourceRoot,
                                                destinationRoot: destinationRoot, settings: settings)
            )
        }
    }

    private func resolveDestination(source: URL, sourceRoot: URL,
                                    destinationRoot: URL, settings: AppSettings) -> URL {
        let srcPath  = source.path
        let rootPath = sourceRoot.path
        let relative = srcPath.hasPrefix(rootPath)
            ? String(srcPath.dropFirst(rootPath.count + 1))
            : source.lastPathComponent

        var dest = destinationRoot
            .appendingPathComponent(relative)
            .deletingPathExtension()
            .appendingPathExtension("mp3")

        if settings.onConflict == .suffix {
            var i = 1
            let base = dest.deletingPathExtension().lastPathComponent
            let dir  = dest.deletingLastPathComponent()
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent("\(base)_\(i).mp3")
                i += 1
            }
        }
        return dest
    }

    // MARK: – Private: execution

    private func runAll(_ allTasks: [TranscodeTask], parallelism: Int, settings: AppSettings) async {
        await withTaskGroup(of: Void.self) { group in
            var iter    = allTasks.makeIterator()
            var running = 0

            while running < parallelism, let task = iter.next() {
                group.addTask { await self.runOne(task, settings: settings) }
                running += 1
            }
            for await _ in group {
                if let task = iter.next() {
                    group.addTask { await self.runOne(task, settings: settings) }
                }
            }
        }
    }

    private func runOne(_ task: TranscodeTask, settings: AppSettings) async {
        // Skip / overwrite
        let destExists = FileManager.default.fileExists(atPath: task.destinationURL.path)
        if destExists {
            switch settings.onConflict {
            case .skip:
                task.setStatus(.done)
                return
            case .overwrite:
                try? FileManager.default.removeItem(at: task.destinationURL)
            case .suffix:
                break
            }
        }

        // Create destination directory
        try? FileManager.default.createDirectory(
            at: task.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Probe duration for progress
        let duration = await probeDuration(url: task.sourceURL)

        task.setStatus(.running)

        let cmd = buildCommand(task: task, settings: settings)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            func resume() {
                guard !resumed else { return }
                resumed = true
                cont.resume()
            }

            let session = FFmpegKit.executeAsync(
                cmd,
                withCompleteCallback: { [weak self] session in
                    Task { @MainActor [weak self] in
                        if let sid = session?.getSessionId() {
                            self?.sessionMap.removeValue(forKey: sid)
                        }
                    }
                    let rc = session?.getReturnCode()
                    if ReturnCode.isSuccess(rc) {
                        task.setStatus(.done)
                        task.setProgress(1.0)
                    } else if ReturnCode.isCancel(rc) {
                        task.setStatus(.cancelled)
                    } else {
                        let log = session?.getAllLogsAsString() ?? "Неизвестная ошибка"
                        // Keep last 5 non-empty lines
                        let lines = log.components(separatedBy: "\n").filter { !$0.isEmpty }
                        task.setError(lines.suffix(5).joined(separator: "\n"))
                    }
                    resume()
                },
                withLogCallback: nil,
                withStatisticsCallback: { stats in
                    guard let stats, let dur = duration, dur > 0 else { return }
                    let timeMs = Double(stats.getTime())
                    task.setProgress(min(timeMs / (dur * 1000.0), 0.99))
                }
            )

            if let sid = session?.getSessionId() {
                Task { @MainActor [weak self] in
                    self?.sessionMap[sid] = task.id
                }
            }
        }
    }

    private func buildCommand(task: TranscodeTask, settings: AppSettings) -> String {
        var parts: [String] = [
            "-i", quoted(task.sourceURL.path),
            "-y",
            "-codec:a", "libmp3lame"
        ]

        if settings.encodingMode == .vbr {
            parts += ["-q:a", "\(settings.vbrQuality)"]
        } else {
            parts += ["-b:a", "\(settings.cbrBitrate)k"]
        }

        if settings.preserveMetadata {
            parts += ["-map_metadata", "0", "-id3v2_version", "3"]
        }

        parts.append(quoted(task.destinationURL.path))
        return parts.joined(separator: " ")
    }

    private func probeDuration(url: URL) async -> Double? {
        await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            FFprobeKit.getMediaInformationAsync(url.path) { session in
                let dur = session?.getMediaInformation()?.getDuration()
                    .flatMap { Double($0) }
                cont.resume(returning: dur)
            }
        }
    }

    private func quoted(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\"" }
}
