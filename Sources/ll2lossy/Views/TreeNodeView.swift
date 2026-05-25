import SwiftUI
import AppKit

enum CheckboxState { case unchecked, mixed, checked }

// MARK: – Checkbox helpers (MainActor free functions)

@MainActor
func losslessDescendantIDs(of item: FileItem) -> [UUID] {
    if !item.isDirectory { return item.isLossless ? [item.id] : [] }
    return item.children?.flatMap { losslessDescendantIDs(of: $0) } ?? []
}

@MainActor
func checkboxState(of item: FileItem, in selection: Set<UUID>) -> CheckboxState {
    if !item.isDirectory {
        return selection.contains(item.id) ? .checked : .unchecked
    }
    let ids = losslessDescendantIDs(of: item)
    if ids.isEmpty { return .unchecked }
    let n = ids.filter { selection.contains($0) }.count
    if n == 0           { return .unchecked }
    if n == ids.count   { return .checked   }
    return .mixed
}

@MainActor
func toggleCheckbox(item: FileItem, selection: Binding<Set<UUID>>) {
    if !item.isDirectory {
        if selection.wrappedValue.contains(item.id) {
            selection.wrappedValue.remove(item.id)
        } else if item.isLossless {
            selection.wrappedValue.insert(item.id)
        }
        return
    }
    let ids = Set(losslessDescendantIDs(of: item))
    if checkboxState(of: item, in: selection.wrappedValue) == .checked {
        ids.forEach { selection.wrappedValue.remove($0) }
    } else {
        ids.forEach { selection.wrappedValue.insert($0) }
    }
}

// MARK: – Tree node view

@MainActor
struct TreeNodeView: View {
    @ObservedObject var item: FileItem
    @Binding var selection: Set<UUID>
    let losslessOnly: Bool
    let showCheckbox: Bool
    let depth: Int
    let onDropFolder: ((FileItem) -> Void)?

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
                        onDropFolder: onDropFolder
                    )
                }
            }
        } label: {
            rowLabel(isDirectory: true)
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: nil) { _ in
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
            // Checkbox (source panel only)
            if showCheckbox && (isDirectory || item.isLossless) {
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
