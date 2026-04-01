import SwiftUI
import AVKit
import os

private let logger = Logger(subsystem: "com.pineapplestack.tv", category: "Recordings")

struct RecordingPlayback: Identifiable {
    let id = UUID()
    let recording: Recording
    let url: URL
}

struct RecordingsListView: View {
    @ObservedObject var recordingsVM: RecordingsViewModel
    @ObservedObject var channelsVM: ChannelsViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @State private var showPlayer = false
    @State private var showPlaybackChoice: Recording?
    @State private var showDeleteConfirm: Recording?
    @State private var showRetentionPicker: String?

    // Group completed recordings by show name
    private var groupedRecordings: [(showName: String, recordings: [Recording])] {
        let completed = recordingsVM.completedRecordings
        var groups: [String: [Recording]] = [:]
        for rec in completed {
            let name = rec.programTitle
            groups[name, default: []].append(rec)
        }
        // Sort recordings within each group by date (newest first)
        for (key, recs) in groups {
            groups[key] = recs.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }
        // Sort groups alphabetically
        return groups.sorted { $0.key < $1.key }.map { (showName: $0.key, recordings: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                // In-progress recordings
                if !recordingsVM.inProgressRecordings.isEmpty {
                    Section("Recording Now") {
                        ForEach(recordingsVM.inProgressRecordings) { recording in
                            Button(action: { playRecording(recording) }) {
                                RecordingRowView(
                                    recording: recording,
                                    channelName: channelName(for: recording),
                                    onStop: {
                                        Task { await recordingsVM.stopRecording(recording) }
                                    },
                                    onExtend: { minutes in
                                        Task { await recordingsVM.extendRecording(recording, minutes: minutes) }
                                    }
                                )
                            }
                        }
                    }
                }

                // Scheduled recordings
                if !recordingsVM.scheduledRecordings.isEmpty {
                    Section("Scheduled") {
                        ForEach(recordingsVM.scheduledRecordings) { recording in
                            RecordingRowView(
                                recording: recording,
                                channelName: channelName(for: recording)
                            )
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    showDeleteConfirm = recording
                                }
                            }
                        }
                    }
                }

                // Completed recordings grouped by show
                if !groupedRecordings.isEmpty {
                    ForEach(groupedRecordings, id: \.showName) { group in
                        Section {
                            ForEach(group.recordings) { recording in
                                Button(action: { playRecording(recording) }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            if let date = recording.startDate {
                                                Text(DateFormatters.dateTime.string(from: date))
                                                    .font(.subheadline)
                                            }
                                            Text(channelName(for: recording))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        // Resume indicator
                                        if PlayerViewModel.loadPlaybackPosition(recordingId: recording.id) != nil {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundStyle(.blue)
                                                .font(.title3)
                                        }
                                    }
                                }
                                .contextMenu {
                                    Button("Delete Recording", role: .destructive) {
                                        showDeleteConfirm = recording
                                    }
                                    if PlayerViewModel.loadPlaybackPosition(recordingId: recording.id) != nil {
                                        Button("Clear Resume Position") {
                                            PlayerViewModel.clearPlaybackPosition(recordingId: recording.id)
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.showName)
                                Spacer()
                                Text("\(group.recordings.count)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                // Retention rule indicator
                                let retention = getRetention(for: group.showName)
                                if retention > 0 {
                                    Text("Keep \(retention)")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                            .contextMenu {
                                Button("Keep All") { setRetention(for: group.showName, count: 0) }
                                Button("Keep Last 3") { setRetention(for: group.showName, count: 3) }
                                Button("Keep Last 5") { setRetention(for: group.showName, count: 5) }
                                Button("Keep Last 10") { setRetention(for: group.showName, count: 10) }
                                Divider()
                                Button("Delete All Episodes", role: .destructive) {
                                    Task {
                                        for rec in group.recordings {
                                            await recordingsVM.deleteRecording(rec)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Series rules
                if !recordingsVM.recurringRules.isEmpty {
                    Section("Series Rules") {
                        ForEach(recordingsVM.recurringRules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rule.name ?? "Unnamed Rule")
                                        .font(.headline)
                                    HStack(spacing: 4) {
                                        Text(daysText(rule.daysOfWeek ?? []))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("\(rule.startTime) - \(rule.endTime)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(channelName(forId: rule.channel))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if rule.enabled {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await recordingsVM.deleteRule(rule) }
                                }
                            }
                        }
                    }
                }

                if recordingsVM.recordings.isEmpty && recordingsVM.recurringRules.isEmpty && !recordingsVM.isLoading {
                    Section {
                        Text("No recordings. Schedule recordings from the Guide tab.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Recordings")
            .fullScreenCover(isPresented: $showPlayer) {
                PlayerView(playerVM: playerVM, channelsVM: channelsVM, isPresented: $showPlayer)
            }
            .confirmationDialog(
                "This recording is still in progress",
                isPresented: Binding(
                    get: { showPlaybackChoice != nil },
                    set: { if !$0 { showPlaybackChoice = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let recording = showPlaybackChoice {
                    Button("Watch from Start") {
                        playFromFile(recording)
                        showPlaybackChoice = nil
                    }
                    Button("Go to Live") {
                        playLive(recording)
                        showPlaybackChoice = nil
                    }
                    Button("Cancel", role: .cancel) {
                        showPlaybackChoice = nil
                    }
                }
            }
            .confirmationDialog(
                "Delete this recording?",
                isPresented: Binding(
                    get: { showDeleteConfirm != nil },
                    set: { if !$0 { showDeleteConfirm = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let recording = showDeleteConfirm {
                    Button("Delete from Server", role: .destructive) {
                        Task {
                            await recordingsVM.deleteRecording(recording)
                            PlayerViewModel.clearPlaybackPosition(recordingId: recording.id)
                        }
                        showDeleteConfirm = nil
                    }
                    Button("Cancel", role: .cancel) {
                        showDeleteConfirm = nil
                    }
                }
            } message: {
                Text("This will permanently remove the recording from disk.")
            }
        }
        .task {
            await recordingsVM.loadAll()
            enforceRetentionRules()
        }
        .task(id: "auto-refresh") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !recordingsVM.inProgressRecordings.isEmpty {
                    await recordingsVM.loadAll()
                }
            }
        }
        .refreshable {
            await recordingsVM.loadAll()
        }
    }

    // MARK: - Retention Rules

    private func getRetention(for showName: String) -> Int {
        let rules = UserDefaults.standard.dictionary(forKey: "recording_retention") as? [String: Int] ?? [:]
        return rules[showName] ?? 0
    }

    private func setRetention(for showName: String, count: Int) {
        var rules = UserDefaults.standard.dictionary(forKey: "recording_retention") as? [String: Int] ?? [:]
        if count == 0 {
            rules.removeValue(forKey: showName)
        } else {
            rules[showName] = count
        }
        UserDefaults.standard.set(rules, forKey: "recording_retention")
        enforceRetentionRules()
    }

    private func enforceRetentionRules() {
        let rules = UserDefaults.standard.dictionary(forKey: "recording_retention") as? [String: Int] ?? [:]
        for group in groupedRecordings {
            guard let maxKeep = rules[group.showName], maxKeep > 0 else { continue }
            let toDelete = group.recordings.dropFirst(maxKeep)
            for rec in toDelete {
                Task {
                    await recordingsVM.deleteRecording(rec)
                    PlayerViewModel.clearPlaybackPosition(recordingId: rec.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func channelName(for recording: Recording) -> String {
        channelsVM.channels.first { $0.id == recording.channel }?.name ?? "Channel \(recording.channel)"
    }

    private func channelName(forId id: Int) -> String {
        channelsVM.channels.first { $0.id == id }?.name ?? "Channel \(id)"
    }

    private func daysText(_ days: [Int]) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if days.count == 7 { return "Every day" }
        if days.sorted() == [1, 2, 3, 4, 5] { return "Weekdays" }
        if days.sorted() == [0, 6] { return "Weekends" }
        return days.sorted().compactMap { $0 >= 0 && $0 < 7 ? names[$0] : nil }.joined(separator: ", ")
    }

    private func playRecording(_ recording: Recording) {
        if recording.isInProgress {
            showPlaybackChoice = recording
            return
        }
        playFromFile(recording)
    }

    private func playLive(_ recording: Recording) {
        if let channel = channelsVM.channels.first(where: { $0.id == recording.channel }) {
            Task {
                playerVM.setChannelList(channelsVM.filteredChannels)
                await playerVM.play(channel: channel)
                showPlayer = true
            }
        }
    }

    private func playFromFile(_ recording: Recording) {
        Task {
            await playerVM.playRecording(id: recording.id)
            showPlayer = true
        }
    }
}
