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

The app has multiple windows managed by `SkippyApp`:
- **Main window** → `ContentView` (placeholder)
- **Logcat window** (Cmd+Shift+L) → `LogcatView` (view the output of `adb logcat`)
- **Emulators window** (Cmd+Shift+E) → `EmulatorView` (list, launch, delete Android emulators)
- **New Emulator window** (via Create button) → `NewEmulatorView` (create emulators with device profile/API level selection)

### CommandFinder.swift

Shared utility (`enum CommandFinder`) for locating CLI tools (`adb`, `skip`, `avdmanager`, `sdkmanager`). Maintains a single list of candidate directories (general bin dirs + Android SDK subdirectories derived from `ANDROID_HOME`/`ANDROID_SDK_ROOT` env vars and common install locations). Provides `toolPATH` for setting `PATH` on spawned processes so child commands can find sibling tools.

### LogcatView.swift

Contains three tightly coupled components:

1. **LogcatView** — SwiftUI view with toolbar hosting the scroll view
2. **LogcatScrollView** — `NSViewRepresentable` bridging AppKit's `NSScrollView`/`NSTextView` into SwiftUI for performant log display. Uses a Coordinator to track scroll position and manage auto-scroll behavior.
3. **LogcatManager** — `@Observable` class that manages the `adb logcat` process lifecycle. Uses `CommandFinder.findAdb()` to locate the executable. Caps log buffer at a configurable number of lines.

### EmulatorManager.swift

`@Observable @MainActor` class managing Android emulator lifecycle via the `skip` and `avdmanager` CLIs:
- **List/Refresh** — runs `skip android emulator list`, parses one-name-per-line output
- **Create** — runs `skip android emulator create` with streaming output displayed in `NewEmulatorView`; closes the window on success
- **Delete** — runs `avdmanager delete avd`, refreshes list on completion
- **Launch** — runs `skip android emulator launch`, optionally with `--name` and `--android-home`
- **Device profiles/API levels** — loaded from `avdmanager list device` and `avdmanager list target`

A single `EmulatorManager` instance is created as `@State` in `SkippyApp` and injected via `.environment()` into both emulator window groups.

### EmulatorView.swift

Emulators window with a `List` of emulator names, toolbar buttons (Create, Refresh, Launch, Delete), delete confirmation dialog, and a command output panel showing commands run from this window.

### NewEmulatorView.swift

Form for creating emulators with Device Profile and API Level pickers (defaults to `pixel_7` and API 34), auto-generated name field with uniqueness checking, and streaming command output display.

### Concurrency Model

- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- Process output is read asynchronously with Swift async/await
