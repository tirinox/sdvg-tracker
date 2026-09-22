import SDVGCore
import SwiftUI

/// One task or routine. Attention grows with the number of postpones.
struct ItemRow: View {
    @Environment(AppModel.self) private var model
    var item: DayItem
    /// Day the row is shown on (routine marks go to this day).
    var date: LocalDate?
    /// Show the timing hint (Now screen).
    var showHint = false

    private var day: LocalDate { date ?? model.today }
    private var isTask: Bool { item.kind == .task }

    private var borderColor: Color {
        switch item.done ? 0 : item.attention {
        case 2: Palette.warn.opacity(0.55)
        case 3, 4: Palette.danger.opacity(0.7)
        default: Color(.separator).opacity(0.5)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { edit() } label: {
                    HStack(spacing: 12) {
                        EmojiCircle(emoji: item.emoji, color: item.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                                .strikethrough(item.done)
                                .multilineTextAlignment(.leading)
                            meta
                            if showHint, let hint = Fmt.nowHint(item, now: model.now, today: model.today) {
                                Tag(text: hint, fg: .accentColor, bg: Color.accentColor.opacity(0.13))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isTask && !item.done {
                    Button { setCheck(item.skipped ? nil : .skipped) } label: {
                        Image(systemName: item.skipped ? "arrow.uturn.backward" : "forward.end")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(item.skipped ? "Вернуть" : "Пропустить сегодня")
                }
                Button(action: toggleDone) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30))
                        .foregroundStyle(item.done ? Palette.ok : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)
                .disabled(!isTask && day > model.today)
                .accessibilityLabel(item.done ? "Снять отметку" : "Готово")
            }
            if item.attention >= 4 && !item.done && isTask {
                FlowLayout(spacing: 6) {
                    Text("Застряла?").font(.footnote.weight(.semibold)).foregroundStyle(Palette.danger)
                        .padding(.vertical, 4)
                    Button("Разбить на шаги") { edit() }
                    Button("Во входящие") { model.perform { try $0.updateTask(item.refID, ["date": nil]) } }
                    Button("Удалить", role: .destructive) { model.perform { try $0.deleteTask(item.refID) } }
                }
                .font(.footnote)
                .lineLimit(1)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.leading, 52)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor, lineWidth: item.attention >= 3 && !item.done ? 1.5 : 1))
        .opacity(item.done || item.skipped ? 0.55 : 1)
    }

    @ViewBuilder private var meta: some View {
        let timing = Fmt.timing(item.timing, duration: item.durationMin)
        let deadline = Fmt.deadline(item, today: model.today)
        HStack(spacing: 6) {
            if !isTask { Image(systemName: "repeat").font(.caption2).foregroundStyle(.tertiary) }
            if !timing.isEmpty { Text(timing).font(.footnote).foregroundStyle(.secondary) }
            if !deadline.isEmpty && !item.done {
                switch item.deadline {
                case .soon: Tag(text: deadline, fg: Palette.warn, bg: Palette.warn.opacity(0.14))
                case .today, .overdue: Tag(text: deadline, fg: Palette.danger, bg: Palette.danger.opacity(0.14))
                default: Tag(text: deadline, fg: .secondary, bg: Color(.tertiarySystemFill))
                }
            }
            if item.moves > 0 && !item.done {
                switch item.attention {
                case 3, 4: Tag(text: "↻ \(item.moves)", fg: .white, bg: Palette.danger)
                case 2: Tag(text: "↻ \(item.moves)", fg: Palette.warn, bg: Palette.warn.opacity(0.14))
                default: Tag(text: "↻ \(item.moves)", fg: .secondary, bg: Color(.tertiarySystemFill))
                }
            }
            if item.skipped { Text("пропущено").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func edit() {
        isTask ? model.openTask(item.refID) : model.openRoutine(item.refID)
    }

    private func toggleDone() {
        let today = model.today
        if isTask {
            model.perform { [item] in try item.done ? $0.reopenTask(item.refID) : $0.completeTask(item.refID, today: today) }
        } else {
            setCheck(item.done ? nil : .done)
        }
    }

    private func setCheck(_ status: CheckStatus?) {
        model.perform { [item, day] in try $0.setRoutineCheck(item.refID, date: day, status: status) }
    }
}
