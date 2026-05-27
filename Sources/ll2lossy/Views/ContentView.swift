import SwiftUI
import AppKit

@MainActor
struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var engine = TranscodeEngine()
    @StateObject private var previewPlayer = AudioPreviewPlayer()

    @State private var leftRoot:  FileItem?
    @State private var rightRoot: FileItem?
    @State private var leftSelection:  Set<URL> = []
    @State private var rightSelection: Set<URL> = []
    @State private var showProgress  = false
    @State private var showSettings  = false
    @State private var ffmpegMissing = false

    @State private var selectedFileCount: Int? = nil
    @State private var fileCountTask: Task<Void, Never>? = nil

    private var canConvert: Bool {
        !leftSelection.isEmpty && rightRoot != nil
    }

    // MARK: – Command and status

    private var commandBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Подготовка конвертации")
                    .font(.headline)
                Text(commandSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: primaryCommand) {
                Label(primaryCommandTitle, systemImage: primaryCommandIcon)
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(engine.isRunning ? Color(red: 0.82, green: 0.20, blue: 0.16) : Color.accentColor)
            .disabled(primaryCommandDisabled)
            .keyboardShortcut(.return, modifiers: .command)
            .help(primaryCommandHelp)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var primaryCommandTitle: String {
        if engine.isStopping { return "Прерывается" }
        return engine.isRunning ? "Прервать" : "Конвертировать"
    }

    private var primaryCommandIcon: String {
        if engine.isStopping { return "hourglass" }
        return engine.isRunning ? "pause.circle.fill" : "arrow.right.circle.fill"
    }

    private var primaryCommandDisabled: Bool {
        engine.isRunning ? engine.isStopping : !canConvert
    }

    private var primaryCommandHelp: String {
        engine.isRunning
            ? "Остановить очередь после текущей партии файлов"
            : "Конвертировать выбранное (⌘↩)"
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if engine.tasks.isEmpty {
                    Label(leftStatusText.isEmpty ? "Очередь пуста" : leftStatusText,
                          systemImage: leftStatusText.isEmpty ? "tray" : "checklist")
                        .foregroundStyle(.secondary)
                } else {
                    Label(rightStatusText, systemImage: engine.isRunning ? "arrow.2.circlepath" : "checkmark.circle")
                        .foregroundStyle(engine.isRunning ? Color.accentColor : .secondary)
                }

                Spacer()

                if !engine.tasks.isEmpty {
                    Button {
                        withAnimation { showProgress.toggle() }
                    } label: {
                        Label(showProgress ? "Скрыть очередь" : "Показать очередь",
                              systemImage: showProgress ? "chevron.down" : "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            if engine.isRunning || (engine.overallProgress > 0 && engine.overallProgress < 1) {
                ProgressView(value: engine.overallProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var commandSummary: String {
        let source = leftStatusText.isEmpty ? "выберите источник" : leftStatusText.lowercased()
        let destination: String
        if let rightRoot {
            destination = rightRoot.url.path
        } else if settings.rightPath.isEmpty {
            destination = "выберите папку назначения"
        } else {
            destination = settings.rightPath
        }
        return "\(source) -> \(destination)"
    }

    private var leftStatusText: String {
        guard !leftSelection.isEmpty else { return "" }
        if let n = selectedFileCount { return "К конвертации: \(n) файлов" }
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
            commandBar
            Divider()

            HStack(spacing: 12) {
                FileBrowserView(
                    title: "Источник",
                    subtitle: "Lossless-аудио для обработки",
                    losslessOnly: true,
                    previewPlayer: previewPlayer,
                    path: $settings.leftPath,
                    root: $leftRoot,
                    selection: $leftSelection,
                    onConvertDrop: nil,
                    onNavigateToFolder: nil
                )

                FileBrowserView(
                    title: "Назначение",
                    subtitle: "Папка для MP3 и готовых файлов",
                    losslessOnly: false,
                    previewPlayer: previewPlayer,
                    path: $settings.rightPath,
                    root: $rightRoot,
                    selection: $rightSelection,
                    onConvertDrop: { items in startConversion(sources: items) },
                    onNavigateToFolder: nil,
                    onMoveToFolder: { folder, providers in moveItems(providers, to: folder) }
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusBar

            if showProgress {
                Divider()
                ProgressDrawerView(engine: engine)
                    .frame(minHeight: 140, maxHeight: 260)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: showProgress)
        .onChange(of: leftSelection) { _, sel in
            selectedFileCount = nil
            fileCountTask?.cancel()
            guard !sel.isEmpty else { return }
            fileCountTask = Task.detached(priority: .utility) {
                var total = 0
                for url in sel {
                    if Task.isCancelled { return }
                    total += collectLosslessURLs(from: url).count
                }
                let result = total
                if !Task.isCancelled {
                    await MainActor.run { selectedFileCount = result }
                }
            }
        }
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

    // MARK: – Actions

    private func primaryCommand() {
        if engine.isRunning {
            engine.stopAfterCurrentBatch()
        } else {
            convertSelected()
        }
    }

    private func convertSelected() {
        guard FFmpegLocator.locate() != nil else { ffmpegMissing = true; return }
        guard let sourceRoot = leftRoot, let destRoot = rightRoot else { return }
        guard !leftSelection.isEmpty else { return }
        showProgress = true
        engine.enqueue(sources: Array(leftSelection),
                       sourceRoot: sourceRoot.url,
                       destinationRoot: destRoot.url,
                       settings: settings)
    }

    private func startConversion(sources: [FileItem]) {
        guard FFmpegLocator.locate() != nil else { ffmpegMissing = true; return }
        guard let destRoot = rightRoot else { return }
        let sourceRoot = leftRoot?.url
            ?? sources.first?.url.deletingLastPathComponent()
            ?? destRoot.url
        showProgress = true
        engine.enqueue(sources: sources.map { $0.url },
                       sourceRoot: sourceRoot,
                       destinationRoot: destRoot.url,
                       settings: settings)
    }

    private func navigateRight(to folder: FileItem) {
        settings.rightPath = folder.url.path
        folder.loadChildren(losslessOnly: false)
        rightRoot = folder
    }

    private func moveItems(_ providers: [NSItemProvider], to folder: FileItem) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
                else if let url = item as? URL { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard let rightURL = self.rightRoot?.url else { return }
            var moved = false
            for url in urls {
                guard url.path.hasPrefix(rightURL.path + "/") || url.path == rightURL.path else { continue }
                guard url != folder.url, !folder.url.path.hasPrefix(url.path + "/") else { continue }
                let dest = folder.url.appendingPathComponent(url.lastPathComponent)
                guard url != dest else { continue }
                try? FileManager.default.moveItem(at: url, to: dest)
                moved = true
            }
            if moved { self.reloadRight() }
        }
    }

    private func reloadRight() {
        guard !settings.rightPath.isEmpty else { return }
        let url = URL(fileURLWithPath: settings.rightPath)
        rightSelection = []
        let item = FileItem(url: url)
        rightRoot = item
        Task { await item.loadChildrenAsync(losslessOnly: false) }
    }
}
