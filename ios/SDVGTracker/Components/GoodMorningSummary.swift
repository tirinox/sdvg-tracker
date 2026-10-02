import SDVGCore
import SwiftUI

/// What is still open today, for the morning video, and the streak. A high-priority item counts
/// as important, task or routine; the rest are routines and tasks.
struct MorningSummary: Equatable {
    var important = 0
    var routines = 0
    var tasks = 0
    var streak = 0

    var total: Int { important + routines + tasks }

    init(day: DayView, streak: Int) {
        for item in day.items where !item.done && !item.skipped {
            if item.priority == .high {
                important += 1
            } else if item.kind == .routine {
                routines += 1
            } else {
                tasks += 1
            }
        }
        self.streak = streak
    }
}

/// Under the greeting: how much is planned, the counts and the streak, popping in one by one.
struct GoodMorningSummaryView: View {
    var summary: MorningSummary
    /// When the first line appears.
    var from: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many of the lines and chips are in.
    @State private var shown = 0

    private static let step = 0.3

    private struct Chip {
        var icon: String
        var text: String
    }

    private var chips: [Chip] {
        let s = summary
        return [
            s.routines > 0 ? Chip(icon: "repeat", text: trn(s.routines, ru: ("рутина", "рутины", "рутин"), en: ("routine", "routines"))) : nil,
            s.important > 0 ? Chip(icon: "exclamationmark.2", text: trn(s.important, ru: ("важное", "важных", "важных"), en: ("important", "important"))) : nil,
            s.tasks > 0 ? Chip(icon: "checklist", text: trn(s.tasks, ru: ("задача", "задачи", "задач"), en: ("task", "tasks"))) : nil,
        ].compactMap { $0 }
    }

    private var headline: String {
        guard summary.total > 0 else { return tr("На сегодня дел нет", "Nothing planned for today") }
        let count = trn(summary.total, ru: ("дело", "дела", "дел"), en: ("thing", "things"))
        return tr("На сегодня — \(count)", "\(count) for today")
    }

    private var streak: String {
        guard summary.streak > 0 else { return tr("Сегодня начнётся стрик", "A streak starts today") }
        let count = trn(summary.streak, ru: ("день", "дня", "дней"), en: ("day", "days"))
        return tr("Стрик — \(count)", "Streak: \(count)")
    }

    var body: some View {
        let chips = chips
        VStack(spacing: 12) {
            Text(headline)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .popIn(shown > 0)
            if !chips.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chipViews(chips) }
                    VStack(spacing: 8) { chipViews(chips) }
                }
            }
            Label {
                Text(streak)
            } icon: {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }
            .font(.system(.headline, design: .rounded))
            .popIn(shown > 1 + chips.count)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 6)
        .multilineTextAlignment(.center)
        .task {
            let steps = 2 + chips.count
            if reduceMotion {
                shown = steps
                return
            }
            for k in 1...steps {
                let delay = from.timeIntervalSinceNow + Double(k - 1) * Self.step
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { shown = k }
            }
        }
    }

    private func chipViews(_ chips: [Chip]) -> some View {
        ForEach(Array(chips.enumerated()), id: \.offset) { i, chip in
            Label(chip.text, systemImage: chip.icon)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.35), in: Capsule())
                .popIn(shown > 1 + i)
        }
    }
}

private extension View {
    /// Hidden, a little low and small until it is in.
    func popIn(_ isIn: Bool) -> some View {
        opacity(isIn ? 1 : 0)
            .scaleEffect(isIn ? 1 : 0.8)
            .offset(y: isIn ? 0 : 14)
    }
}
