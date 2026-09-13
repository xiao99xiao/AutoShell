# AutoShell

<img src="logos/export/logo-192.png" width="96" height="96" alt="AutoShell logo">

English · [简体中文](README.zh-Hans.md)

A native macOS menu bar app for managing long-running shell commands, including local GitHub Actions runners and development servers.

## Getting started

1. Open the Xcode project, select the **AutoShell** scheme, and run the app. The task manager opens on first launch.
2. Choose **Add Task** and enter a name, shell command, and working directory.
3. Enable **Start with AutoShell** if desired. Save, then choose **Start Task** to verify it. Saving alone never runs a command.
4. Add a stable copy of AutoShell.app to macOS **Login Items**. The sidebar provides a shortcut to these settings. Avoid using a temporary build location for a permanent login item.
5. Use the menu bar to check task status, start, stop, restart, or open logs.

### GitHub Actions runner example

Download and configure your runner with `config.sh` first, then create a task:

- **Name:** GitHub Runner
- **Working Directory:** your actual `actions-runner` directory
- **Shell Command:** `./run.sh`
- **Start with AutoShell:** enabled
- **Restart on failure:** disabled by default; enable if needed

Commands must stay in the foreground. Do not add `&`, `nohup`, `disown`, or daemon mode, and do not run the same runner through another service manager at the same time.

## Languages

English is the source and fallback language. English and Simplified Chinese are included. AutoShell follows macOS language preferences, including per-app language selection; reopen the app after changing its language.

UI labels, menus, accessibility text, validation errors, and AutoShell-generated log messages use `AutoShell/Localizable.xcstrings`. Task names, commands, paths, and process output remain unchanged. To support another language, add translations to the String Catalog in Xcode without changing business logic.

## Task behavior

- Closing the manager window keeps tasks running. Quitting AutoShell sends SIGTERM to each task's process group and forces remaining processes to exit after five seconds.
- Restart waits for the old process to exit. Repeated start requests do not create duplicate processes.
- Failed tasks remain failed by default and show an exit code. Optional recovery applies only to nonzero exits, with a delay increasing from 5 to 60 seconds. A manual stop cancels recovery; running for more than 60 seconds resets the backoff.
- Commands use the selected shell's `-l -c` mode, defaulting to `/bin/zsh`. Login configuration is loaded, but `.zshrc` is not loaded automatically. Initialize tools such as nvm or conda explicitly, or use absolute executable paths. Common Homebrew paths are added to the initial PATH, which login configuration can still override.
- Environment variables use one `KEY=value` per line. Values are literal: do not add shell quotes or expect variable expansion. Configuration is stored locally in plain text with owner-only access.
- Standard input comes from `/dev/null`. Run password prompts, interactive TUIs, and commands requiring a real terminal in Terminal. Some tools buffer output; use their unbuffered option if needed, such as Python's `-u`.

## Periodic restarts

Select a task, then choose **Configure…** beside **Automatic Restart**. Enable **Restart periodically** and enter an interval in seconds, minutes, hours, or days (at least one second). You can change or disable the schedule while the task is running. The interval is saved for each task.

Saving the setting or starting the task begins a fresh interval. When it is due, AutoShell stops the current process group, waits for it to exit, then starts a new process and resets the interval. The task details show full start/restart dates, elapsed running time, and a live restart countdown. Durations include days, hours, minutes, and seconds. The log records each scheduled restart.

Closing the window keeps the schedule running. Stopping a task or quitting AutoShell cancels its countdown; the saved interval resumes when the task starts again. Unexpected exits still follow **Restart on failure**, which is off by default. AutoShell must remain running; it does not wake your Mac. After sleep, an overdue restart runs once, followed by a fresh interval.

## Logs

Standard output and standard error are combined. The app displays the latest 128 KB and supports search, pause display, follow output, and copy. Each task keeps a current log and one archive, each up to 5 MB.

**View in Terminal** follows the same log with `tail -F`, including rotation. This is read-only viewing, not attachment to the running process. Control-C stops viewing without stopping the task.

Local files:

```text
~/Library/Application Support/AutoShell/
  tasks.json
  Logs/<task-id>.log
  Logs/<task-id>.log.1
  Terminal/<task-id>.command
```

Deleting a task removes its configuration and retains logs. Unreadable configuration is reported and protected from being overwritten.

## Limits

AutoShell manages foreground commands; it is not a launchd service manager. Normal app exit cleans up owned process groups. Cleanup is not guaranteed after force quit, an app crash, or a task detaching from its process group; check for old processes before restarting in those cases. Tasks cannot be guaranteed to continue while the Mac sleeps.

App Sandbox is disabled to run local tools and access working directories. Hardened Runtime remains enabled. The project retains the Xcode template's macOS 26.5 deployment target.

## Development and verification

```sh
xcodebuild -scheme AutoShell -configuration Debug \
  -derivedDataPath /tmp/AutoShell-build build CODE_SIGNING_ALLOWED=NO

./Tests/run.sh
./Tests/test-localizations.sh
```

Integration tests run real processes in isolated temporary directories. They cover persistence, automatic startup, stdout/stderr, working directories, literal environment variables, exit codes, duplicate starts, process-group cleanup, forced stops, restart order, recovery cancellation, log rotation, quit cleanup, and corrupt configuration protection.

Localization checks use the built app's compiled resources in an isolated test bundle. They verify English, Simplified Chinese, unsupported-language fallback, counts, runtime statuses, validation messages, process-log messages, and preservation of user text. Pass another built `.app` path as the script's first argument if needed.

Requires macOS and Xcode Command Line Tools; no external package dependencies.
