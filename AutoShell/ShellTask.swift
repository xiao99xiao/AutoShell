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
        guard !result.name.isEmpty else { throw TaskError.message("请输入任务名称。") }
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TaskError.message("请输入要执行的命令。")
        }
        guard ![command, directory, shell, environment].contains(where: { $0.contains("\0") }) else {
            throw TaskError.message("配置不能包含空字符。")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TaskError.message("工作目录不存在，请重新选择。")
        }
        guard shell.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: shell) else {
            throw TaskError.message("Shell 必须是可执行文件的绝对路径。")
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
                throw TaskError.message("环境变量需每行填写 KEY=value。")
            }
            let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
                throw TaskError.message("环境变量名称无效：\(key)")
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
        case .stopped: "已停止"
        case .running: "运行中"
        case .stopping: "正在停止"
        case .waiting: "等待重启"
        case .succeeded: "已完成"
        case .failed: "运行失败"
        }
    }
    var isActive: Bool { self == .running || self == .stopping || self == .waiting }
}
