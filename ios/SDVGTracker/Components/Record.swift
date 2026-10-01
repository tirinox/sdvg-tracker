import SDVGCore
import SwiftUI

/// "3 дела" / "3 things".
private func things(_ n: Int) -> String { trn(n, ru: ("дело", "дела", "дел"), en: ("thing", "things")) }

/// Previous best day on the Now screen, or today's new record once it is broken.
struct RecordCard: View {
    var record: Rules.DayRecord

    var body: some View {
        let date = record.bestDate.map(Fmt.shortDate) ?? ""
        HStack(spacing: 12) {
            Text("🏆").font(.title)
            VStack(alignment: .leading, spacing: 3) {
                if record.broken {
                    Text(tr("Новый рекорд: \(things(record.todayDone)) за день", "New record: \(things(record.todayDone)) in a day"))
                        .font(.subheadline.bold())
                    Text(tr("Прежний — \(record.bestDone), \(date)", "Previous: \(record.bestDone), \(date)")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(tr("Рекорд: \(things(record.bestDone)) за день", "Record: \(things(record.bestDone)) in a day"))
                        .font(.subheadline.bold())
                    Text(tr("\(date) · чтобы побить, сделайте сегодня ещё \(record.toBeat)", "\(date) · do \(record.toBeat) more today to beat it"))
                        .font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(record.todayDone), total: Double(record.bestDone + 1)).tint(Palette.warn)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(
            record.broken ? Palette.warn.opacity(0.15) : Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }
}

/// Full-screen confetti with a "new record" toast; dismisses itself.
struct RecordCelebration: View {
    var record: Rules.DayRecord
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var shown = false

    private static let duration = 4.0

    var body: some View {
        ZStack(alignment: .top) {
            if !reduceMotion {
                TimelineView(.animation) { ctx in
                    ConfettiCanvas(elapsed: ctx.date.timeIntervalSince(start), duration: Self.duration)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            Button(action: onClose) {
                HStack(spacing: 12) {
                    Text("🏆").font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Новый рекорд!", "New record!")).font(.headline)
                        Text(tr("\(things(record.todayDone)) за день — прежний был \(record.bestDone)", "\(things(record.todayDone)) in a day, up from \(record.bestDone)"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial).shadow(radius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
        }
        .task {
            start = .now
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shown = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .seconds(Self.duration + 1.5))
            onClose()
        }
    }
}

private struct ConfettiCanvas: View {
    var elapsed: Double
    var duration: Double

    private struct Piece {
        var left: Bool, angle: Double, speed: Double, spin: Double, w: Double, h: Double, color: Color
    }

    private static let colors = [0, 1, 2, 4, 6, 8, 10].map(Palette.color)
    private static let pieces: [Piece] = (0..<180).map { i in
        let left = i.isMultiple(of: 2)
        return Piece(
            left: left,
            angle: (left ? -60 : -120) * .pi / 180 + .random(in: -0.35...0.35),
            speed: .random(in: 1.4...2.4),
            spin: .random(in: -6...6),
            w: .random(in: 6...12), h: .random(in: 4...8),
            color: colors[i % colors.count])
    }

    var body: some View {
        Canvas { ctx, size in
            let t = elapsed
            ctx.opacity = max(0, min(1, (duration - t) / 0.8))
            // Ballistic bursts from the bottom corners with air drag: v * (1 - e^(-kt)) / k.
            let k = 0.6, g = size.height * 0.9
            let drag = (1 - exp(-k * t)) / k
            for p in Self.pieces {
                let x = (p.left ? 0 : size.width) + cos(p.angle) * p.speed * size.width * drag * 0.6
                let y = size.height + sin(p.angle) * p.speed * size.height * drag + g * (t - drag) / k
                var c = ctx
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(p.spin * t))
                let h = p.h * abs(cos(p.spin * t * 2))
                c.fill(Path(CGRect(x: -p.w / 2, y: -h / 2, width: p.w, height: h)), with: .color(p.color))
            }
        }
    }
}
