import SwiftUI
import AppKit

struct PathBarView: View {
    @Binding var path: String
    let onPathChanged: (URL) -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("Путь к папке", text: $path)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { commitPath() }

            Button(action: browse) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Выбрать папку")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Выберите папку"
        panel.prompt = "Открыть"
        if let current = URL(string: path), FileManager.default.fileExists(atPath: current.path) {
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
