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

    @State private var pops = 0
    @State private var checkFrame = CGRect.zero

    private var day: LocalDate { date ?? model.today }
    private var isTask: Bool { item.kind == .task }
    private var doneKey: String { AppModel.doneKey(item, day) }
    /// Checked on tap, before the write: the row stays for a moment and a second tap takes it back.
    private var checking: Bool { model.pendingDone[doneKey] != nil }

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
                    Button {
                        hideKeyboard()
                        setCheck(item.skipped ? nil : .skipped)
                    } label: {
                        Image(systemName: item.skipped ? "arrow.uturn.backward" : "forward.end")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(item.skipped ? "Вернуть" : "Пропустить сегодня")
                }
                Button(action: toggleDone) {
                    let checked = item.done || checking
                    Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30))
                        .foregroundStyle(checked ? Palette.ok : Color(.tertiaryLabel))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: pops)
                        // A ring ripples out of the check.
                        .keyframeAnimator(initialValue: 0.0, trigger: pops) { content, t in
                            content.background {
                                Circle().stroke(Palette.ok, lineWidth: 2)
                                    .scaleEffect(1 + t * 0.9)
                                    .opacity(t > 0 && t < 1 ? (1 - t) * 0.8 : 0)
                            }
                        } keyframes: { _ in
                            LinearKeyframe(1, duration: 0.55, timingCurve: .easeOut)
                        }
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: pops)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { checkFrame = $0 }
                .disabled(!isTask && day > model.today)
                .accessibilityLabel(item.done || checking ? "Снять отметку" : "Готово")
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
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground))
                // A green flash while the check plays.
                RoundedRectangle(cornerRadius: 14).fill(Palette.ok.opacity(checking ? 0.14 : 0))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor, lineWidth: item.attention >= 3 && !item.done ? 1.5 : 1))
        .opacity(item.done || item.skipped ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: checking)
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
            if let a = item.adherence, a.warning, let percent = a.percent, !item.done, !item.skipped {
                Tag(text: "⚠︎ \(percent)\u{00A0}%", fg: Palette.warn, bg: Palette.warn.opacity(0.14))
                    .accessibilityLabel("Рутина пропускается: \(Fmt.adherence(a))")
            }
            if item.skipped { Text("пропущено").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func edit() {
        isTask ? model.openTask(item.refID) : model.openRoutine(item.refID)
    }

    private func toggleDone() {
        // Checking things off, not typing any more.
        hideKeyboard()
        if model.pendingDone[doneKey] == .waiting {
            model.cancelDone(doneKey)
            return
        }
        guard !checking else { return }
        if item.done {
            isTask ? model.perform { [item] in try $0.reopenTask(item.refID) } : setCheck(nil)
            return
        }
        pops += 1
        let level = isTask ? Rules.celebrationLevel(moves: item.moves) : 0
        if level > 0 {
            model.doneCelebration = DoneCelebration(
                level: level, moves: item.moves, origin: CGPoint(x: checkFrame.midX, y: checkFrame.midY))
        }
        model.markDone(item, on: day)
    }

    private func setCheck(_ status: CheckStatus?) {
        model.perform { [item, day] in try $0.setRoutineCheck(item.refID, date: day, status: status) }
    }
}
