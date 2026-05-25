import Foundation
import AppKit

@MainActor
final class FileItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let isLossless: Bool

    @Published var children: [FileItem]?   // nil = not yet loaded
    @Published var isExpanded = false

    var name: String { url.lastPathComponent }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static let losslessExtensions: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff"
    ]
    // m4a can be either ALAC or AAC; we include it and let ffprobe/ffmpeg handle it
    static let audioExtensions: Set<String> = losslessExtensions.union(["m4a"])

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        let ext = url.pathExtension.lowercased()
        self.isLossless = !isDir.boolValue && FileItem.audioExtensions.contains(ext)
        // directories start with empty children array so tree shows disclosure arrow
        if isDir.boolValue { self.children = nil }
    }

    func loadChildren(losslessOnly: Bool) {
        guard isDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            children = []
            return
        }

        children = contents
            .map { FileItem(url: $0) }
            .filter { item in
                if losslessOnly { return item.isDirectory || item.isLossless }
                return true
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    // Recursively collect all lossless files under this item
    nonisolated func collectLosslessFiles() -> [FileItem] {
        // Must be called from non-isolated context carefully;
        // safe because we only read immutable properties (url, isDirectory, isLossless)
        // and children snapshot at call time.
        if !isDirectory { return isLossless ? [self] : [] }
        // Load children synchronously on the calling thread (used from engine thread)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
              let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        let items = contents.map { FileItem(url: $0) }
        var result: [FileItem] = []
        for item in items {
            result.append(contentsOf: item.collectLosslessFiles())
        }
        return result
    }
}
