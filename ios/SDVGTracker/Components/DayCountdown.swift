import SDVGCore
import SwiftUI

/// Time left in the logical day: yellow in the last hour, red in the last half hour.
struct DayCountdown: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let endsAt = Dates.dayEnd(model.today, dayStartHour: model.settings.dayStartHour)
        let end = Dates.instant(of: endsAt) ?? .distantFuture
        // Redrawn at the start of each minute, where the colour can change; the timer text ticks by itself.
        TimelineView(.everyMinute) { context in
            let level = Dates.dayEndLevel(secondsLeft: Int(end.timeIntervalSince(context.date).rounded(.up)))
            let (fg, bg): (Color, Color) = switch level {
            case .urgent: (Palette.danger, Palette.danger.opacity(0.14))
            case .soon: (Palette.caution, Palette.cautionFill)
            case .calm: (.secondary, Color(.tertiarySystemFill))
            }
            HStack(spacing: 5) {
                Image(systemName: "hourglass")
                Text(timerInterval: min(context.date, end)...end, countsDown: true)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(level == .calm ? Color.primary : fg)
                Text(tr("до конца дня", "left today"))
            }
            .font(.subheadline)
            .foregroundStyle(fg)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
            .animation(.easeInOut(duration: 0.3), value: level)
            .accessibilityElement(children: .combine)
            .accessibilityHint(tr("День закончится в \(endsAt.suffix(5))", "The day ends at \(endsAt.suffix(5))"))
        }
    }
}
