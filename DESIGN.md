---
name: AutoShell
description: Native macOS task management with clear status and readable logs.
---

# Design System: AutoShell

## Overview

AutoShell is a native macOS utility in Operate mode. Its interface uses English source copy with a Simplified Chinese localization, system typography and colors, SF Symbols, and standard macOS controls. The visual character is restrained and practical, with task status and readable output taking priority.

**Key Characteristics:**
- Native sidebar navigation and focused task details.
- Explicit status words paired with recognizable symbols.
- Logs occupy the remaining detail height.
- System-managed appearance, selection, focus, and control states.

## App identity

The Loop Prompt mark combines a circular arrow (continuous execution) with a Shell `>` prompt. The prompt is optically centered by shifting it slightly right. The loop arrowhead has rounded corners and follows the tangent at the arc endpoint for a continuous, aligned join. The App icon uses a flat dark evergreen tile (`#142523`), a mint loop (`#67E8B5`), and an off-white prompt (`#F2FFF9`). These fixed colors apply to branding assets only; interface controls retain semantic system colors.

The menu bar uses a separate 18 pt monochrome template with slightly stronger small-size geometry. macOS provides its appearance-aware tint. A 26 pt variant adds a separate exclamation indicator for failed tasks. Preserve transparent margins and the 1x/2x image representations. SVG originals and PNG exports live in `logos/export/`; `logos/preview.html` provides size and appearance comparisons.

## Colors

Use semantic SwiftUI and AppKit colors so surfaces and text follow system appearance; do not replace them with fixed light-mode hex values.

- Primary actions use the system accent through bordered prominent buttons.
- Detail status words and the sidebar running count use `.primary`. Sidebar row status and supporting metadata use `.secondary`.
- Status symbols use green for running/succeeded, red for failed, orange for waiting/stopping, and secondary for stopped. State remains understandable from its text and symbol without color.
- The detail uses `.background`; the command summary uses a faint quaternary fill. Logs use AppKit `.textColor` and `.textBackgroundColor`.
- Editor validation and log errors use red text. This is distinct from the symbol-only color treatment for routine task status.

## Typography

Use the macOS system font and semantic SwiftUI text styles: semibold title for the task name, semibold title2 for the editor, headline for logs, body for task rows, and callout/caption for status and metadata. Commands and environment-variable editors use system monospace. Log output uses regular system monospace at 12 pt. Process IDs use monospaced digits; paths retain normal system text.

## Layout

The management window is a SwiftUI `Window` scene with a default size of 1060 × 700 pt and a content minimum of 830 × 530 pt, enforced by `.windowResizability(.contentMinSize)`. The navigation sidebar allows 220–310 pt and prefers 250 pt.

The system toolbar contains the automatic sidebar toggle and an Add Task primary action. The sidebar contains a task list, running count, and login-settings link. The selected task detail stacks its name/status, lifecycle actions, command summary, and log panel. Main detail insets are 24 pt; sidebar footer insets are 20 pt. The log area absorbs available vertical space. Long log lines scroll horizontally; commands show up to three lines and directory labels truncate in the middle with a full-path help tooltip.

The editor is a fixed-width sheet (580 pt), growing from 590 to 750 pt high when advanced settings expand. No web breakpoints or mobile layout are defined.

## Elevation & Depth

System window, sheet, menu, and control treatments provide depth. Inside the content, dividers and subtle tonal grouping establish sections. The implementation adds no custom shadows or motion choreography.

## Shapes

Native controls retain system shapes. The command summary has an 8 pt corner radius and 14 pt padding; the command editor background has a 6 pt radius. SF Symbols carry action and state meaning without decorative illustration.

## Components

- **Navigation:** `NavigationSplitView` is the root of the SwiftUI window. Its native sidebar list displays task names, state words/symbols, and an automatic-start indicator. SwiftUI manages the title bar, sidebar toggle, selection, and keyboard focus. `SidebarCommands` provides the system View menu command. Keep the automatic toolbar style; do not recreate the toggle or host this root in a manually constructed window.
- **Window lifecycle:** `openWindow(id:)` opens or focuses the single management window from the menu bar or app reopen event. Default launch presentation and window restoration are suppressed so configured tasks start quietly. An empty configuration or load error opens the manager after startup. Closing it keeps tasks alive; quitting the app stops them.
- **Actions:** Start and save use bordered prominent buttons. Stop/restart are available while active and disabled during stopping. Editing and deletion are disabled while active; deletion uses a confirmation alert.
- **Editor:** A grouped form holds name, command, directory, startup/restart toggles, and an advanced disclosure for shell/environment fields. Cancel/save use standard keyboard actions; inline validation keeps the sheet open. Footer copy states that saving does not immediately run commands.
- **Logs:** Selectable, read-only AppKit text supports search by matching lines, follow output, pause/resume display, copy of visible text, and Terminal access. Pausing display leaves recording active, explained by help/footer text. Separate empty-output and no-search-results states use native unavailable views.
- **Empty selection:** A native unavailable view explains task creation or prompts selection, with an add-task action.
- **Menu bar:** Native menus show running count, each task's state, detail access, lifecycle actions, and an explicitly labeled quit-and-stop action.
- **Accessibility:** Icon-only add/copy actions have accessible labels; task rows combine their elements. Retain system focus and disabled states and text labels alongside status symbols.

## Do's and Don'ts

- **Do** keep status words legible in primary/secondary system text and reserve routine state color for symbols.
- **Do** preserve selectable logs, native keyboard behavior, and concise localized action labels.
- **Do** keep output prominent when adding task-management controls.
- **Don't** introduce fixed color replacements, custom control chrome, decorative dashboards, or gratuitous animation into this utility.
- **Don't** treat implementation intent as verification: the recorded visual review covers the inspected running-task and compact-window screenshots, not every state or system appearance.

## Localization

English (`en`) is the source and fallback language; Simplified Chinese (`zh-Hans`) is supported through `AutoShell/Localizable.xcstrings`. Use `String(localized:)` for runtime messages, conditional labels, menus, accessibility labels, and app-generated log messages. Preserve task names, paths, commands, and command output verbatim. Follow macOS language preferences instead of forcing a locale. Review long translations in the editor, sidebar footer, and log toolbar.

## Native navigation references

- [Apple: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [Apple: SidebarCommands](https://developer.apple.com/documentation/swiftui/sidebarcommands)
- [Apple: Window](https://developer.apple.com/documentation/swiftui/window)
- [WWDC25: Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
