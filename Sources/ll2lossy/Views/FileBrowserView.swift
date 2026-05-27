import SwiftUI
import AppKit

@MainActor
struct FileBrowserView: View {
    let title: String
    let losslessOnly: Bool
    @Binding var path: String
    @Binding var root: FileItem?
    @Binding var selection: Set<URL>

    var onConvertDrop: (([FileItem]) -> Void)?
    var onNavigateToFolder: ((FileItem) -> Void)?
    var onMoveToFolder: ((FileItem, [NSItemProvider]) -> Void)?

    @State private var isLoading = false
    @State private var isDropTargeted = false
    @State private var showDeleteConfirm = false
    @State private var deleteItemCount = 0

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
                if !losslessOnly {
                    Button { selectAll() } label: {
                        Image(systemName: "checkmark.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Выделить все")

                    Button { selection = [] } label: {
                        Image(systemName: "square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Снять выделение")

                    Button { prepareDelete() } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(selection.isEmpty ? Color(NSColor.tertiaryLabelColor) : .red)
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection.isEmpty)
                    .help("Удалить выбранное")
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
                                    showCheckbox: true,
                                    depth: 0,
                                    onDropFolder: onNavigateToFolder,
                                    onMoveToFolder: onMoveToFolder
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
        .confirmationDialog(
            "Удалить \(deleteItemCount) \(itemWord(deleteItemCount))?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) { deleteSelected() }
            Button("Отмена", role: .cancel) {}
        }
        .onAppear {
            guard !path.isEmpty else { return }
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                loadRoot(url: url)
            }
        }
    }

    // MARK: – Selection & deletion

    private func prepareDelete() {
        var count = 0
        for url in selection {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                count += 1
                if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                    while let _ = e.nextObject() { count += 1 }
                }
            } else {
                count += 1
            }
        }
        deleteItemCount = count
        showDeleteConfirm = true
    }

    private func itemWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "объектов" }
        switch mod10 {
        case 1:  return "объект"
        case 2, 3, 4: return "объекта"
        default: return "объектов"
        }
    }

    private func selectAll() {
        guard let children = root?.children else { return }
        selection = Set(children.map { $0.url })
    }

    private func deleteSelected() {
        for url in selection {
            try? FileManager.default.removeItem(at: url)
        }
        selection = []
        reload()
    }

    // MARK: – Loading

    private func loadRoot(url: URL) {
        path = url.path
        let item = FileItem(url: url)
        root = item
        selection = []
        isLoading = true
        Task {
            await item.loadChildrenAsync(losslessOnly: losslessOnly)
            isLoading = false
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
