import SwiftUI
import AppKit

struct FileBrowserView: View {
    let title: String
    let losslessOnly: Bool
    @Binding var path: String
    @Binding var root: FileItem?
    @Binding var selection: Set<UUID>

    /// Called when user drops items from the source panel onto this panel (right panel only)
    var onConvertDrop: (([FileItem]) -> Void)?
    /// Called when user navigates to a folder by dropping on a folder row (right panel only)
    var onNavigateToFolder: ((FileItem) -> Void)?

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .padding(.leading, 8)
                Spacer()
                if !selection.isEmpty && losslessOnly {
                    Text("\(selection.count) выбрано")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            PathBarView(path: $path) { url in
                loadRoot(url: url)
            }

            Divider()

            // File tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let root {
                        if let children = root.children {
                            ForEach(children) { child in
                                TreeNodeView(
                                    item: child,
                                    selection: $selection,
                                    losslessOnly: losslessOnly,
                                    depth: 0,
                                    onDropFolder: onNavigateToFolder
                                )
                            }
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    } else {
                        Text("Выберите папку")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                isDropTargeted
                    ? Color.accentColor.opacity(0.08)
                    : Color(NSColor.textBackgroundColor)
            )
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            // Drop target for convert-by-drag (right panel)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let convert = onConvertDrop else { return false }
                // Items come from DragCoordinator via NSItemProvider with fileURL
                // We collect URLs and match them to items — engine handles recursion
                var urls: [URL] = []
                let group = DispatchGroup()
                for provider in providers {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        if let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        } else if let url = item as? URL {
                            urls.append(url)
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    let items = urls.map { FileItem(url: $0) }
                    convert(items)
                }
                return true
            }
        }
        .onAppear {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                loadRoot(url: url)
            }
        }
    }

    private func loadRoot(url: URL) {
        path = url.path
        let item = FileItem(url: url)
        item.loadChildren(losslessOnly: losslessOnly)
        root = item
        selection = []
    }
}
