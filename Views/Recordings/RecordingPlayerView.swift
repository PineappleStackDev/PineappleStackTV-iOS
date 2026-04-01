import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.dispatcharr.DispatcharrTV", category: "RecPlayer")

struct RecordingPlayerView: View {
    let hlsURL: URL
    let recording: Recording?
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        player?.pause()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
        .onAppear {
            let avPlayer = AVPlayer(url: hlsURL)
            avPlayer.allowsExternalPlayback = true
            #if !os(tvOS)
            avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
            #endif
            player = avPlayer
            avPlayer.play()
            logger.info("Recording player started: \(hlsURL.absoluteString.prefix(60))")
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        #if os(tvOS)
        .onExitCommand {
            player?.pause()
            isPresented = false
        }
        #endif
    }
}
