import CoreText
import SDVGCore
import SwiftUI

/// "Доброе утро" written over the morning video in a script font, letter by letter: the pen
/// traces each letter's outline, then the ink fills it, while the next letter is begun.
struct GoodMorningTitle: View {
    /// When the first letter is begun.
    var from: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let text = tr("Доброе утро", "Good morning")
    private let lettering: Lettering

    /// Seconds between the starts of two letters, to trace one letter, and for its ink to fill it.
    private static let step = 0.15
    private static let trace = 0.5
    private static let ink = 0.35

    init(from: Date) {
        self.from = from
        lettering = Lettering(text, font: "SnellRoundhand-Black", size: 64)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = reduceMotion ? .infinity : timeline.date.timeIntervalSince(from)
            Canvas { gc, size in
                let scale = size.width / lettering.size.width
                gc.scaleBy(x: scale, y: scale)
                gc.addFilter(.shadow(color: .black.opacity(0.55), radius: 6))
                for (i, letter) in lettering.letters.enumerated() {
                    let t = elapsed - Double(i) * Self.step
                    guard t > 0 else { break }
                    let traced = min(t / Self.trace, 1)
                    let inked = min(max((t - Self.trace * 0.6) / Self.ink, 0), 1)
                    gc.stroke(letter.trimmedPath(from: 0, to: traced), with: .color(.white), lineWidth: 1.4 / scale)
                    if inked > 0 { gc.fill(letter, with: .color(.white.opacity(inked))) }
                }
            }
        }
        .aspectRatio(lettering.size.width / lettering.size.height, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// The outlines of a line of text, one path per letter in writing order, set in a box with room
/// for the swashes and the shadow.
private struct Lettering {
    var letters: [Path] = []
    var size: CGSize = .zero

    init(_ text: String, font name: String, size fontSize: CGFloat) {
        let font = CTFontCreateWithName(name as CFString, fontSize, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var outlines: [CGPath] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            // A fallback font when the script one lacks a character.
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs)
            CTRunGetPositions(run, CFRange(), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                var at = CGAffineTransform(translationX: position.x, y: position.y)
                if let path = CTFontCreatePathForGlyph(runFont, glyph, &at), !path.isEmpty { outlines.append(path) }
            }
        }
        guard let first = outlines.first else { return }
        let pad = fontSize * 0.2
        let bounds = outlines.dropFirst().reduce(first.boundingBoxOfPath) { $0.union($1.boundingBoxOfPath) }
            .insetBy(dx: -pad, dy: -pad)
        // CoreText's y goes up, SwiftUI's down.
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: -bounds.minX, ty: bounds.maxY)
        letters = outlines.map { Path($0).applying(flip) }
        size = bounds.size
    }
}
