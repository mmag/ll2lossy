import Foundation

@MainActor
final class TranscodeTask: Identifiable, ObservableObject {
    let id = UUID()
    let sourceURL: URL
    let destinationURL: URL

    @Published private(set) var status: Status = .pending
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var errorMessage: String?

    var name: String { sourceURL.lastPathComponent }
    var relativePath: String { "" } // set externally if needed

    enum Status: Equatable {
        case pending, running, done, error, cancelled
        var label: String {
            switch self {
            case .pending:   return "Ожидание"
            case .running:   return "Конвертация"
            case .done:      return "Готово"
            case .error:     return "Ошибка"
            case .cancelled: return "Отменено"
            }
        }
    }

    init(source: URL, destination: URL) {
        self.sourceURL = source
        self.destinationURL = destination
    }

    // Safe to call from any async context
    nonisolated func setStatus(_ s: Status) {
        Task { @MainActor in self.status = s }
    }
    nonisolated func setProgress(_ p: Double) {
        Task { @MainActor in self.progress = p }
    }
    nonisolated func setError(_ msg: String) {
        Task { @MainActor in
            self.status = .error
            self.errorMessage = msg
        }
    }
}
