import SDVGCore
import SwiftUI

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxW = max(maxW, x - spacing)
        }
        return (points, maxW, y + rowH)
    }
}

struct Chip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)))
                .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: 1))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct Tag: View {
    var text: String
    var fg: Color
    var bg: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(bg))
            .foregroundStyle(fg)
    }
}

/// Hides the keyboard, whichever field has it.
@MainActor func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// A routine's last days as a row of squares, oldest first: green done, red missed, grey skipped,
/// hollow for today not marked yet, faint for days off.
struct DayMarks: View {
    var marks: [Rules.DayMark]
    /// Squares stretch to fill the width (the month in the editor) instead of staying tiny.
    var big = false

    var body: some View {
        HStack(spacing: big ? 3 : 2) {
            ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                let shape = RoundedRectangle(cornerRadius: big ? 3 : 1.5)
                Group {
                    switch mark {
                    case .done: shape.fill(Palette.ok)
                    case .missed: shape.fill(Palette.danger)
                    case .skipped: shape.fill(Color(.tertiaryLabel))
                    case .pending: shape.strokeBorder(Color(.tertiaryLabel), lineWidth: 1)
                    case .off: shape.fill(Color(.quaternarySystemFill))
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: big ? 16 : 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tr(
            "Последние \(marks.count) дн.: сделано \(count(.done)), не сделано \(count(.missed)), пропущено \(count(.skipped))",
            "Last \(marks.count) days: \(count(.done)) done, \(count(.missed)) missed, \(count(.skipped)) skipped"))
    }

    func count(_ mark: Rules.DayMark) -> Int { marks.filter { $0 == mark }.count }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }
}

struct QuickAdd: View {
    @Environment(AppModel.self) private var model
    var date: LocalDate?
    var placeholder = tr("Добавить задачу", "Add a task")
    @State private var title = ""
    @State private var history: [Rules.TitleGroup] = []
    /// Open tasks, routines and what is done today: the title is checked against them (Rules.checkTitle).
    @State private var listed: [Rules.ListedItem] = []
    /// Adding a taken title was refused; the notice shakes.
    @State private var nudges = 0
    /// A suggestion put into the field with ↖; its look is kept while the title is being edited.
    @State private var filled: Rules.TitleSuggestion?
    @FocusState private var focused: Bool
    /// Where the field is in its scroll view.
    @State private var fieldY: CGFloat = 0
    /// Where it was once the keyboard came up; nil while the keyboard is down.
    @State private var restY: CGFloat?
    /// Tasks changed while typing: rows added above may have moved the field, so it's measured anew.
    @State private var listChanged = false

    var body: some View {
        let suggestions = focused ? Rules.suggestTitles(Rules.withoutTaken(history, listed), query: title) : []
        let check = Rules.checkTitle(listed, title: title)
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $title)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
                Button {
                    model.openTask(nil, draft: draft(title))
                    title = ""
                } label: {
                    Image(systemName: "plus").frame(width: 40, height: 40)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(tr("Новая задача подробно", "New task with details"))
            }
            if !check.isClear {
                TitleCheckNotice(check: check, nudges: nudges, onNumbered: { title = $0; add() }, onOpen: { title = "" })
                    .padding(.trailing, 48)
            }
            if !suggestions.isEmpty {
                TitleSuggestions(items: suggestions, onPick: pick, onFill: { filled = $0; title = $0.title })
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.trailing, 48)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { y in
            fieldY = y
            guard let rest = restY else { return }
            if listChanged {
                restY = y
                listChanged = false
            } else if abs(rest - y) > 120 {
                // Scrolled well away, either way (on Now the list is above the field): the keyboard would only cover it.
                focused = false
            }
        }
        // Counted from here, so the scroll that brings the field above the keyboard doesn't hide it.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            if focused {
                restY = fieldY
                listChanged = false
            }
        }
        .onChange(of: focused) {
            if focused { loadHistory() } else { restY = nil }
        }
        .onChange(of: model.revision) {
            if restY != nil { listChanged = true }
            if !title.isEmpty { loadListed() }
        }
        .onChange(of: title) { old, new in
            if new.trimmingCharacters(in: .whitespaces).isEmpty { filled = nil }
            // A new title starts: re-read, so tasks added a moment ago are suggested too.
            else if old.trimmingCharacters(in: .whitespaces).isEmpty { loadHistory() }
        }
    }

    private func draft(_ title: String) -> TaskDraft {
        var d = TaskDraft(title: title, date: date)
        if let filled {
            d.apply(filled)
            d.title = title
        }
        return d
    }

    /// Not under a title that is taken or done today: the notice says why, and offers a numbered one for the latter.
    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        loadListed()
        switch Rules.checkTitle(listed, title: t) {
        case .free:
            model.createTask(draft(t))
            title = ""
        case .taken:
            nudges += 1
        case .doneToday:
            break
        }
    }

    /// A suggestion is added right away, looking like the last time; if it was done today, it waits in the field.
    private func pick(_ s: Rules.TitleSuggestion) {
        filled = s
        title = s.title
        add()
    }

    private func loadHistory() {
        history = (try? model.store.loadTitleHistory(today: model.today)) ?? []
        loadListed()
    }

    private func loadListed() {
        listed = (try? model.store.loadListed(today: model.today)) ?? []
    }
}
