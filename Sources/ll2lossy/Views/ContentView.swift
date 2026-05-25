import SwiftUI
import AppKit

@MainActor
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = TranscodeEngine()

    @State private var leftRoot:  FileItem?
    @State private var rightRoot: FileItem?
    @State private var leftSelection: Set<UUID> = []
    @State private var showProgress  = false
    @State private var showSettings  = false
    @State private var ffmpegMissing = false
    @State private var scanMessage: String?

    private var canConvert: Bool {
        !leftSelection.isEmpty && rightRoot != nil
    }

    // MARK: – Status bar

    private var statusBar: some View {
        HStack(spacing: 0) {
            Text(leftStatusText)
                .foregroundStyle(.secondary)
            Spacer()
            Text(rightStatusText)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var leftStatusText: String {
        if let msg = scanMessage { return "Сканирование: \(msg)" }
        guard !leftSelection.isEmpty else { return "" }
        return "Выбрано: \(leftSelection.count)"
    }

    private var rightStatusText: String {
        let total = engine.tasks.count
        guard total > 0 else { return "" }
        let done = engine.tasks.filter { $0.status == .done }.count
        return engine.isRunning
            ? "Конвертация: \(done) / \(total)"
            : "Сконвертировано: \(done) / \(total)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main two-panel area
            HStack(spacing: 0) {
                FileBrowserView(
                    title: "Источник",
                    losslessOnly: true,
                    eagerLoad: true,
                    path: $settings.leftPath,
                    root: $leftRoot,
                    selection: $leftSelection,
                    onConvertDrop: nil,
                    onNavigateToFolder: nil,
                    scanMessage: $scanMessage
                )

                centerStrip

                FileBrowserView(
                    title: "Назначение",
                    losslessOnly: false,
                    eagerLoad: false,
                    path: $settings.rightPath,
                    root: $rightRoot,
                    selection: .constant([]),
                    onConvertDrop: { items in startConversion(sources: items) },
                    onNavigateToFolder: { folder in navigateRight(to: folder) }
                )
            }
            .padding(10)

            // Status bar
            Divider()
            statusBar

            // Progress drawer
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

    // MARK: – Center strip with convert button

    private var centerStrip: some View {
        VStack {
            Spacer()
            Button(action: convertSelected) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canConvert ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
            }
            .buttonStyle(.plain)
            .disabled(!canConvert)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Конвертировать выбранное (⌘↩)")
            Spacer()
        }
        .frame(width: 56)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .leading)
        .overlay(Divider(), alignment: .trailing)
    }

    // MARK: – Actions

    private func convertSelected() {
        guard FFmpegLocator.locate() != nil else { ffmpegMissing = true; return }
        guard let sourceRoot = leftRoot, let destRoot = rightRoot else { return }
        let items = collectSelectedFiles(root: sourceRoot)
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

    /// Collects all lossless FileItems whose IDs are in leftSelection.
    private func collectSelectedFiles(root: FileItem) -> [FileItem] {
        var result: [FileItem] = []
        func traverse(_ item: FileItem) {
            if !item.isDirectory && item.isLossless && leftSelection.contains(item.id) {
                result.append(item)
                return
            }
            item.children?.forEach { traverse($0) }
        }
        root.children?.forEach { traverse($0) }
        return result
    }
}
