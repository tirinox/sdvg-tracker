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
    /// The routine's adherence as the pending check makes it; the tag counts up to it at once.
    @State private var boost: Rules.Adherence?

    private var day: LocalDate { date ?? model.today }
    private var isTask: Bool { item.kind == .task }
    private var doneKey: String { AppModel.doneKey(item, day) }
    /// Checked on tap, before the write: the row stays for a moment and a second tap takes it back.
    private var checking: Bool { model.pendingDone[doneKey] != nil }

    private var high: Bool { item.priority == .high }

    /// What the "being skipped" tag shows, if anything: once the row is checked, the new rate.
    private var lagging: Rules.Adherence? {
        if checking, let boost { return boost }
        guard let a = item.adherence, a.warning, !item.done, !item.skipped else { return nil }
        return a
    }

    private var borderColor: Color {
        switch item.done ? 0 : item.attention {
        case 2: Palette.warn.opacity(0.55)
        case 3, 4: Palette.danger.opacity(0.7)
        default: high ? Palette.color(item.color).opacity(0.45) : Color(.separator).opacity(0.5)
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
                                .font(.body.weight(high ? .bold : item.priority == .low ? .regular : .medium))
                                .foregroundStyle(item.priority == .low ? .secondary : .primary)
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
                    .accessibilityLabel(item.skipped ? tr("Вернуть", "Undo skip") : tr("Пропустить сегодня", "Skip today"))
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
                .accessibilityLabel(item.done || checking ? tr("Снять отметку", "Mark not done") : tr("Готово", "Mark done"))
            }
            if item.attention >= 4 && !item.done && isTask {
                FlowLayout(spacing: 6) {
                    Text(tr("Застряла?", "Stuck?")).font(.footnote.weight(.semibold)).foregroundStyle(Palette.danger)
                        .padding(.vertical, 4)
                    Button(tr("Разбить на шаги", "Break into steps")) { edit() }
                    Button(tr("Во входящие", "Move to Inbox")) { model.perform { try $0.updateTask(item.refID, ["date": nil]) } }
                    Button(tr("Удалить", "Delete"), role: .destructive) { model.perform { try $0.deleteTask(item.refID) } }
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
        .overlay {
            if high { PriorityMarks(color: item.color, key: item.id, pulse: !item.done && !item.skipped) }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(borderColor, lineWidth: item.attention >= 3 && !item.done ? 1.5 : 1))
        .opacity(item.done || item.skipped ? 0.55 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: checking)
        .onChange(of: checking) { _, on in
            if !on { boost = nil }
        }
    }

    @ViewBuilder private var meta: some View {
        let timing = Fmt.timing(item.timing, duration: item.durationMin)
        let deadline = Fmt.deadline(item, today: model.today)
        HStack(spacing: 6) {
            if high { Tag(text: Fmt.priorityTag, fg: Palette.text(item.color), bg: Palette.color(item.color).opacity(0.24)) }
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
            if let a = lagging, let percent = a.percent {
                AdherenceTag(percent: percent, warning: a.warning)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(a.warning
                        ? tr("Рутина пропускается: \(Fmt.adherence(a))", "Routine being skipped: \(Fmt.adherence(a))")
                        : tr("Рутина снова выполняется: \(Fmt.adherence(a))", "Routine back on track: \(Fmt.adherence(a))"))
            }
            if item.skipped { Text(tr("пропущено", "skipped")).font(.footnote).foregroundStyle(.secondary) }
            if item.priority == .low && !item.done && !item.skipped {
                Text(Fmt.lowPriority).font(.footnote).foregroundStyle(.secondary)
            }
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
        if lagging != nil {
            boost = try? model.store.loadRoutineAdherence(item.refID, today: model.today, doneOn: day)
        }
        model.markDone(item, on: day)
    }

    private func setCheck(_ status: CheckStatus?) {
        model.perform { [item, day] in try $0.setRoutineCheck(item.refID, date: day, status: status) }
    }
}

/// How regularly a routine is done, on the row of one that is being skipped. When a check moves the
/// rate, the number counts to the new one; out of the warning zone it turns green with a thumbs up.
struct AdherenceTag: View {
    var percent: Int
    var warning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double
    /// Green with a thumbs up; follows `warning` once the count has got there.
    @State private var ok: Bool

    init(percent: Int, warning: Bool) {
        self.percent = percent
        self.warning = warning
        _shown = State(initialValue: Double(percent))
        _ok = State(initialValue: !warning)
    }

    var body: some View {
        let color = ok ? Palette.ok : Palette.warn
        HStack(spacing: 3) {
            ZStack {
                if ok {
                    Image(systemName: "hand.thumbsup.fill")
                        .transition(.scale(scale: 0.1, anchor: .bottom).combined(with: .opacity))
                } else {
                    Text(verbatim: "⚠︎").transition(.opacity)
                }
            }
            CountingPercent(value: shown)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.14)))
        .foregroundStyle(color)
        .onChange(of: percent) { _, target in
            let warning = warning
            guard !reduceMotion else {
                shown = Double(target)
                ok = !warning
                return
            }
            // Back into the warning zone (the check was taken back): the thumbs up goes at once.
            if warning { withAnimation(.snappy(duration: 0.2)) { ok = false } }
            // The count takes longer the further the percent goes.
            withAnimation(.easeOut(duration: min(0.7, 0.2 + 0.05 * abs(Double(target) - shown)))) {
                shown = Double(target)
            } completion: {
                // Unless the number has been sent elsewhere meanwhile.
                guard !warning, shown == Double(target) else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { ok = true }
            }
        }
    }
}

/// A whole percent; animated, it counts through the numbers in between.
private struct CountingPercent: View, Animatable {
    var value: Double

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(Int(value.rounded()))\u{00A0}%").monospacedDigit()
    }
}

/// High priority, in the item's own color: a stripe on the left and a ring pulsing out of the row
/// now and then (not with Reduce Motion). Neighbouring rows start their pulses at different moments.
struct PriorityMarks: View {
    var color: Int
    /// Picks the pulse's start, so rows do not pulse in step.
    var key: String
    var pulse: Bool
    /// 0 for a List row background: the cell clips, so the pulse glows inside the row instead.
    var cornerRadius: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false

    var body: some View {
        let c = Palette.color(color)
        ZStack {
            Rectangle().fill(c).frame(width: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            if pulse && !reduceMotion && started {
                // t: 0 when the ring leaves the border, 1 when it has faded out.
                Color.clear.keyframeAnimator(initialValue: 1.0, repeating: true) { content, t in
                    content.overlay {
                        if cornerRadius > 0 {
                            let w = 7 * t
                            RoundedRectangle(cornerRadius: cornerRadius + w / 2)
                                .stroke(c.opacity(0.55 * (1 - t)), lineWidth: w)
                                .padding(-w / 2)
                        } else {
                            Rectangle().fill(c.opacity(0.18 * (1 - t)))
                        }
                    }
                } keyframes: { _ in
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 1.35, timingCurve: .easeOut)
                    LinearKeyframe(1, duration: 1.65)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            let h = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
            try? await Task.sleep(for: .milliseconds(h % 7 * 500))
            started = true
        }
    }
}
