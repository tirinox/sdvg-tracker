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
