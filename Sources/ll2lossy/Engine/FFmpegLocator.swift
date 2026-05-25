import Foundation

enum FFmpegLocator {
    private static let candidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    static func locate(override: String = "") -> String? {
        if !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func ffprobe(ffmpegOverride: String = "") -> String? {
        // ffprobe lives next to ffmpeg
        if let ffmpeg = locate(override: ffmpegOverride) {
            let dir = (ffmpeg as NSString).deletingLastPathComponent
            let candidate = (dir as NSString).appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Returns duration in seconds using ffprobe, or nil on failure.
    static func duration(of url: URL, ffmpegOverride: String = "") async -> Double? {
        guard let ffprobe = ffprobe(ffmpegOverride: ffmpegOverride) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffprobe)
        proc.arguments = [
            "-v", "quiet",
            "-print_format", "default=noprint_wrappers=1:nokey=1",
            "-show_entries", "format=duration",
            url.path
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Double(str)
    }
}
