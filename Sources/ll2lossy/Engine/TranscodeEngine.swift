import Foundation
import AppKit

@MainActor
final class TranscodeEngine: ObservableObject {
    @Published private(set) var tasks: [TranscodeTask] = []
    @Published private(set) var isRunning = false

    private var processes: [UUID: Process] = [:]
    private var runningJob: Task<Void, Never>?

    // MARK: – Public API

    func enqueue(sources: [FileItem], sourceRoot: URL, destinationRoot: URL, settings: AppSettings) {
        guard !sources.isEmpty else { return }

        let newTasks = buildTasks(
            sources: sources,
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            settings: settings
        )
        guard !newTasks.isEmpty else { return }
        tasks.append(contentsOf: newTasks)

        let parallelism = settings.parallelTasks
        let ffmpegOverride = settings.ffmpegPath

        isRunning = true
        runningJob = Task { [weak self] in
            await self?.runAll(newTasks, parallelism: parallelism, settings: settings, ffmpegOverride: ffmpegOverride)
            await MainActor.run { self?.isRunning = false }
        }
    }

    func cancelAll() {
        processes.values.forEach { $0.terminate() }
        runningJob?.cancel()
        tasks.filter { $0.status == .running || $0.status == .pending }
            .forEach { $0.setStatus(.cancelled) }
        isRunning = false
    }

    func cancel(id: UUID) {
        processes[id]?.terminate()
    }

    func clearCompleted() {
        tasks.removeAll { $0.status == .done || $0.status == .cancelled || $0.status == .error }
    }

    // MARK: – Private

    private func buildTasks(
        sources: [FileItem],
        sourceRoot: URL,
        destinationRoot: URL,
        settings: AppSettings
    ) -> [TranscodeTask] {
        var result: [TranscodeTask] = []
        for item in sources {
            let files = item.collectLosslessFiles()
            for file in files {
                let dest = resolveDestination(
                    source: file.url,
                    sourceRoot: sourceRoot,
                    destinationRoot: destinationRoot,
                    settings: settings
                )
                result.append(TranscodeTask(source: file.url, destination: dest))
            }
        }
        return result
    }

    private func resolveDestination(
        source: URL,
        sourceRoot: URL,
        destinationRoot: URL,
        settings: AppSettings
    ) -> URL {
        // Relative path from source root
        let srcPath = source.path
        let rootPath = sourceRoot.path
        let relative: String
        if srcPath.hasPrefix(rootPath) {
            relative = String(srcPath.dropFirst(rootPath.count + 1)) // drop leading slash
        } else {
            relative = source.lastPathComponent
        }

        var dest = destinationRoot
            .appendingPathComponent(relative)
            .deletingPathExtension()
            .appendingPathExtension("mp3")

        if settings.onConflict == .suffix && FileManager.default.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext  = dest.pathExtension
            let dir  = dest.deletingLastPathComponent()
            var i = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent("\(base)_\(i).\(ext)")
                i += 1
            }
        }
        return dest
    }

    private func runAll(
        _ allTasks: [TranscodeTask],
        parallelism: Int,
        settings: AppSettings,
        ffmpegOverride: String
    ) async {
        await withTaskGroup(of: Void.self) { group in
            var iter = allTasks.makeIterator()
            var running = 0

            while running < parallelism, let task = iter.next() {
                group.addTask { await self.runOne(task, settings: settings, ffmpegOverride: ffmpegOverride) }
                running += 1
            }
            for await _ in group {
                if let task = iter.next() {
                    group.addTask { await self.runOne(task, settings: settings, ffmpegOverride: ffmpegOverride) }
                }
            }
        }
    }

    private func runOne(_ task: TranscodeTask, settings: AppSettings, ffmpegOverride: String) async {
        guard let ffmpeg = FFmpegLocator.locate(override: ffmpegOverride) else {
            task.setError("ffmpeg не найден. Установите через Homebrew:\n  brew install ffmpeg")
            return
        }

        // Skip / overwrite logic
        let destExists = FileManager.default.fileExists(atPath: task.destinationURL.path)
        if destExists {
            switch settings.onConflict {
            case .skip:
                task.setStatus(.done)
                return
            case .overwrite:
                try? FileManager.default.removeItem(at: task.destinationURL)
            case .suffix:
                break // destination was already uniquified in buildTasks
            }
        }

        // Create destination directory
        let destDir = task.destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Get duration for progress tracking
        let duration = await FFmpegLocator.duration(of: task.sourceURL, ffmpegOverride: ffmpegOverride)

        // Build ffmpeg arguments
        var args: [String] = ["-i", task.sourceURL.path, "-y", "-codec:a", "libmp3lame"]
        if settings.encodingMode == .vbr {
            args += ["-q:a", "\(settings.vbrQuality)"]
        } else {
            args += ["-b:a", "\(settings.cbrBitrate)k"]
        }
        if settings.preserveMetadata {
            args += ["-map_metadata", "0", "-id3v2_version", "3"]
        }
        args += ["-progress", "pipe:1", "-nostats", task.destinationURL.path]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        task.setStatus(.running)
        let taskID = task.id
        await MainActor.run { self.processes[taskID] = process }

        do {
            try process.run()
        } catch {
            await MainActor.run { self.processes.removeValue(forKey: taskID) }
            task.setError(error.localizedDescription)
            return
        }

        // Read progress from stdout
        let progressTask = Task {
            guard let dur = duration, dur > 0 else { return }
            for await line in stdoutPipe.fileHandleForReading.bytes.lines {
                if line.hasPrefix("out_time_us="),
                   let us = Double(line.dropFirst("out_time_us=".count)), us > 0 {
                    task.setProgress(min(us / (dur * 1_000_000.0), 0.99))
                }
            }
        }

        // Wait for process using terminationHandler to avoid blocking a thread
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }

        progressTask.cancel()
        await MainActor.run { self.processes.removeValue(forKey: taskID) }

        if process.terminationReason == .uncaughtSignal || process.terminationStatus == 15 {
            task.setStatus(.cancelled)
        } else if process.terminationStatus == 0 {
            task.setStatus(.done)
            task.setProgress(1.0)
        } else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "Неизвестная ошибка"
            // Trim to last 5 lines for readability
            let lines = msg.components(separatedBy: "\n").filter { !$0.isEmpty }
            task.setError(lines.suffix(5).joined(separator: "\n"))
        }
    }
}
