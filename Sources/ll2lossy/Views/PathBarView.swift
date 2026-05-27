import SwiftUI
import AppKit

struct PathBarView: View {
    @Binding var path: String
    let onPathChanged: (URL) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Путь к папке", text: $path)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { commitPath() }
                .lineLimit(1)

            Button(action: browse) {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Выбрать папку")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.textBackgroundColor).opacity(0.75))
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Выберите папку"
        panel.prompt = "Открыть"
        let current = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: current.path) {
            panel.directoryURL = current
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        onPathChanged(url)
    }

    private func commitPath() {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            onPathChanged(url)
        }
    }
}
