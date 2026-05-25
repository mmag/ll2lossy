import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            // Encoding
            Section("Кодирование") {
                Picker("Режим", selection: $settings.encodingMode) {
                    ForEach(AppSettings.EncodingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settings.encodingMode == .vbr {
                    HStack {
                        Text("Качество VBR")
                        Spacer()
                        Picker("", selection: $settings.vbrQuality) {
                            ForEach(0...9, id: \.self) { q in
                                Text("V\(q)\(q == 0 ? " (лучшее)" : q == 9 ? " (наименьшее)" : "")").tag(q)
                            }
                        }
                        .frame(width: 180)
                    }
                } else {
                    HStack {
                        Text("Битрейт")
                        Spacer()
                        Picker("", selection: $settings.cbrBitrate) {
                            ForEach([128, 192, 256, 320], id: \.self) { br in
                                Text("\(br) кбит/с").tag(br)
                            }
                        }
                        .frame(width: 130)
                    }
                }
            }

            // Metadata
            Section("Метаданные") {
                Toggle("Сохранять теги (ID3)", isOn: $settings.preserveMetadata)
            }

            // Conflicts
            Section("При совпадении имён") {
                Picker("", selection: $settings.onConflict) {
                    ForEach(AppSettings.ConflictBehavior.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            // Performance
            Section("Производительность") {
                HStack {
                    Text("Параллельных задач")
                    Spacer()
                    Stepper("\(settings.parallelTasks)", value: $settings.parallelTasks, in: 1...16)
                }
            }

            // Advanced
            Section("Дополнительно") {
                HStack {
                    Text("Путь к ffmpeg")
                    TextField("Авто-определение", text: $settings.ffmpegPath)
                        .textFieldStyle(.roundedBorder)
                }
                if let path = FFmpegLocator.locate(override: settings.ffmpegPath) {
                    Text("Найден: \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("ffmpeg не найден. Установите: brew install ffmpeg")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
