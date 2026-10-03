import SDVGCore
import SwiftUI

/// Titles of earlier tasks matching what is typed: tap a row to pick it,
/// ↖ (when `onFill` is set) puts the title into the field for editing.
struct TitleSuggestions: View {
    var items: [Rules.TitleSuggestion]
    var onPick: (Rules.TitleSuggestion) -> Void
    var onFill: ((Rules.TitleSuggestion) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items, id: \.title) { s in
                HStack(spacing: 4) {
                    Button { onPick(s) } label: {
                        HStack(spacing: 10) {
                            EmojiCircle(emoji: s.emoji, color: s.color, size: 28)
                            Text(s.title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    if let onFill {
                        Button { onFill(s) } label: {
                            Image(systemName: "arrow.up.left").frame(width: 36, height: 36).contentShape(Rectangle())
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(tr("Вставить в поле", "Put into the field"))
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                if s != items.last { Divider().padding(.leading, 38) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("Из прошлых задач", "From past tasks"))
    }
}

extension TaskDraft {
    /// Title and look of an earlier task; its duration only if it had one.
    mutating func apply(_ s: Rules.TitleSuggestion) {
        title = s.title
        emoji = s.emoji
        color = s.color
        if let d = s.durationMin { durationMin = d }
    }
}

/// Under the title of a new task (Rules.checkTitle): taken by an open task or routine, done today with
/// the numbered title offered, or similar to another one. A tap on a listed item opens it.
struct TitleCheckNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var check: Rules.TitleCheck
    /// Bumped when adding is refused: the notice shakes.
    var nudges = 0
    /// The numbered title offered for a task done today is taken.
    var onNumbered: (String) -> Void
    /// Called before a listed item is opened.
    var onOpen: () -> Void = {}

    var body: some View {
        content
            .font(.subheadline)
            .keyframeAnimator(initialValue: 0.0, trigger: nudges) { content, x in
                content.offset(x: reduceMotion ? 0 : x)
            } keyframes: { _ in
                LinearKeyframe(-6, duration: 0.07)
                LinearKeyframe(6, duration: 0.1)
                LinearKeyframe(-3, duration: 0.1)
                LinearKeyframe(0, duration: 0.08)
            }
            .sensoryFeedback(.warning, trigger: nudges)
    }

    @ViewBuilder private var content: some View {
        switch check {
        case .taken(let item):
            HStack(spacing: 8) {
                Text(item.kind == .task
                    ? tr("Такая задача уже есть \(place(item))", "Already on your list \(place(item))")
                    : tr("Такая рутина уже есть", "There is a routine with this name"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(tr("Открыть", "Open")) { open(item) }.fontWeight(.semibold)
            }
            .foregroundStyle(Palette.caution)
            .box(Palette.cautionFill)
        case .doneToday(let item, let next):
            VStack(alignment: .leading, spacing: 6) {
                Text("✓ " + (item.kind == .task
                    ? tr("Такая задача уже сделана сегодня", "Already done today")
                    : tr("Эта рутина уже сделана сегодня", "This routine is already done today")))
                Button { onNumbered(next) } label: {
                    Text(tr("Добавить «\(next)»", "Add “\(next)”")).lineLimit(1)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .box(Color.accentColor.opacity(0.12))
        case .free(let similar) where !similar.isEmpty:
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Похожая уже есть:", "A similar one exists:")).foregroundStyle(.secondary)
                ForEach(similar, id: \.id) { item in
                    Button { open(item) } label: {
                        HStack(spacing: 8) {
                            EmojiCircle(emoji: item.emoji, color: item.color, size: 24)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(place(item)).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(tr("Открыть", "Open"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .box(Color(.tertiarySystemFill))
        case .free:
            EmptyView()
        }
    }

    private func place(_ i: Rules.ListedItem) -> String {
        let today = model.today
        guard i.kind == .task else { return tr("рутина", "routine") }
        guard let d = i.date else { return tr("во входящих", "in the inbox") }
        if d <= today { return tr("на сегодня", "for today") }
        if d == Dates.addDays(today, 1) { return tr("на завтра", "for tomorrow") }
        return tr("на \(Fmt.shortDate(d))", "for \(Fmt.shortDate(d))")
    }

    private func open(_ i: Rules.ListedItem) {
        onOpen()
        if i.kind == .task { model.openTask(i.id) } else { model.openRoutine(i.id) }
    }
}

private extension View {
    func box(_ fill: Color) -> some View {
        padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 10).fill(fill))
    }
}
