import SDVGCore
import SwiftUI

struct EmojiCircle: View {
    var emoji: String?
    var color: Int
    var size: CGFloat = 40

    var body: some View {
        let c = Palette.color(color)
        Text(emoji ?? "•")
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Circle().fill(c.opacity(0.22)))
            .overlay(Circle().strokeBorder(c.opacity(0.6), lineWidth: 2))
            .accessibilityHidden(true)
    }
}

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
    var placeholder = "Добавить задачу"
    @State private var title = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $title)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemGroupedBackground)))
            Button {
                model.openTask(nil, draft: TaskDraft(title: title, date: date))
                title = ""
            } label: {
                Image(systemName: "plus").frame(width: 40, height: 40)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Новая задача подробно")
        }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        model.perform { try $0.createTask(TaskDraft(title: t, date: date)) }
        title = ""
    }
}
