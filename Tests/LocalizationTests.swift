import Foundation

/// Runs inside an isolated test bundle containing the app's compiled language resources.
@main
@MainActor
struct LocalizationTests {
    static func main() throws {
        let expectedLanguage = ProcessInfo.processInfo.environment["EXPECTED_LANGUAGE"] ?? "en"
        let chinese = expectedLanguage == "zh-Hans"
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw TaskError.message("FAIL: \(message)") }
            print("PASS: \(message)")
        }
        try check(Bundle.main.preferredLocalizations.first == expectedLanguage, "language selection and English fallback")
        try check(String(localized: "Cancel") == (chinese ? "取消" : "Cancel"), "static control label")
        try check(RunState.failed.label == (chinese ? "运行失败" : "Failed"), "runtime task status")
        try check(String(localized: "Add Task") == (chinese ? "添加任务" : "Add Task"), "editor title")
        try check(String(localized: "Manage Tasks…") == (chinese ? "管理任务…" : "Manage Tasks…"), "menu label")
        for count in [0, 1, 5] {
            let message = String(localized: "Running tasks: \(count)")
            try check(message == (chinese ? "\(count) 个任务运行中" : "Running tasks: \(count)"), "interpolated count \(count)")
        }
        let child: Int32 = 123
        try check(String(localized: "Started PID \(child)") == (chinese ? "启动 PID 123" : "Started PID 123"), "process log interpolation")
        do {
            _ = try ShellTask().validated()
            throw TaskError.message("validation unexpectedly succeeded")
        } catch {
            try check(error.localizedDescription == (chinese ? "请输入任务名称。" : "Enter a task name."), "model validation error")
        }
        let name = "Runner '项目' 100%"
        let deletion = String(localized: "Delete the configuration for “\(name)”? Existing logs will stay on this Mac.")
        try check(deletion.contains(name), "user text preserved in localized message")
        let state = RunState.failed
        let code: Int32 = 7
        try check(String(localized: "\(state.label) · Exit code \(code)") == (chinese ? "运行失败 · 退出码 7" : "Failed · Exit code 7"), "combined runtime status and exit code")
        let header = String(localized: "AutoShell · Live log (read-only; press Control-C to stop viewing)")
        try check(header == (chinese ? "AutoShell · 实时日志（只读，按 Control-C 结束查看）" : "AutoShell · Live log (read-only; press Control-C to stop viewing)"), "Terminal viewer heading")
        print("Localization checks passed for \(expectedLanguage).")
    }
}
