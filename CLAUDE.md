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

### LogcatView.swift

Contains three tightly coupled components:

1. **LogcatView** — SwiftUI view with toolbar hosting the scroll view
2. **LogcatScrollView** — `NSViewRepresentable` bridging AppKit's `NSScrollView`/`NSTextView` into SwiftUI for performant log display. Uses a Coordinator to track scroll position and manage auto-scroll behavior.
3. **LogcatManager** — `@Observable` class that manages the `adb logcat` process lifecycle. Searches for `adb` via shell `which`, common install paths, and `ANDROID_HOME`/`ANDROID_SDK_ROOT` env vars. Caps log buffer at a configurable number of lines.

### Concurrency Model

- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- Process output is read asynchronously with Swift async/await
