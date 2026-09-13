# AutoShell
<!-- impeccable:product-schema 1 -->

## Platform
Native macOS (SwiftUI and AppKit).

## Users and purpose
A personal utility for keeping multiple long-running shell commands, such as local GitHub Actions runners, running without reopening Terminal after every login.

## Confirmed capabilities
- User adds AutoShell to macOS Login Items manually.
- Tasks may start automatically when AutoShell opens.
- Menu bar access, task management, manual start/stop/restart, and detailed logs.
- Per-task periodic restart intervals, configurable while running, with a visible next restart time.
- Unexpected exits show failure by default; user explicitly selected manual restart.

## Implementation decisions
Native task list and detail window, with menu bar shortcuts. Commands run as noninteractive login shells. Terminal offers read-only log following. App exit stops owned process groups; closing a window does not. Optional per-task failure restart. App Sandbox is disabled to run local tools. No example command runs until the user saves and starts it.

## Languages
English is the default/source and fallback language. The interface follows macOS language preferences and includes Simplified Chinese translations. User content and process output are never translated.
