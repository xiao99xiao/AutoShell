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
                Text(isNew ? String(localized: "Add Task") : String(localized: "Edit Task")).font(.title2.weight(.semibold))
                Text(String(localized: "Configure once. Run automatically when AutoShell opens."))
                    .foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            Form {
                Section {
                    TextField(String(localized: "Task Name"), text: $task.name, prompt: Text(String(localized: "e.g. GitHub Runner")))
                        .accessibilityIdentifier("taskName")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Shell Command"))
                        TextEditor(text: $task.command)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 90)
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(String(localized: "Shell Command"))
                            .accessibilityIdentifier("taskCommand")
                        Text(String(localized: "For example, ./run.sh. Keep commands in the foreground; do not add & or nohup."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField(String(localized: "Working Directory"), text: $task.directory)
                            .accessibilityIdentifier("taskDirectory")
                        Button(String(localized: "Choose…"), action: chooseDirectory)
                    }
                }
                Section {
                    Toggle(String(localized: "Start with AutoShell"), isOn: $task.startsAutomatically)
                    Toggle(String(localized: "Restart on failure"), isOn: $task.restartsOnFailure)
                    Text(String(localized: "Waits 5–60 seconds before restarting. Normal exits and manual stops do not trigger a restart."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(String(localized: "Advanced Settings"), isExpanded: $advanced) {
                    TextField(String(localized: "Shell Path"), text: $task.shell)
                    Text(String(localized: "Runs a noninteractive login shell. Loads login configuration, but not .zshrc."))
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "Environment Variables (one KEY=value per line)"))
                        TextEditor(text: $task.environment)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 70)
                            .accessibilityLabel(String(localized: "Environment Variables"))
                        Text(String(localized: "Values are passed literally; no quotes needed. Configuration is stored locally in plain text."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 12) }
            Divider()
            HStack {
                Text(String(localized: "Saving does not start the command."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Save Task")) {
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
        panel.prompt = String(localized: "Choose Working Directory")
        panel.directoryURL = URL(fileURLWithPath: task.expandedDirectory)
        if panel.runModal() == .OK, let url = panel.url { task.directory = url.path }
    }
}
