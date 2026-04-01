import Foundation

@MainActor
final class RecordingsViewModel: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var recurringRules: [RecurringRule] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var inProgressRecordings: [Recording] {
        recordings.filter { $0.isInProgress }
    }

    var scheduledRecordings: [Recording] {
        recordings.filter { $0.isScheduled }
    }

    var completedRecordings: [Recording] {
        recordings.filter { $0.isCompleted }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil

        do {
            async let recordingsTask = PineappleStackAPI.getRecordings()
            async let rulesTask = PineappleStackAPI.getRecurringRules()

            let (fetchedRecordings, fetchedRules) = try await (recordingsTask, rulesTask)
            recordings = fetchedRecordings
            recurringRules = fetchedRules
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func scheduleRecording(
        channelId: Int,
        startTime: Date,
        endTime: Date,
        program: RecordingProgram? = nil
    ) async {
        do {
            let newRecording = try await PineappleStackAPI.createRecording(
                channelId: channelId,
                startTime: startTime,
                endTime: endTime,
                program: program
            )
            recordings.append(newRecording)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording(_ recording: Recording) async {
        do {
            try await PineappleStackAPI.stopRecording(id: recording.id)
            // Wait for server to finish processing the stop
            try? await Task.sleep(for: .seconds(2))
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecording(_ recording: Recording) async {
        do {
            try await PineappleStackAPI.deleteRecording(id: recording.id)
            recordings.removeAll { $0.id == recording.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSeriesRule(
        channelId: Int,
        name: String,
        program: Program
    ) async {
        guard let start = program.startDate, let end = program.endDate else { return }
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: start) - 1 // 0=Sunday
        let startTimeStr = DateFormatters.timeOnly24h.string(from: start)
        let endTimeStr = DateFormatters.timeOnly24h.string(from: end)

        do {
            let rule = try await PineappleStackAPI.createRecurringRule(
                channelId: channelId,
                name: name,
                daysOfWeek: [dayOfWeek],
                startTime: startTimeStr,
                endTime: endTimeStr
            )
            recurringRules.append(rule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRule(_ rule: RecurringRule) async {
        do {
            try await PineappleStackAPI.deleteRecurringRule(id: rule.id)
            recurringRules.removeAll { $0.id == rule.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func extendRecording(_ recording: Recording, minutes: Int) async {
        do {
            try await PineappleStackAPI.extendRecording(id: recording.id, minutes: minutes)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
