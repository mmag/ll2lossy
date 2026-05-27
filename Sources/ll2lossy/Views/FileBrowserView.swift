import SwiftUI
import AppKit

@MainActor
struct FileBrowserView: View {
    let title: String
    let subtitle: String
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
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 18, height: 18)
                } else if !selection.isEmpty && losslessOnly {
                    selectionBadge("\(selection.count)")
                }

                if !losslessOnly {
                    destinationMenu
                }

                Button { reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Обновить")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            PathBarView(path: $path) { url in
                loadRoot(url: url)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let root {
                        if let children = root.children {
                            if children.isEmpty {
                                emptyState(
                                    title: losslessOnly ? "Нет подходящих аудиофайлов" : "Папка пуста",
                                    systemImage: losslessOnly ? "waveform.slash" : "folder"
                                )
                            }
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
                        emptyState(title: "Выберите папку", systemImage: "folder.badge.plus")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                isDropTargeted
                    ? Color.accentColor.opacity(0.07)
                    : Color(NSColor.textBackgroundColor).opacity(0.92)
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
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 1)
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

    // MARK: – Header helpers

    private var destinationMenu: some View {
        Menu {
            Button { selectAll() } label: {
                Label("Выделить все", systemImage: "checkmark.square")
            }
            .disabled(root?.children?.isEmpty ?? true)

            Button { selection = [] } label: {
                Label("Снять выделение", systemImage: "square")
            }
            .disabled(selection.isEmpty)

            Divider()

            Button(role: .destructive) { prepareDelete() } label: {
                Label("Удалить выбранное", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help("Действия с папкой назначения")
    }

    private func selectionBadge(_ value: String) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
            .help("\(value) выбрано")
    }

    private func emptyState(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
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
