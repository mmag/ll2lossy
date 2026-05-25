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

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static let losslessExtensions: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff"
    ]
    static let audioExtensions: Set<String> = losslessExtensions.union(["m4a"])

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        let ext = url.pathExtension.lowercased()
        self.isLossless = !isDir.boolValue && FileItem.audioExtensions.contains(ext)
        if isDir.boolValue { self.children = nil }
    }

    func loadChildren(losslessOnly: Bool) {
        guard isDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { children = []; return }

        children = contents
            .map { FileItem(url: $0) }
            .filter { losslessOnly ? ($0.isDirectory || $0.isLossless) : true }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

/// Recursively collects all lossless audio file URLs under the given URL.
/// Free function — no actor isolation, safe to call from background tasks.
func collectLosslessURLs(from url: URL) -> [URL] {
    let extensions: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff", "m4a"
    ]
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
    if !isDir.boolValue {
        return extensions.contains(url.pathExtension.lowercased()) ? [url] : []
    }
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
    ) else { return [] }
    return contents.flatMap { collectLosslessURLs(from: $0) }
}
