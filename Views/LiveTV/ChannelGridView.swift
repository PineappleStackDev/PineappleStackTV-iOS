import SwiftUI

struct ChannelGridView: View {
    @ObservedObject var channelsVM: ChannelsViewModel
    @ObservedObject var guideVM: GuideViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @State private var showPlayer = false

    #if os(tvOS)
    @State private var channelNumberBuffer: String = ""
    @State private var channelNumberTimer: Task<Void, Never>?
    #endif

    // Precompute current programs to avoid expensive lookups during render
    private var currentPrograms: [Int: Program] {
        var map: [Int: Program] = [:]
        for channel in channelsVM.filteredChannels {
            if let prog = guideVM.programs(for: channel).first(where: { $0.isCurrentlyAiring }) {
                map[channel.id] = prog
            }
        }
        return map
    }

    let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 320), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Channel grid
                if channelsVM.isLoading && channelsVM.channels.isEmpty {
                    Spacer()
                    // Loading skeletons
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(0..<8, id: \.self) { _ in
                                ChannelCardSkeleton()
                            }
                        }
                        .padding(20)
                    }
                    Spacer()
                } else if channelsVM.filteredChannels.isEmpty && channelsVM.favoriteChannels.isEmpty {
                    Spacer()
                    Text("No channels found")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Favorites section
                            if !channelsVM.favoriteChannels.isEmpty {
                                Text("Favorites")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)

                                #if os(tvOS)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 20) {
                                        ForEach(channelsVM.favoriteChannels) { channel in
                                            channelCard(channel)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .frame(height: 200)
                                #else
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(channelsVM.favoriteChannels) { channel in
                                        channelCard(channel)
                                    }
                                }
                                .padding(.horizontal, 20)
                                #endif
                            }

                            // All Channels
                            if !channelsVM.filteredChannels.isEmpty {
                                Text("All Channels")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 20)

                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(channelsVM.filteredChannels) { channel in
                                        channelCard(channel)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }

                #if os(tvOS)
                // Channel number overlay
                if !channelNumberBuffer.isEmpty {
                    Text(channelNumberBuffer)
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .padding(30)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.opacity)
                }
                #endif
            }
            .searchable(text: $channelsVM.searchText, prompt: "Search channels")
            .fullScreenCover(isPresented: $showPlayer) {
                PlayerView(playerVM: playerVM, channelsVM: channelsVM, isPresented: $showPlayer)
            }
            #if os(tvOS)
            .pressHandler { press in
                handleNumberPress(press)
            }
            #endif
        }
        .task {
            if channelsVM.channels.isEmpty {
                await channelsVM.loadAll()
            }
            if guideVM.programs.isEmpty {
                await guideVM.loadGuide()
            }
        }
        .refreshable {
            await channelsVM.loadAll(forceRefresh: true)
        }
    }

    @ViewBuilder
    private func channelCard(_ channel: Channel) -> some View {
        ChannelCardView(
            channel: channel,
            logoURL: channelsVM.logoURLSync(for: channel),
            currentProgram: currentPrograms[channel.id],
            isFavorite: channelsVM.isFavorite(channel.id),
            onSelect: {
                playerVM.setChannelList(channelsVM.filteredChannels)
                Task { await playerVM.play(channel: channel) }
                showPlayer = true
            },
            onToggleFavorite: {
                channelsVM.toggleFavorite(channelId: channel.id)
            }
        )
    }

    #if os(tvOS)
    private func handleNumberPress(_ keyCode: Int) {
        guard keyCode >= 0 && keyCode <= 9 else { return }
        channelNumberBuffer += "\(keyCode)"
        channelNumberTimer?.cancel()
        channelNumberTimer = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if let num = Int(channelNumberBuffer) {
                await playerVM.goToChannelNumber(num)
                showPlayer = true
            }
            channelNumberBuffer = ""
        }
    }
    #endif
}

#if os(tvOS)
// Simple press handler modifier for tvOS number entry
struct PressHandlerModifier: ViewModifier {
    let handler: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {} // placeholder, number entry handled via gesture recognizers if needed
    }
}

extension View {
    func pressHandler(_ handler: @escaping (Int) -> Void) -> some View {
        self.modifier(PressHandlerModifier(handler: handler))
    }
}
#endif
