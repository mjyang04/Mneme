# Mneme P3 — Activity Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Activity Log module so Mneme can collect authorized folder activity, summarize it into a managed Obsidian daily-note block, expose it in the app, and index the generated activity notes.

**Architecture:** Keep collection, rendering, writing, and indexing in `MnemeCore` so each piece is testable. The SwiftUI app only configures watched folders, runs refresh, and displays recent generated activity text.

**Tech Stack:** Swift 5.10 / macOS 14 · SwiftPM · Foundation `FileManager`/`Process` · GRDB-backed existing index path · SwiftUI app shell.

---

## Scope

Included in this P3 pass:
- Authorized workspace folder refresh based on file metadata.
- Ignore rules for noisy paths such as `.git`, `node_modules`, `build`, `outputs`, lockfiles, `.DS_Store`, and editor swap files.
- Git commit collection through local `git log` for authorized repositories.
- Daily activity markdown rendering.
- Managed-block daily-note writer that preserves all user text outside Mneme markers.
- `ActivityConnector` so generated daily notes participate in global search.
- App Activity view with watched folders, daily-note folder, manual refresh, and status.
- App-scoped background FSEvents watching for configured workspace folders, with debounce and automatic refresh.
- Optional MLX daily summary with a dedicated no-fabrication prompt, Settings toggle, deterministic fallback, and managed-block write-back.

## Files

- Create: `Sources/MnemeCore/Activity/ActivityTypes.swift`
- Create: `Sources/MnemeCore/Activity/ActivityIgnoreRules.swift`
- Create: `Sources/MnemeCore/Activity/FileActivityCollector.swift`
- Create: `Sources/MnemeCore/Activity/GitActivityCollector.swift`
- Create: `Sources/MnemeCore/Activity/DailyActivityRenderer.swift`
- Create: `Sources/MnemeCore/Activity/DailyNoteWriter.swift`
- Create: `Sources/MnemeCore/Activity/ActivityLogService.swift`
- Create: `Sources/MnemeCore/Activity/ActivityEventBatcher.swift`
- Create: `Sources/MnemeCore/Activity/ActivitySummaryGenerator.swift`
- Create: `Sources/MnemeCore/Connectors/ActivityConnector.swift`
- Modify: `App/AppEnvironment.swift`
- Modify: `App/Sources/SourcesStore.swift`
- Modify: `App/Search/MainWindow.swift`
- Create: `App/Activity/ActivityView.swift`
- Create: `App/Activity/ActivityFolderWatcher.swift`
- Create: `App/Activity/MLXLocalActivitySummaryGenerator.swift`
- Create tests under `Tests/MnemeCoreTests/Activity*Tests.swift`

## Tasks

### Task 1: Activity Models And Ignore Rules

- [x] Write failing tests for default ignore behavior and daily activity grouping.
- [x] Implement `FileTouch`, `GitCommit`, `ProjectActivity`, `DailyActivity`, and `ActivityIgnoreRules`.
- [x] Run focused tests.

### Task 2: File And Git Collectors

- [x] Write failing tests for enumerating changed files under a workspace root.
- [x] Write failing tests for parsing `git log --numstat` output.
- [x] Implement `FileActivityCollector` and `GitActivityCollector`.
- [x] Run focused tests.

### Task 3: Daily Markdown Writer

- [x] Write failing tests proving managed-block insert/update preserves user text.
- [x] Implement `DailyActivityRenderer` and `DailyNoteWriter`.
- [x] Run focused tests.

### Task 4: ActivityConnector And Service

- [x] Write failing tests for `ActivityConnector` extraction and `ActivityLogService.refresh`.
- [x] Implement connector and service.
- [x] Run focused tests.

### Task 5: App Integration

- [x] Add Activity tab/view for watched folders, daily-note folder, manual refresh, and generated preview.
- [x] Route `.activity` source configs to `ActivityConnector`.
- [x] Run `swift test` and `swift build`.

### Task 6: Background Folder Watching

- [x] Write failing tests for filtering, deduplicating, and prefix-safe workspace matching.
- [x] Implement `ActivityEventBatcher`.
- [x] Implement app-scoped FSEvents watcher with 2-second debounce.
- [x] Add Activity tab controls to start/stop background watching.
- [x] Run focused tests, full tests, build, and app startup smoke.

### Task 7: Optional MLX Summary

- [x] Add summary field rendering at the top of the managed activity block.
- [x] Add prompt builder and deterministic fallback summary tests.
- [x] Add MLX-backed activity summary generator and Settings toggle.
- [x] Add diagnostic entry point for activity summary generation.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

Current result:
- `swift test --filter ActivityEventBatcherTests`: 3 XCTest tests passed, 0 failures.
- `swift test`: 74 XCTest tests passed, 0 failures.
- `swift build`: build complete.
- `swift run Mneme`: app launched and stayed alive during smoke check; stopped with SIGINT.
- `MNEME_ACTIVITY_SUMMARY_DIAGNOSTIC=1 .build/Mneme.app/Contents/MacOS/Mneme`: PASS outside the tool sandbox.

## Product Limits After P3

- Manual refresh and app-scoped background FSEvents watching are product-usable while Mneme is running.
- MLX summary is product-wired behind a toggle and falls back to a deterministic summary if the local model cannot generate.
