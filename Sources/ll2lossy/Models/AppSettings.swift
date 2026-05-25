import Foundation
import Combine

final class AppSettings: ObservableObject {
    // Encoding
    @Published var encodingMode: EncodingMode = .vbr
    @Published var vbrQuality: Int = 0
    @Published var cbrBitrate: Int = 320

    // Behaviour
    @Published var preserveMetadata: Bool = true
    @Published var parallelTasks: Int = 4
    @Published var onConflict: ConflictBehavior = .skip

    // Paths — persisted in UserDefaults; empty = never chosen by user
    @Published var leftPath: String {
        didSet { UserDefaults.standard.set(leftPath,  forKey: "leftPath")  }
    }
    @Published var rightPath: String {
        didSet { UserDefaults.standard.set(rightPath, forKey: "rightPath") }
    }

    init() {
        leftPath  = UserDefaults.standard.string(forKey: "leftPath")  ?? ""
        rightPath = UserDefaults.standard.string(forKey: "rightPath") ?? ""
    }

    enum EncodingMode: String, CaseIterable, Identifiable {
        case vbr = "VBR"
        case cbr = "CBR"
        var id: String { rawValue }
    }

    enum ConflictBehavior: String, CaseIterable, Identifiable {
        case skip      = "Пропустить"
        case overwrite = "Перезаписать"
        case suffix    = "Добавить суффикс"
        var id: String { rawValue }
    }
}
