import Foundation

enum FFmpegLocator {
    /// Path where setup.sh installs the bundled ffmpeg binary.
    static var installURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ll2lossy/ffmpeg")
    }

    static func locate() -> String? {
        let path = installURL.path
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
