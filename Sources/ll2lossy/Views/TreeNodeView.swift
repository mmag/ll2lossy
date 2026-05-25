import SwiftUI
import AppKit

struct TreeNodeView: View {
    @ObservedObject var item: FileItem
    @Binding var selection: Set<UUID>
    let losslessOnly: Bool
    let depth: Int
    let onDropFolder: ((FileItem) -> Void)?  // right-panel: drop on folder = navigate

    var body: some View {
        if item.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    // MARK: – Directory row with DisclosureGroup

    @ViewBuilder
    private var directoryRow: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { item.isExpanded },
                set: { expanded in
                    item.isExpanded = expanded
                    if expanded && item.children == nil {
                        item.loadChildren(losslessOnly: losslessOnly)
                    }
                }
            )
        ) {
            if let children = item.children {
                ForEach(children) { child in
                    TreeNodeView(
                        item: child,
                        selection: $selection,
                        losslessOnly: losslessOnly,
                        depth: depth + 1,
                        onDropFolder: onDropFolder
                    )
                }
            }
        } label: {
            rowLabel(isDirectory: true)
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection(item) }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    onDropFolder?(item)
                    return true
                }
        }
        .padding(.leading, CGFloat(depth) * 14)
    }

    // MARK: – File row

    private var fileRow: some View {
        rowLabel(isDirectory: false)
            .padding(.leading, CGFloat(depth + 1) * 14)
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(item) }
            .onDrag {
                // Used for drag-to-convert: selection must already include this item
                let provider = NSItemProvider(object: item.url as NSURL)
                return provider
            }
    }

    // MARK: – Shared label

    private func rowLabel(isDirectory: Bool) -> some View {
        let isSelected = selection.contains(item.id)
        return HStack(spacing: 4) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(item.name)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer()
            if !isDirectory, item.isLossless {
                Text(item.url.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: – Selection

    private func toggleSelection(_ item: FileItem) {
        let cmdDown = NSEvent.modifierFlags.contains(.command)
        if cmdDown {
            if selection.contains(item.id) {
                selection.remove(item.id)
            } else {
                selection.insert(item.id)
            }
        } else {
            selection = [item.id]
        }
    }
}
