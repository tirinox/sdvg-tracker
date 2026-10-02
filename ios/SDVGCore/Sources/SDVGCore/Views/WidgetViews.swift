import SwiftUI

public enum WidgetSize: Sendable { case small, medium, large }
public enum LockWidgetSize: Sendable { case circular, rectangular, inline }

/// One badge per row: time, deadline or postpone count — never all three.
struct WidgetBadge: View {
    var item: WidgetSnapshot.Item

    var body: some View {
        if let text = item.badge {
            let color: Color = switch item.badgeKind {
            case .deadline: Palette.danger
            case .moves: item.item.attention >= 3 ? Palette.danger : Palette.warn
            default: .accentColor
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.16)))
                .foregroundStyle(color)
        }
    }
}

struct WidgetRow: View {
    var item: WidgetSnapshot.Item
    var date: LocalDate
    /// The extension passes a button wired to an App Intent; previews pass nil.
    var check: ((DayItem) -> AnyView)?

    var body: some View {
        HStack(spacing: 8) {
            EmojiCircle(emoji: item.item.emoji, color: item.item.color, size: 26)
                // High priority: a stripe in the item's color, out in the margin so rows stay aligned.
                .overlay(alignment: .leading) {
                    if item.item.priority == .high {
                        Capsule().fill(Palette.color(item.item.color)).frame(width: 3, height: 22).offset(x: -7)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.item.title)
                    .font(.caption.weight(item.item.priority == .high ? .bold : .regular))
                    .lineLimit(1)
                    .strikethrough(item.item.done)
                    .foregroundStyle(item.item.done ? .secondary : .primary)
                if !item.item.done { WidgetBadge(item: item) }
            }
            Spacer(minLength: 0)
            if item.item.done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.ok)
            } else if let check {
                check(item.item)
            } else {
                Image(systemName: "circle").font(.system(size: 17)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct WidgetHeader: View {
    var snapshot: WidgetSnapshot
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Palette.warn)
            Text("\(snapshot.streak)").font(.caption2.weight(.semibold))
            if let record = snapshot.recordText {
                Text("· \(record)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(trailing ?? snapshot.progressText).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct WidgetEmpty: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle").font(.title2).foregroundStyle(Palette.ok)
            Text(tr("На сегодня всё", "All done for today")).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Home screen widget layouts: small = one thing, medium = top three, large = current part.
public struct HomeWidgetBody: View {
    var snapshot: WidgetSnapshot?
    var size: WidgetSize
    var check: ((DayItem) -> AnyView)?

    public init(snapshot: WidgetSnapshot?, size: WidgetSize, check: ((DayItem) -> AnyView)? = nil) {
        self.snapshot = snapshot
        self.size = size
        self.check = check
    }

    public var body: some View {
        if let snapshot {
            switch size {
            case .small: small(snapshot)
            case .large: large(snapshot)
            case .medium: medium(snapshot)
            }
        } else {
            Text(tr("Откройте приложение", "Open the app")).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One thing to do, with the reason it is first.
    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(tr("Сейчас", "Now")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(s.progressText).font(.caption2).foregroundStyle(.secondary)
            }
            if let first = s.items.first {
                EmojiCircle(emoji: first.item.emoji, color: first.item.color, size: 30)
                Text(first.item.title).font(.footnote.weight(first.item.priority == .high ? .bold : .medium)).lineLimit(3)
                HStack(spacing: 4) {
                    if first.item.priority == .high {
                        Text("!!")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.color(first.item.color).opacity(0.24)))
                            .foregroundStyle(Palette.text(first.item.color))
                            .accessibilityLabel(Fmt.priorityTag)
                    }
                    WidgetBadge(item: first)
                }
            } else {
                WidgetEmpty()
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Palette.warn)
                Text("\(s.streak)").font(.caption2)
            }
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(snapshot: s)
            if s.items.isEmpty {
                WidgetEmpty()
            } else {
                ForEach(s.items.prefix(3)) { WidgetRow(item: $0, date: s.date) }
                Spacer(minLength: 0)
            }
        }
    }

    /// The current part of the day as a short timeline.
    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(snapshot: s, trailing: "\(Fmt.sectionTitle(s.part)): \(s.partDone)/\(s.partTotal)")
            ProgressView(value: s.partTotal > 0 ? Double(s.partDone) / Double(s.partTotal) : 0)
                .tint(Palette.ok)
            if s.partItems.isEmpty {
                WidgetEmpty()
            } else {
                ForEach(s.partItems) { WidgetRow(item: $0, date: s.date) }
            }
            Spacer(minLength: 0)
            HStack {
                if s.moreInPart > 0 { Text(tr("и ещё \(s.moreInPart)", "and \(s.moreInPart) more")) }
                Spacer()
                if let next = s.nextPart, s.nextPartCount > 0 {
                    Text(tr("дальше \(Fmt.sectionTitle(next).lowercased()) (\(s.nextPartCount))", "next: \(Fmt.sectionTitle(next).lowercased()) (\(s.nextPartCount))"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// Lock screen layouts.
public struct LockWidgetBody: View {
    var snapshot: WidgetSnapshot?
    var size: LockWidgetSize

    public init(snapshot: WidgetSnapshot?, size: LockWidgetSize) {
        self.snapshot = snapshot
        self.size = size
    }

    public var body: some View {
        let s = snapshot
        switch size {
        case .circular:
            Gauge(value: progress(s)) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text(s.map { "\($0.done)" } ?? "—").font(.system(size: 13, weight: .medium))
            }
            .gaugeStyle(.accessoryCircular)
        case .inline:
            if let s {
                Text("🔥 \(s.streak) · \(s.progressText)\(s.items.first?.badge.map { " · \($0)" } ?? "")")
            } else {
                Text(tr("Трекер", "Tracker"))
            }
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let s, let first = s.items.first {
                    Text(first.badge ?? Fmt.sectionTitle(s.part)).font(.caption2).foregroundStyle(.secondary)
                    Text(first.item.title).font(.footnote.weight(.medium)).lineLimit(2)
                    if s.items.count > 1 {
                        Text(tr("потом: \(s.items[1].item.title)", "then: \(s.items[1].item.title)")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else {
                    Text(tr("На сегодня всё", "All done for today")).font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func progress(_ s: WidgetSnapshot?) -> Double {
        guard let s, s.total > 0 else { return 0 }
        return Double(s.done) / Double(s.total)
    }
}
