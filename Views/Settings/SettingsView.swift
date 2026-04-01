import SwiftUI

struct SettingsView: View {
    @ObservedObject var authVM: AuthViewModel
    @AppStorage(Constants.streamBufferSizeKey) private var bufferSize: String = "Medium"
    @AppStorage(Constants.autoPlayKey) private var autoPlay: Bool = true
    @State private var cacheCleared = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // Logo at top
                Section {
                    HStack {
                        Spacer()
                        Image("DispatcharrLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Server") {
                    LabeledContent("Server URL", value: authVM.serverURL)
                    LabeledContent("Username", value: authVM.username)
                }

                Section("Playback") {
                    Picker("Stream Buffer Size", selection: $bufferSize) {
                        Text("Low").tag("Low")
                        Text("Medium").tag("Medium")
                        Text("High").tag("High")
                    }

                    Toggle("Auto-play on channel select", isOn: $autoPlay)
                }

                Section("Cache") {
                    Button(action: {
                        ImageCache.shared.clearDisk()
                        cacheCleared = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            cacheCleared = false
                        }
                    }) {
                        HStack {
                            Text("Clear Image Cache")
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section {
                    Button("Logout", role: .destructive) {
                        Task { await authVM.logout() }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "Dispatcharr TV")
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
