import SwiftUI
import AVKit

// Presents AVPlayerViewController modally via UIKit for full native controls
struct AVPlayerPresenter: UIViewControllerRepresentable {
    let player: AVPlayer?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .black
        context.coordinator.host = host
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let coordinator = context.coordinator

        if let player, isPresented, !coordinator.isShowingPlayer {
            coordinator.isShowingPlayer = true

            let playerVC = AVPlayerViewController()
            playerVC.player = player
            playerVC.allowsPictureInPicturePlayback = true
            playerVC.delegate = coordinator
            player.allowsExternalPlayback = true

            #if !os(tvOS)
            playerVC.canStartPictureInPictureAutomaticallyFromInline = true
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
            #endif

            // Present modally for full native experience
            DispatchQueue.main.async {
                uiViewController.present(playerVC, animated: true) {
                    player.play()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var host: UIViewController?
        var isShowingPlayer = false
        var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        #if !os(tvOS)
        // Called when user taps Done/X in the player
        func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: any UIViewControllerTransitionCoordinator) {
            playerViewController.player?.pause()
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                playerViewController.player?.replaceCurrentItem(with: nil)
                self?.isShowingPlayer = false
                self?.isPresented.wrappedValue = false
            }
        }
        #endif
    }
}

struct PlayerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @ObservedObject var channelsVM: ChannelsViewModel
    @Binding var isPresented: Bool
    @State private var vlcControl: VLCPlayerControl?

    var body: some View {
        Group {
            switch playerVM.backend {
            case .avPlayer:
                AVPlayerPresenter(player: playerVM.player, isPresented: $isPresented)
                    .ignoresSafeArea()

            case .vlcKit:
                vlcPlayerView
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if !newValue {
                vlcControl?.stop()
                playerVM.stop()
            }
        }
        #if os(tvOS)
        .onExitCommand {
            vlcControl?.stop()
            playerVM.stop()
            isPresented = false
        }
        #endif
    }

    private var vlcPlayerView: some View {
        ZStack {
            VLCPlayerRepresentable(
                url: playerVM.streamURL,
                onError: { error in
                    playerVM.errorMessage = error
                },
                playerControl: $vlcControl
            )
            .ignoresSafeArea()

            if playerVM.streamURL == nil {
                Color.black.ignoresSafeArea()
                ProgressView("Loading stream...")
            }

            VStack {
                HStack {
                    if let channel = playerVM.currentChannel {
                        Text(channel.name)
                            .font(.headline)
                            .shadow(radius: 4)
                    }
                    Spacer()

                    // Record button
                    Button(action: {
                        Task { await playerVM.recordCurrentChannel() }
                    }) {
                        Image(systemName: "record.circle")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)

                    #if !os(tvOS)
                    // Last channel button
                    Button(action: {
                        Task { await playerVM.goToLastChannel() }
                    }) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    AirPlayButton()
                        .frame(width: 36, height: 36)
                    #endif

                    Button(action: {
                        vlcControl?.stop()
                        playerVM.stop()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
            }

            // Recording confirmation overlay
            if let confirmation = playerVM.recordingConfirmation {
                VStack {
                    Spacer()
                    Text(confirmation)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }

            if let error = playerVM.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
            }
        }
    }
}
