import SwiftUI

struct RestartScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    let task: ShellTask
    let save: (TimeInterval?) throws -> Void
    @State private var enabled: Bool
    @State private var amount: String
    @State private var unit: RestartIntervalUnit
    @State private var error: String?

    init(task: ShellTask, save: @escaping (TimeInterval?) throws -> Void) {
        self.task = task
        self.save = save
        let interval = task.restartInterval ?? 7200
        let unit = RestartIntervalUnit.allCases.reversed().first {
            interval.truncatingRemainder(dividingBy: $0.seconds) == 0
        } ?? .seconds
        _enabled = State(initialValue: task.restartInterval != nil)
        _unit = State(initialValue: unit)
        _amount = State(initialValue: (interval / unit.seconds).formatted(.number.grouping(.never)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Automatic Restart")).font(.title2.weight(.semibold))
                Text(task.name).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(24)
            Divider()
            Form {
                Section {
                    Toggle(String(localized: "Restart periodically"), isOn: $enabled)
                        .accessibilityIdentifier("periodicRestartEnabled")
                    HStack {
                        Text(String(localized: "Restart every"))
                        Spacer()
                        TextField(String(localized: "Interval"), text: $amount)
                            .labelsHidden()
                            .frame(width: 100)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("restartInterval")
                        Picker(String(localized: "Time Unit"), selection: $unit) {
                            ForEach(RestartIntervalUnit.allCases) { unit in
                                Text(unit.label).tag(unit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 115)
                        .accessibilityIdentifier("restartIntervalUnit")
                    }
                    .disabled(!enabled)
                }
                Section {
                    Text(String(localized: "The interval starts when you save these settings or start the task. Each restart waits for the current process to stop before starting a new one."))
                    Text(String(localized: "Stopping the task pauses the schedule. Starting it resumes the schedule. Unexpected exits follow the task’s failure settings. An overdue restart runs once after your Mac wakes."))
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Save")) {
                    do {
                        var interval: TimeInterval?
                        if enabled {
                            interval = try ShellTask.parseRestartInterval(amount, unit: unit.seconds)
                        }
                        try ShellTask.validateRestartInterval(interval)
                        try save(interval)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("saveRestartSchedule")
            }
            .padding(20)
        }
        .frame(width: 520, height: 450)
    }
}

private enum RestartIntervalUnit: CaseIterable, Identifiable {
    case seconds, minutes, hours, days
    var id: Self { self }
    var seconds: TimeInterval {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        case .days: 86400
        }
    }
    var label: String {
        switch self {
        case .seconds: String(localized: "Seconds")
        case .minutes: String(localized: "Minutes")
        case .hours: String(localized: "Hours")
        case .days: String(localized: "Days")
        }
    }
}
