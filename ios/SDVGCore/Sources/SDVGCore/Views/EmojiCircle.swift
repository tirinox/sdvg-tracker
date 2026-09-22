import SwiftUI

/// Colored circle with the item's emoji; shared by the app and the widgets.
public struct EmojiCircle: View {
    public var emoji: String?
    public var color: Int
    public var size: CGFloat

    public init(emoji: String?, color: Int, size: CGFloat = 40) {
        self.emoji = emoji
        self.color = color
        self.size = size
    }

    public var body: some View {
        let c = Palette.color(color)
        Text(emoji ?? "•")
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Circle().fill(c.opacity(0.22)))
            .overlay(Circle().strokeBorder(c.opacity(0.6), lineWidth: 2))
            .accessibilityHidden(true)
    }
}
