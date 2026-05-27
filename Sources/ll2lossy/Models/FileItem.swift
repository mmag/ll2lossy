import Foundation
import AppKit

// MARK: – Background-safe helpers (no actor isolation)

private struct EntryInfo: Sendable {
    let url: URL
    let isDirectory: Bool
    let isLossless: Bool
}

private func scanLevel(at url: URL, losslessOnly: Bool) -> [EntryInfo] {
    let losslessExts: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff", "m4a", "mp3"
    ]
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }

    return contents.compactMap { child -> EntryInfo? in
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir)
        let dir = isDir.boolValue
        let ext = child.pathExtension.lowercased()
        let lossless = !dir && losslessExts.contains(ext)
        if losslessOnly && !dir && !lossless { return nil }
        return EntryInfo(url: child, isDirectory: dir, isLossless: lossless)
    }
    .sorted {
        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
        return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
    }
}

// MARK: – FileItem

@MainActor
final class FileItem: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let isLossless: Bool

    @Published var children: [FileItem]?   // nil = not yet loaded
    @Published var isExpanded = false
    @Published var isLoading = false

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }

    static let losslessExtensions: Set<String> = [
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff"
    ]
    static let audioExtensions: Set<String> = losslessExtensions.union(["m4a", "mp3"])

    init(url: URL) {
        self.url = url
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        let ext = url.pathExtension.lowercased()
        self.isLossless = !isDir.boolValue && FileItem.audioExtensions.contains(ext)
        if isDir.boolValue { self.children = nil }
    }

    fileprivate init(entry: EntryInfo) {
        self.url = entry.url
        self.isDirectory = entry.isDirectory
        self.isLossless = entry.isLossless
        if entry.isDirectory { self.children = nil }
    }

    // MARK: – Lazy async load (background I/O, called on expand or root open)

    func loadChildrenAsync(losslessOnly: Bool) async {
        guard isDirectory, children == nil, !isLoading else { return }
        isLoading = true
        let url = self.url
        let entries = await Task.detached(priority: .userInitiated) {
            scanLevel(at: url, losslessOnly: losslessOnly)
        }.value
        children = entries.map { FileItem(entry: $0) }
        isLoading = false
    }

    // Kept for the right-panel navigate-into-folder path (local, one level, fast enough)
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
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff", "m4a", "mp3"
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
