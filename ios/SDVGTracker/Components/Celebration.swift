import SDVGCore
import SwiftUI

/// A postponed task just marked done. Level from Rules.celebrationLevel:
/// 1 confetti from the check, 2 adds fireworks, 3 is a long show with applause.
struct DoneCelebration: Identifiable, Equatable {
    let id = UUID()
    var level: Int
    var moves: Int
    /// Where the confetti bursts from: the check button, in global coordinates.
    var origin: CGPoint
}

extension AnyTransition {
    /// A row leaving a list slides aside and fades; a new one fades in.
    static var row: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .move(edge: .trailing).combined(with: .opacity))
    }
}

/// Full-screen overlay for a DoneCelebration; dismisses itself.
struct DoneCelebrationView: View {
    var celebration: DoneCelebration
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var shown = false
    @State private var show: Show?

    private var duration: Double { [0, 2.2, 4.8, 7.2][celebration.level] }

    var body: some View {
        ZStack(alignment: .top) {
            if !reduceMotion {
                GeometryReader { geo in
                    if let show {
                        TimelineView(.animation) { ctx in
                            ShowCanvas(show: show, origin: celebration.origin, elapsed: ctx.date.timeIntervalSince(start), duration: duration)
                        }
                        .task { await show.haptics() }
                    } else {
                        // Randomized once, when the screen size is known.
                        Color.clear.onAppear { show = Show(level: celebration.level, size: geo.size) }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
            if celebration.level >= 2 { toast }
        }
        .task {
            start = .now
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { shown = true }
            try? await Task.sleep(for: .seconds(reduceMotion ? 3 : duration + 0.4))
            onClose()
        }
    }

    private var toast: some View {
        let big = celebration.level == 3
        let times = trn(celebration.moves, ru: ("раз", "раза", "раз"), en: ("time", "times"))
        return Button(action: onClose) {
            HStack(spacing: 12) {
                Text(big ? "👏" : "🎆").font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(big ? tr("Вот это победа!", "Now that's a win!") : tr("Салют!", "Hooray!")).font(.headline)
                    Text(big ? tr("Задачу переносили \(times) — и она сделана", "Moved \(times), and now it's done")
                         : tr("Переносили \(times), а вы её сделали", "Moved \(times), and you did it"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(.regularMaterial).shadow(radius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        // Below the record toast, which can fall on the same tap.
        .padding(.top, 84)
        .scaleEffect(shown ? 1 : 0.6)
        .opacity(shown ? 1 : 0)
    }
}

/// Everything the show draws, randomized once per celebration. Units are points and seconds.
private struct Show {
    struct Piece { var angle, speed, spin, w, h: Double; var color: Color }
    struct Rocket {
        var at, x, apex, rise: Double
        var colors: [Color]
        var sparks: [Spark]
        var crackle: Bool
        var burst: Double { at + rise }
    }
    struct Spark { var angle, speed, life: Double }
    struct Clap { var x, delay, duration, size, sway: Double }

    static let colors = [0, 1, 2, 4, 6, 8, 10].map(Palette.color)
    /// Rocket deceleration, pt/s²: they coast up and burst at the top.
    static let rocketG = 430.0

    var pieces: [Piece]
    var rockets: [Rocket]
    var claps: [Clap]

    init(level: Int, size: CGSize) {
        let colors = Self.colors
        pieces = (0..<[0, 70, 90, 140][level]).map { i in
            Piece(angle: -.pi / 2 + .random(in: -1.2...1.2), speed: .random(in: 300...780) + Double(level) * 60,
                  spin: .random(in: -8...8), w: .random(in: 5...10), h: .random(in: 3...7), color: colors[i % colors.count])
        }
        let count = [0, 0, 6, 18][level], span = [0, 0, 1.8, 3.6][level]
        let scale = min(1, max(0.6, size.width / 900)) * (level == 3 ? 1.25 : 1)
        rockets = (0..<count).map { i in
            let finale = level == 3 && i >= count - 5
            let apex = size.height * .random(in: 0.12...0.45)
            let v0 = (2 * Self.rocketG * (size.height - apex)).squareRoot()
            let s = scale * .random(in: 0.8...1.3)
            let n = Int(80 * s)
            return Rocket(
                at: finale ? span : Double(i) / Double(count) * span + .random(in: 0...0.2),
                x: size.width * .random(in: 0.12...0.88), apex: apex, rise: v0 / Self.rocketG,
                colors: Bool.random() ? [colors.randomElement()!, colors.randomElement()!] : [colors.randomElement()!],
                sparks: (0..<n).map { j in
                    Spark(angle: Double(j) / Double(n) * 2 * .pi + .random(in: 0...0.2),
                          speed: .random(in: 180...540) * s * 1.5, life: .random(in: 0.9...1.5))
                },
                crackle: level == 3 && .random(in: 0...1) < 0.35)
        }
        claps = level == 3 ? (0..<15).map { i in
            Clap(x: .random(in: 0.04...0.92), delay: Double(i) / 15 * 3.2 + .random(in: 0...0.4),
                 duration: .random(in: 2.6...4), size: .random(in: 26...52), sway: .random(in: -40...40))
        } : []
    }

    /// A light thump on every firework burst.
    @MainActor func haptics() async {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        var t = 0.0
        for burst in rockets.map(\.burst).sorted() {
            try? await Task.sleep(for: .seconds(burst - t))
            if Task.isCancelled { return }
            gen.impactOccurred(intensity: 0.7)
            t = burst
        }
    }
}

private struct ShowCanvas: View {
    var show: Show
    var origin: CGPoint
    var elapsed: Double
    var duration: Double

    /// Ballistic flight with air drag k and gravity g from p with velocity v, after t seconds.
    private func fly(_ p: CGPoint, vx: Double, vy: Double, k: Double, g: Double, t: Double) -> CGPoint {
        let d = (1 - exp(-k * t)) / k
        return CGPoint(x: p.x + vx * d, y: p.y + vy * d + g * (t - d) / k)
    }

    var body: some View {
        Canvas { ctx, size in
            let t = elapsed
            let fade = max(0, min(1, (duration - t) / 0.7))

            // Confetti fountain from the check.
            var c = ctx
            c.opacity = fade
            for p in show.pieces {
                let pos = fly(origin, vx: cos(p.angle) * p.speed, vy: sin(p.angle) * p.speed, k: 1.5, g: 1000, t: t)
                if pos.y > size.height + 20 { continue }
                var pc = c
                pc.translateBy(x: pos.x, y: pos.y)
                pc.rotate(by: .radians(p.spin * t))
                let h = p.h * abs(cos(p.spin * t * 2))
                pc.fill(Path(CGRect(x: -p.w / 2, y: -h / 2, width: p.w, height: h)), with: .color(p.color))
            }

            for r in show.rockets where t >= r.at {
                if t < r.burst {
                    // Rising trail.
                    let tau = t - r.at
                    let y = size.height - (r.rise * Show.rocketG) * tau + Show.rocketG * tau * tau / 2
                    let v = Show.rocketG * (r.rise - tau)
                    var path = Path()
                    path.move(to: CGPoint(x: r.x, y: y))
                    path.addLine(to: CGPoint(x: r.x, y: y + v * 0.07))
                    c.stroke(path, with: .color(r.colors[0]), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    continue
                }
                let tau = t - r.burst
                let apex = CGPoint(x: r.x, y: r.apex)
                for (i, s) in r.sparks.enumerated() where tau < s.life {
                    let vx = cos(s.angle) * s.speed, vy = sin(s.angle) * s.speed
                    let head = fly(apex, vx: vx, vy: vy, k: 2.8, g: 180, t: tau)
                    let tail = fly(apex, vx: vx, vy: vy, k: 2.8, g: 180, t: max(0, tau - 0.05))
                    var a = pow(1 - tau / s.life, 0.7) * fade
                    // Crackling bursts flicker as they die down.
                    if r.crackle && tau > s.life * 0.4 && (i + Int(t * 20)) % 2 == 0 { a *= 0.15 }
                    var sc = ctx
                    sc.opacity = a
                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    sc.stroke(path, with: .color(r.colors[i % r.colors.count]), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }

            // Applause rising from the bottom.
            for clap in show.claps {
                let p = (t - clap.delay) / clap.duration
                guard p > 0, p < 1 else { continue }
                let eased = 1 - pow(1 - p, 1.6)
                let x = clap.x * size.width + clap.sway * sin(p * .pi * 2)
                let y = size.height + 40 - (size.height + 120) * eased
                var cc = ctx
                cc.opacity = min(1, p / 0.12, (1 - p) / 0.2)
                cc.translateBy(x: x, y: y)
                cc.rotate(by: .degrees(12 * sin(p * .pi * 5)))
                cc.draw(Text("👏").font(.system(size: clap.size)), at: .zero)
            }
        }
    }
}
