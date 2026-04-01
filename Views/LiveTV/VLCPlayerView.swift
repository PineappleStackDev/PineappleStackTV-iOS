import SwiftUI
import VLCKit
import AVKit

struct VLCPlayerRepresentable: UIViewRepresentable {
    let url: URL?
    let onError: (String) -> Void
    @Binding var playerControl: VLCPlayerControl?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.setupPlayer(in: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateURL(url, in: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError, controlBinding: $playerControl)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    class Coordinator: NSObject, VLCMediaPlayerDelegate {
        private var mediaPlayer: VLCMediaPlayer?
        private var currentURL: URL?
        private let onError: (String) -> Void
        private var controlBinding: Binding<VLCPlayerControl?>

        init(onError: @escaping (String) -> Void, controlBinding: Binding<VLCPlayerControl?>) {
            self.onError = onError
            self.controlBinding = controlBinding
            super.init()
        }

        func setupPlayer(in view: UIView) {
            let player = VLCMediaPlayer()
            player.delegate = self
            player.drawable = view
            mediaPlayer = player
            DispatchQueue.main.async {
                self.controlBinding.wrappedValue = VLCPlayerControl(player: player)
            }
        }

        func updateURL(_ url: URL?, in view: UIView) {
            guard url != currentURL else { return }
            currentURL = url

            guard let url else {
                mediaPlayer?.stop()
                return
            }

            guard let media = VLCMedia(url: url) else { return }
            media.addOptions([
                "network-caching": 1500,
                "clock-jitter": 0,
                "clock-synchro": 0
            ])
            mediaPlayer?.media = media
            mediaPlayer?.play()
        }

        func stop() {
            mediaPlayer?.stop()
            mediaPlayer = nil
        }

        func mediaPlayerStateChanged(_ notification: Notification) {
            guard let player = mediaPlayer else { return }
            switch player.state {
            case .error:
                DispatchQueue.main.async {
                    self.onError("VLC playback error")
                }
            default:
                break
            }
        }
    }
}

class VLCPlayerControl: ObservableObject {
    private let player: VLCMediaPlayer

    var isPlaying: Bool {
        player.isPlaying
    }

    init(player: VLCMediaPlayer) {
        self.player = player
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func skipForward(_ seconds: Int32 = 10) {
        player.jumpForward(Double(seconds))
    }

    func skipBackward(_ seconds: Int32 = 10) {
        player.jumpBackward(Double(seconds))
    }

    func stop() {
        player.stop()
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
