import SwiftUI
import AVFoundation

@main
struct PineappleStackTVApp: App {
    init() {
        // Enable AirPlay video and background audio
        #if !os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        try? session.setActive(true)
        #endif
    }

    @StateObject private var authVM = AuthViewModel()
    @StateObject private var channelsVM = ChannelsViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var guideVM = GuideViewModel()
    @StateObject private var recordingsVM = RecordingsViewModel()

    var body: some Scene {
        WindowGroup {
            if authVM.isAuthenticated {
                TabView {
                    ChannelGridView(channelsVM: channelsVM, guideVM: guideVM, playerVM: playerVM)
                        .tabItem {
                            Label("Live TV", systemImage: "tv")
                        }

                    GuideView(
                        guideVM: guideVM,
                        channelsVM: channelsVM,
                        recordingsVM: recordingsVM,
                        playerVM: playerVM
                    )
                    .tabItem {
                        Label("Guide", systemImage: "list.bullet.rectangle")
                    }

                    RecordingsListView(recordingsVM: recordingsVM, channelsVM: channelsVM, playerVM: playerVM)
                        .tabItem {
                            Label("Recordings", systemImage: "record.circle")
                        }

                    SettingsView(authVM: authVM)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                }
            } else {
                LoginView(authVM: authVM)
            }
        }
    }
}
