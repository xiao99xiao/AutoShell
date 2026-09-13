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

    var expandedDirectory: String { (directory as NSString).expandingTildeInPath }

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
        return result
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
