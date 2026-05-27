import SwiftUI

struct ProgressDrawerView: View {
    @ObservedObject var engine: TranscodeEngine

    private var doneCount:  Int { engine.tasks.filter { $0.status == .done }.count }
    private var errorCount: Int { engine.tasks.filter { $0.status == .error }.count }
    private var total:      Int { engine.tasks.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("Конвертация")
                            .font(.headline)
                        Spacer()
                        if total > 0 {
                            Text("\(doneCount) из \(total) файлов")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text("\(Int(engine.overallProgress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if total > 0 {
                        ProgressView(value: engine.overallProgress)
                            .progressViewStyle(.linear)
                    }
                }
                .frame(maxWidth: .infinity)

                if engine.isRunning {
                    Button("Отменить все", role: .destructive) { engine.cancelAll() }
                        .buttonStyle(.borderless)
                        .fixedSize()
                } else if !engine.tasks.isEmpty {
                    Button("Очистить") { engine.clearCompleted() }
                        .buttonStyle(.borderless)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            if errorCount > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Ошибок: \(errorCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.07))
            }

            Divider()

            if engine.tasks.isEmpty {
                Text("Нет задач")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(engine.tasks) { task in
                            TaskRowView(task: task, engine: engine)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TaskRowView: View {
    @ObservedObject var task: TranscodeTask
    let engine: TranscodeEngine

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            statusIcon
                .frame(width: 16, height: 16)

            // File name + progress
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.system(size: 12))
                    .lineLimit(1)

                if task.status == .running {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                } else if task.status == .error, let msg = task.errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    Text(task.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Percentage or cancel
            if task.status == .running {
                Text("\(Int(task.progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)

                Button {
                    engine.cancel(id: task.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .scaleEffect(0.6)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.orange)
        }
    }
}
