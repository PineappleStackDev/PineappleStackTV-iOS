import SwiftUI

struct GuideView: View {
    @ObservedObject var guideVM: GuideViewModel
    @ObservedObject var channelsVM: ChannelsViewModel
    @ObservedObject var recordingsVM: RecordingsViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @State private var showPlayer = false
    @State private var showProgramDetail = false

    #if os(tvOS)
    private let channelColumnWidth: CGFloat = 200
    private let pixelsPerMinute: CGFloat = 6
    private let rowHeight: CGFloat = 100
    private let timeHeaderHeight: CGFloat = 40
    #else
    private let channelColumnWidth: CGFloat = 90
    private let pixelsPerMinute: CGFloat = 3
    private let rowHeight: CGFloat = 50
    private let timeHeaderHeight: CGFloat = 30
    #endif

    private var guideStartTime: Date {
        guideVM.timeSlots.first ?? Date()
    }

    private var totalContentWidth: CGFloat {
        guard let first = guideVM.timeSlots.first, let last = guideVM.timeSlots.last else { return 0 }
        let totalMinutes = last.timeIntervalSince(first) / 60 + Double(Constants.guideSlotMinutes)
        return channelColumnWidth + CGFloat(totalMinutes) * pixelsPerMinute
    }

    private var totalGuideWidth: CGFloat {
        guard let first = guideVM.timeSlots.first, let last = guideVM.timeSlots.last else { return 0 }
        let totalMinutes = last.timeIntervalSince(first) / 60 + Double(Constants.guideSlotMinutes)
        return CGFloat(totalMinutes) * pixelsPerMinute
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if guideVM.isLoading && guideVM.programs.isEmpty {
                    Spacer()
                    ProgressView("Loading guide...")
                    Spacer()
                } else {
                    guideGrid
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                PlayerView(playerVM: playerVM, channelsVM: channelsVM, isPresented: $showPlayer)
            }
            .sheet(isPresented: $showProgramDetail) {
                if let program = guideVM.selectedProgram {
                    ProgramDetailView(
                        program: program,
                        channelsVM: channelsVM,
                        guideVM: guideVM,
                        recordingsVM: recordingsVM,
                        onWatch: { channel in
                            showProgramDetail = false
                            playerVM.setChannelList(channelsVM.filteredChannels)
                            Task { await playerVM.play(channel: channel) }
                            showPlayer = true
                        }
                    )
                }
            }
        }
        .task {
            if guideVM.programs.isEmpty {
                await guideVM.loadGuide()
            }
        }
    }

    // One horizontal ScrollView for the whole grid (time header + all rows scroll together).
    // Inside: one vertical ScrollView with pinned time header.
    private var guideGrid: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(channelsVM.filteredChannels) { channel in
                            HStack(spacing: 0) {
                                channelCell(channel)
                                programRow(for: channel)
                            }
                            .frame(height: rowHeight)
                        }
                    } header: {
                        timeHeaderRow
                    }
                }
            }
            .frame(width: totalContentWidth)
        }
    }

    private var timeHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Channel")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: channelColumnWidth, height: timeHeaderHeight, alignment: .leading)
                .padding(.leading, 6)
                .background(Color(.init(white: 0.1, alpha: 1)))

            ForEach(guideVM.timeSlots, id: \.self) { slot in
                Text(DateFormatters.timeOnly.string(from: slot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: CGFloat(Constants.guideSlotMinutes) * pixelsPerMinute, alignment: .leading)
                    .padding(.leading, 4)
            }
        }
        .frame(width: totalContentWidth, height: timeHeaderHeight)
        .background(Color(.init(white: 0.1, alpha: 1)))
    }

    private func channelCell(_ channel: Channel) -> some View {
        HStack(spacing: 4) {
            #if os(tvOS)
            if let url = channelsVM.logoURLSync(for: channel) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    EmptyView()
                }
                .frame(width: 36, height: 24)
            }
            #endif

            VStack(alignment: .leading, spacing: 1) {
                if let num = channel.channelNumber {
                    Text(num == num.rounded() ? String(Int(num)) : String(format: "%.1f", num))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(channel.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: channelColumnWidth, height: rowHeight)
        .background(Color(.init(white: 0.15, alpha: 1)))
    }

    private func programRow(for channel: Channel) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: totalGuideWidth, height: rowHeight)

            let progs = guideVM.programs(for: channel)
            ForEach(progs) { program in
                let offset = programOffset(program)
                let width = programWidth(program)
                if offset + width > 0 && offset < totalGuideWidth {
                    programBlock(program, for: channel)
                        .offset(x: max(offset, 0))
                }
            }
        }
        .frame(width: totalGuideWidth, height: rowHeight)
    }

    private func programBlock(_ program: Program, for channel: Channel) -> some View {
        let width = programWidth(program)

        return Button(action: {
            guideVM.selectedProgram = program
            showProgramDetail = true
        }) {
            ProgramBlockContent(program: program, width: width, rowHeight: rowHeight)
        }
        .buttonStyle(.plain)
        #if os(tvOS)
        .focusable()
        #endif
    }

    private func programOffset(_ program: Program) -> CGFloat {
        guard let start = program.startDate else { return 0 }
        let minutes = start.timeIntervalSince(guideStartTime) / 60
        return CGFloat(minutes) * pixelsPerMinute
    }

    private func programWidth(_ program: Program) -> CGFloat {
        guard let start = program.startDate, let end = program.endDate else { return 120 }
        let minutes = end.timeIntervalSince(start) / 60
        return CGFloat(minutes) * pixelsPerMinute
    }
}

/// Extracted program block content to support @FocusState on tvOS
private struct ProgramBlockContent: View {
    let program: Program
    let width: CGFloat
    let rowHeight: CGFloat

    #if os(tvOS)
    @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(program.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            #if os(tvOS)
            if let start = program.startDate, let end = program.endDate {
                Text("\(DateFormatters.timeOnly.string(from: start)) - \(DateFormatters.timeOnly.string(from: end))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            #endif
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(width: max(width, 40), height: rowHeight - 2, alignment: .leading)
        .background(programBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        #if os(tvOS)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.blue : Color.clear, lineWidth: 3)
        )
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        #endif
    }

    private var programBackground: Color {
        if program.isCurrentlyAiring {
            return .blue.opacity(0.3)
        }
        return Color(.systemGray).opacity(0.15)
    }
}
