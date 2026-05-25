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
        "flac", "wav", "wave", "aiff", "aif", "alac", "ape", "wv", "wma", "dsf", "dff", "m4a"
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

    @Published var children: [FileItem]?
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

    private init(entry: EntryInfo) {
        self.url = entry.url
        self.isDirectory = entry.isDirectory
        self.isLossless = entry.isLossless
        if entry.isDirectory { self.children = nil }
    }

    // MARK: – Eager full-tree load with progress (background I/O)

    /// Scans the entire subtree off the main thread.
    /// `onProgress` is called on MainActor with (dirsDone, dirsTotal).
    func loadAllWithProgress(
        losslessOnly: Bool,
        onProgress: @escaping (Int, Int) -> Void
    ) async {
        guard isDirectory else { return }

        // Scan first level on background thread to get top-level dirs
        let topEntries = await Task.detached(priority: .userInitiated) {
            scanLevel(at: self.url, losslessOnly: losslessOnly)
        }.value

        let topItems = topEntries.map { FileItem(entry: $0) }
        self.children = topItems

        let topDirs = topItems.filter { $0.isDirectory }
        let total = topDirs.count

        if total == 0 { return }

        var done = 0
        onProgress(done, total)

        for dir in topDirs {
            await dir.scanRecursively(losslessOnly: losslessOnly)
            done += 1
            onProgress(done, total)
        }
    }

    private func scanRecursively(losslessOnly: Bool) async {
        guard isDirectory else { return }

        let entries = await Task.detached(priority: .userInitiated) {
            scanLevel(at: self.url, losslessOnly: losslessOnly)
        }.value

        let items = entries.map { FileItem(entry: $0) }
        self.children = items

        for child in items where child.isDirectory {
            await child.scanRecursively(losslessOnly: losslessOnly)
        }
    }

    // MARK: – Lazy single-level load (on-demand expand, runs on main thread — fast for local)

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
