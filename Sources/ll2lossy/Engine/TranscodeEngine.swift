import Foundation

@MainActor
final class TranscodeEngine: ObservableObject {
    @Published private(set) var tasks: [TranscodeTask] = []
    @Published private(set) var isRunning = false

    private var processes: [UUID: Process] = [:]
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
        tasks.removeAll { $0.status != .running && $0.status != .pending }
    }

    // MARK: – Task building

    private func buildTasks(sources: [FileItem], sourceRoot: URL,
                            destinationRoot: URL, settings: AppSettings) -> [TranscodeTask] {
        sources
            .flatMap { collectLosslessURLs(from: $0.url) }
            .map { url in
                TranscodeTask(
                    source: url,
                    destination: resolveDestination(source: url, sourceRoot: sourceRoot,
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

    // MARK: – Execution

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
        guard let ffmpeg = FFmpegLocator.locate() else {
            task.setError("ffmpeg не найден. Запустите ./setup.sh")
            return
        }

        let destExists = FileManager.default.fileExists(atPath: task.destinationURL.path)
        if destExists {
            switch settings.onConflict {
            case .skip:      task.setStatus(.done); return
            case .overwrite: try? FileManager.default.removeItem(at: task.destinationURL)
            case .suffix:    break
            }
        }

        try? FileManager.default.createDirectory(
            at: task.destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Build arguments: use -progress pipe:1 for progress, stderr for duration
        var args: [String] = ["-hide_banner", "-i", task.sourceURL.path, "-y",
                               "-codec:a", "libmp3lame"]
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

        do { try process.run() } catch {
            await MainActor.run { _ = self.processes.removeValue(forKey: taskID) }
            task.setError(error.localizedDescription)
            return
        }

        // Shared duration found in stderr, used for progress from stdout
        let sharedDuration = SharedDuration()

        let stderrTask = Task<String, Never> {
            var errorLines: [String] = []
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    errorLines.append(line)
                    if await sharedDuration.value == nil,
                       let d = Self.parseDuration(from: line) {
                        await sharedDuration.set(d)
                    }
                }
            } catch {}
            return errorLines.suffix(8).joined(separator: "\n")
        }

        let progressTask = Task {
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    guard line.hasPrefix("out_time_us="),
                          let us  = Double(line.dropFirst("out_time_us=".count)), us > 0,
                          let dur = await sharedDuration.value, dur > 0
                    else { continue }
                    task.setProgress(min(us / (dur * 1_000_000), 0.99))
                }
            } catch {}
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        progressTask.cancel()
        let errorOutput = await stderrTask.value

        await MainActor.run { _ = self.processes.removeValue(forKey: taskID) }

        switch process.terminationReason {
        case .uncaughtSignal:
            task.setStatus(.cancelled)
        default:
            if process.terminationStatus == 0 {
                task.setStatus(.done)
                task.setProgress(1.0)
            } else {
                task.setError(errorOutput.isEmpty ? "Неизвестная ошибка" : errorOutput)
            }
        }
    }

    // "  Duration: 00:03:45.23, start: ..."
    private static func parseDuration(from line: String) -> Double? {
        guard line.contains("Duration:") else { return nil }
        let parts = line.components(separatedBy: "Duration:").dropFirst()
        guard let chunk = parts.first else { return nil }
        let trimmed = chunk.trimmingCharacters(in: .whitespaces)
        let hms = trimmed.prefix(while: { $0.isNumber || $0 == ":" || $0 == "." })
        let components = hms.split(separator: ":")
        guard components.count == 3,
              let h = Double(components[0]),
              let m = Double(components[1]),
              let s = Double(components[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// Safely shares duration found in stderr with the progress reader in stdout
private actor SharedDuration {
    var value: Double?
    func set(_ d: Double) { value = d }
}
