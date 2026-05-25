import SwiftUI
import AppKit

@MainActor
struct FileBrowserView: View {
    let title: String
    let losslessOnly: Bool
    let eagerLoad: Bool          // left panel: load full tree on open
    @Binding var path: String
    @Binding var root: FileItem?
    @Binding var selection: Set<UUID>

    var onConvertDrop: (([FileItem]) -> Void)?
    var onNavigateToFolder: ((FileItem) -> Void)?

    @State private var isLoading = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                } else if !selection.isEmpty && losslessOnly {
                    Text("\(selection.count) выбрано")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Обновить")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            PathBarView(path: $path) { url in
                loadRoot(url: url)
            }

            Divider()

            // Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let root {
                        if let children = root.children {
                            ForEach(children) { child in
                                TreeNodeView(
                                    item: child,
                                    selection: $selection,
                                    losslessOnly: losslessOnly,
                                    showCheckbox: losslessOnly,
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
                    ? Color.accentColor.opacity(0.07)
                    : Color(NSColor.textBackgroundColor)
            )
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                guard let convert = onConvertDrop else { return false }
                var urls: [URL] = []
                let group = DispatchGroup()
                for provider in providers {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                        if let data = item as? Data,
                           let url  = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                        else if let url = item as? URL { urls.append(url) }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    convert(urls.map { FileItem(url: $0) })
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

    // MARK: – Loading

    private func loadRoot(url: URL) {
        path = url.path
        let item = FileItem(url: url)
        item.loadChildren(losslessOnly: losslessOnly)
        root = item
        selection = []

        if eagerLoad {
            isLoading = true
            Task {
                await item.loadAll(losslessOnly: losslessOnly)
                isLoading = false
            }
        }
    }

    private func reload() {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        loadRoot(url: url)
    }
}
