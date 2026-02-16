# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Skippy is a macOS desktop application (SwiftUI) that provides a GUI assistant for development with the Skip open source project (https://skip.dev).

## Build & Test Commands

```bash
# Build (from repo root)
xcodebuild -scheme Skippy -project Skippy/Skippy.xcodeproj -configuration Debug

# Run tests
xcodebuild test -scheme Skippy -project Skippy/Skippy.xcodeproj -configuration Debug

# Open in Xcode
open Skippy/Skippy.xcodeproj
```

## Architecture

### Windows

Managed by `SkippyApp`, which creates manager instances as `@State` and injects them via `.environment()`:

- **Main window** → `ContentView` (placeholder)
- **Logcat window** (Cmd+Shift+L) → `LogcatView`
- **Emulators window** (Cmd+Shift+E) → `EmulatorView`
- **New Emulator window** (via Create button) → `NewEmulatorView`
- **Doctor window** (Debug menu) → `CheckupView(command: .doctor)`
- **Checkup window** (Debug menu) → `CheckupView(command: .checkup)`
- **Settings** → `SettingsView`

### Key Components

- **CommandFinder.swift** — Locates CLI tools (`adb`, `skip`, `avdmanager`, `sdkmanager`) via shell lookup and candidate directories. Returns `FoundCommand` with path and environment for spawning.
- **LogcatManager.swift** — Manages streaming `adb logcat` process lifecycle.
- **LogcatView.swift** — Displays/filters/searches logcat output. Uses `LogcatScrollView` (`NSViewRepresentable`) for performant AppKit text rendering.
- **EmulatorManager.swift** — Lists, launches, and deletes emulators via `skip` and `avdmanager` CLIs. Checks for already-running devices before launch.
- **CreateEmulatorManager.swift** — Loads device profiles and API levels from `avdmanager`, creates emulators via `skip android emulator create` with streaming output.
- **EmulatorView.swift** — Emulator list with toolbar actions (Create, Refresh, Launch, Delete) and command output panel.
- **NewEmulatorView.swift** — Form for creating emulators with device profile/API level pickers and streaming output.
- **CommandOutputView.swift** — Reusable `NSViewRepresentable` for scrolling monospaced command output with auto-scroll. `AnimatedCommandOutputView` wrapper adds an "Executing..." indicator.
- **CheckupManager.swift** — Runs `skip doctor` and `skip checkup` commands with streaming output and log file support.
- **CheckupView.swift** — Shared view for Doctor and Checkup windows with command output, copy/save toolbar actions, and log file link.
- **SettingsView.swift** — App settings (logcat buffer size).

### Concurrency Model

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- Process output is read asynchronously with Swift async/await
