import Foundation

struct ShellTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var command = ""
    var directory = FileManager.default.homeDirectoryForCurrentUser.path
    var shell = "/bin/zsh"
    var environment = ""
    var startsAutomatically = true
    var restartsOnFailure = false
    var restartInterval: TimeInterval?

    var expandedDirectory: String { (directory as NSString).expandingTildeInPath }

    var restartIntervalDescription: String? {
        guard let restartInterval else { return nil }
        return TaskTimeFormatting.duration(restartInterval)
    }

    func validated() throws -> ShellTask {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty else { throw TaskError.message(String(localized: "Enter a task name.")) }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TaskError.message(String(localized: "Enter a command to run."))
        }
        guard ![command, directory, shell, environment].contains(where: { $0.contains("\0") }) else {
            throw TaskError.message(String(localized: "Configuration cannot contain null characters."))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TaskError.message(String(localized: "The working directory does not exist. Choose another directory."))
        }
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else {
            throw TaskError.message(String(localized: "The shell must be an absolute path to an executable file."))
        }
        _ = try environmentValues()
        try Self.validateRestartInterval(restartInterval)
        return result
    }

    static func validateRestartInterval(_ interval: TimeInterval?) throws {
        guard let interval else { return }
        guard interval.isFinite, interval >= 1, Date().addingTimeInterval(interval) < .distantFuture else {
            throw TaskError.message(String(localized: "Enter a valid interval of at least 1 second."))
        }
    }

    static func parseRestartInterval(_ text: String, unit: TimeInterval, locale: Locale = .current) throws -> TimeInterval {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
        guard let amount = Double(normalized) else {
            throw TaskError.message(String(localized: "Enter a valid interval of at least 1 second."))
        }
        let interval = amount * unit
        try validateRestartInterval(interval)
        return interval
    }

    func environmentValues() throws -> [String: String] {
        var values: [String: String] = [:]
        for line in environment.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else {
                throw TaskError.message(String(localized: "Enter one environment variable per line as KEY=value."))
            }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw TaskError.message(String(localized: "Invalid environment variable name: \(key)"))
            }
            values[key] = String(line[line.index(after: equals)...])
        }
        return values
    }
}

enum TaskTimeFormatting {
    static func duration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 4
        formatter.zeroFormattingBehavior = .dropAll
        // Duration days are always 24 hours, independent of daylight-saving changes.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = calendar
        return formatter.string(from: max(0, interval.rounded(.down))) ?? ""
    }

    static func remaining(until deadline: Date, now: Date) -> String {
        duration(max(0, deadline.timeIntervalSince(now)).rounded(.up))
    }
}

enum TaskError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

enum RunState: Equatable {
    case stopped, running, stopping, waiting, succeeded, failed
    var label: String {
        switch self {
        case .stopped: String(localized: "Stopped")
        case .running: String(localized: "Running")
        case .stopping: String(localized: "Stopping")
        case .waiting: String(localized: "Waiting to restart")
        case .succeeded: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        }
    }
    var isActive: Bool { self == .running || self == .stopping || self == .waiting }
}
