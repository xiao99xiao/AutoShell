import SwiftUI
import AppKit

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var task: ShellTask
    let isNew: Bool
    let save: (ShellTask) throws -> Void
    @State private var error: String?
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(isNew ? "添加任务" : "编辑任务").font(.title2.weight(.semibold))
                Text("配置一次，每次打开 App 自动运行。")
                    .foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            Form {
                Section {
                    TextField("任务名称", text: $task.name, prompt: Text("例如：GitHub Runner"))
                        .accessibilityIdentifier("taskName")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shell 命令")
                        TextEditor(text: $task.command)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 90)
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("Shell 命令")
                            .accessibilityIdentifier("taskCommand")
                        Text("例如 ./run.sh。使用前台常驻命令，不要添加 & 或 nohup。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("工作目录", text: $task.directory)
                            .accessibilityIdentifier("taskDirectory")
                        Button("选择…", action: chooseDirectory)
                    }
                }
                Section {
                    Toggle("随 AutoShell 启动", isOn: $task.startsAutomatically)
                    Toggle("失败后自动重启", isOn: $task.restartsOnFailure)
                    Text("自动重启等待 5–60 秒；正常退出或手动停止不会触发。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("高级设置", isExpanded: $advanced) {
                    TextField("Shell 路径", text: $task.shell)
                    Text("以非交互登录 Shell 运行，会读取登录配置；不会自动读取 .zshrc。")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("环境变量（每行 KEY=value）")
                        TextEditor(text: $task.environment)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 70)
                            .accessibilityLabel("环境变量")
                        Text("值按原样传入，无需引号。配置保存在本机，请勿填写需要加密保管的密钥。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            HStack {
                Text("保存不会立即运行命令。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存任务") {
                    do { try save(task); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }.padding(20)
        }
        .frame(width: 580, height: advanced ? 750 : 590)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择工作目录"
        panel.directoryURL = URL(fileURLWithPath: task.expandedDirectory)
        if panel.runModal() == .OK, let url = panel.url { task.directory = url.path }
    }
}
