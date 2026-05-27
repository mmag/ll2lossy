import SwiftUI
import AppKit

enum CheckboxState { case unchecked, mixed, checked }

// MARK: – Checkbox helpers

/// Returns true if `url` itself or any ancestor is in the selection.
@MainActor
private func isCovered(_ url: URL, by selection: Set<URL>) -> Bool {
    if selection.contains(url) { return true }
    var current = url.deletingLastPathComponent()
    while current.pathComponents.count > 1 {
        if selection.contains(current) { return true }
        let parent = current.deletingLastPathComponent()
        if parent == current { break }
        current = parent
    }
    return false
}

@MainActor
func checkboxState(of item: FileItem, in selection: Set<URL>) -> CheckboxState {
    if isCovered(item.url, by: selection) { return .checked }
    guard item.isDirectory, let children = item.children, !children.isEmpty else {
        return .unchecked
    }
    var hasChecked = false
    var hasUnchecked = false
    for child in children {
        switch checkboxState(of: child, in: selection) {
        case .checked:   hasChecked = true
        case .unchecked: hasUnchecked = true
        case .mixed:     hasChecked = true; hasUnchecked = true
        }
        if hasChecked && hasUnchecked { return .mixed }
    }
    return hasChecked ? .checked : .unchecked
}

@MainActor
func toggleCheckbox(item: FileItem, selection: Binding<Set<URL>>) {
    let url = item.url
    let urlPath = url.path
    let state = checkboxState(of: item, in: selection.wrappedValue)

    if state == .checked {
        // Remove this URL and any ancestor or descendant that covers it
        selection.wrappedValue = selection.wrappedValue.filter { existing in
            if existing == url { return false }
            if existing.path.hasPrefix(urlPath + "/") { return false }  // descendant
            if urlPath.hasPrefix(existing.path + "/") { return false }  // ancestor
            return true
        }
    } else {
        // Select: add URL, remove any descendants now covered by this
        var s = selection.wrappedValue.filter { !$0.path.hasPrefix(urlPath + "/") }
        s.insert(url)
        selection.wrappedValue = s
    }
}

// MARK: – Tree node view

@MainActor
struct TreeNodeView: View {
    @ObservedObject var item: FileItem
    @Binding var selection: Set<URL>
    let losslessOnly: Bool
    let showCheckbox: Bool
    let depth: Int
    let onDropFolder: ((FileItem) -> Void)?
    let onMoveToFolder: ((FileItem, [NSItemProvider]) -> Void)?

    @State private var folderDropTargeted = false

    var body: some View {
        if item.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    // MARK: Directory

    private var directoryRow: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { item.isExpanded },
                set: { expanded in
                    item.isExpanded = expanded
                    if expanded && item.children == nil {
                        Task { await item.loadChildrenAsync(losslessOnly: losslessOnly) }
                    }
                }
            )
        ) {
            if item.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(height: 20)
                    .padding(.leading, CGFloat(depth + 1) * 14 + 4)
            } else if let children = item.children {
                ForEach(children) { child in
                    TreeNodeView(
                        item: child,
                        selection: $selection,
                        losslessOnly: losslessOnly,
                        showCheckbox: showCheckbox,
                        depth: depth + 1,
                        onDropFolder: onDropFolder,
                        onMoveToFolder: onMoveToFolder
                    )
                }
            }
        } label: {
            rowLabel(isDirectory: true)
                .contentShape(Rectangle())
                .background(folderDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .onDrop(of: [.fileURL], isTargeted: $folderDropTargeted) { providers in
                    if let moveHandler = onMoveToFolder {
                        moveHandler(item, providers)
                        return true
                    }
                    onDropFolder?(item); return true
                }
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    // MARK: File

    private var fileRow: some View {
        rowLabel(isDirectory: false)
            .padding(.leading, CGFloat(depth + 1) * 14)
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: item.url as NSURL)
            }
    }

    // MARK: Shared label

    private func rowLabel(isDirectory: Bool) -> some View {
        HStack(spacing: 4) {
            if showCheckbox {
                let state = checkboxState(of: item, in: selection)
                Button {
                    toggleCheckbox(item: item, selection: $selection)
                } label: {
                    Image(systemName: checkboxIcon(state))
                        .foregroundStyle(checkboxColor(state))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 16, height: 16)

            Text(item.name)
                .lineLimit(1)

            Spacer()

            if !isDirectory && item.isLossless {
                Text(item.url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }

    private func checkboxIcon(_ state: CheckboxState) -> String {
        switch state {
        case .checked:   return "checkmark.square.fill"
        case .mixed:     return "minus.square.fill"
        case .unchecked: return "square"
        }
    }

    private func checkboxColor(_ state: CheckboxState) -> Color {
        switch state {
        case .checked, .mixed: return .accentColor
        case .unchecked:       return Color(NSColor.tertiaryLabelColor)
        }
    }
}
