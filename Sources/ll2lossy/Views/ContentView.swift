import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = TranscodeEngine()

    @State private var leftRoot:  FileItem?
    @State private var rightRoot: FileItem?
    @State private var leftSelection: Set<UUID> = []
    @State private var showProgress  = false
    @State private var showSettings  = false
    @State private var ffmpegMissing = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                FileBrowserView(
                    title: "Источник",
                    losslessOnly: true,
                    path: $settings.leftPath,
                    root: $leftRoot,
                    selection: $leftSelection,
                    onConvertDrop: nil,
                    onNavigateToFolder: nil
                )
                .frame(minWidth: 280)

                FileBrowserView(
                    title: "Назначение",
                    losslessOnly: false,
                    path: $settings.rightPath,
                    root: $rightRoot,
                    selection: .constant([]),
                    onConvertDrop: { items in startConversion(sources: items) },
                    onNavigateToFolder: { folder in navigateRight(to: folder) }
                )
                .frame(minWidth: 280)
            }
            .frame(minHeight: 400)

            if showProgress {
                Divider()
                ProgressDrawerView(engine: engine)
                    .frame(minHeight: 140, maxHeight: 260)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showProgress)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: convertSelected) {
                    Label("Конвертировать", systemImage: "arrow.right.circle.fill")
                }
                .disabled(leftSelection.isEmpty || rightRoot == nil)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Конвертировать выбранное (⌘↩)")

                Divider()

                Button {
                    withAnimation { showProgress.toggle() }
                } label: {
                    Label(
                        "Прогресс",
                        systemImage: engine.isRunning
                            ? "arrow.2.circlepath.circle.fill"
                            : "list.bullet.rectangle"
                    )
                }
                .help("Показать/скрыть панель задач")

                Button { showSettings = true } label: {
                    Label("Настройки", systemImage: "gear")
                }
                .help("Настройки")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .alert("ffmpeg не найден", isPresented: $ffmpegMissing) {
            Button("OK") {}
        } message: {
            Text("Запустите в терминале:\n\n./setup.sh\n\nСкрипт скопирует ffmpeg из Homebrew. Если Homebrew не установлен: brew install ffmpeg")
        }
    }

    // MARK: – Actions

    private func convertSelected() {
        guard FFmpegLocator.locate() != nil else { ffmpegMissing = true; return }
        guard let sourceRoot = leftRoot, let destRoot = rightRoot else { return }
        let items = collectSelectedItems(root: sourceRoot, selection: leftSelection)
        guard !items.isEmpty else { return }
        showProgress = true
        engine.enqueue(sources: items, sourceRoot: sourceRoot.url,
                       destinationRoot: destRoot.url, settings: settings)
    }

    private func startConversion(sources: [FileItem]) {
        guard FFmpegLocator.locate() != nil else { ffmpegMissing = true; return }
        guard let destRoot = rightRoot else { return }
        let sourceRoot = leftRoot?.url
            ?? sources.first?.url.deletingLastPathComponent()
            ?? destRoot.url
        showProgress = true
        engine.enqueue(sources: sources, sourceRoot: sourceRoot,
                       destinationRoot: destRoot.url, settings: settings)
    }

    private func navigateRight(to folder: FileItem) {
        settings.rightPath = folder.url.path
        folder.loadChildren(losslessOnly: false)
        rightRoot = folder
    }

    private func collectSelectedItems(root: FileItem, selection: Set<UUID>) -> [FileItem] {
        var result: [FileItem] = []
        func traverse(_ item: FileItem) {
            if selection.contains(item.id) { result.append(item); return }
            item.children?.forEach { traverse($0) }
        }
        traverse(root)
        return result
    }
}
