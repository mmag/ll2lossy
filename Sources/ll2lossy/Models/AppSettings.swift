import Foundation
import Combine

final class AppSettings: ObservableObject {
    // Encoding
    @Published var encodingMode: EncodingMode = .vbr
    @Published var vbrQuality: Int = 0        // 0 = V0 (best), 9 = V9
    @Published var cbrBitrate: Int = 320      // kbps

    // Behaviour
    @Published var preserveMetadata: Bool = true
    @Published var parallelTasks: Int = 4
    @Published var onConflict: ConflictBehavior = .skip

    // Paths
    @Published var leftPath:  String = NSHomeDirectory()
    @Published var rightPath: String = NSHomeDirectory()

    enum EncodingMode: String, CaseIterable, Identifiable {
        case vbr = "VBR"
        case cbr = "CBR"
        var id: String { rawValue }
    }

    enum ConflictBehavior: String, CaseIterable, Identifiable {
        case skip       = "Пропустить"
        case overwrite  = "Перезаписать"
        case suffix     = "Добавить суффикс"
        var id: String { rawValue }
    }
}
