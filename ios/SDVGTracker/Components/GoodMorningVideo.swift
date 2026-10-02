import AVFoundation
import SDVGCore
import SwiftUI

/// The morning video over the whole screen: fades in once its first frame is ready, plays once
/// with sound (silent on the mute switch, over any music already playing) and fades out at the
/// end or on the close button.
struct GoodMorningVideo: View {
    var url: URL
    var onClose: () -> Void

    static let fade: Double = 0.2

    @State private var player: AVPlayer
    @State private var shown = false
    @State private var closing = false

    init(url: URL, onClose: @escaping () -> Void) {
        self.url = url
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        PlayerLayer(player: player) { start() }
            .background(.black)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .accessibilityLabel(tr("Закрыть", "Close"))
                .padding(.trailing, 16)
                .padding(.top, 8)
            }
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown && !closing)
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)) { _ in
                close()
            }
            .task {
                // A file that never shows a frame must not leave an invisible layer over the app.
                try? await Task.sleep(for: .seconds(3))
                if !shown { finish() }
            }
    }

    private func start() {
        guard !shown, !closing else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        player.play()
        withAnimation(.easeInOut(duration: Self.fade)) { shown = true }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        withAnimation(.easeInOut(duration: Self.fade)) { shown = false } completion: { finish() }
    }

    private func finish() {
        closing = true
        player.pause()
        onClose()
    }
}

/// An AVPlayerLayer filling its frame; calls onReady once the first frame can be shown.
private struct PlayerLayer: UIViewRepresentable {
    var player: AVPlayer
    var onReady: @MainActor () -> Void

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var ready: NSKeyValueObservation?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        let onReady = onReady
        view.ready = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in onReady() }
        }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}
}
