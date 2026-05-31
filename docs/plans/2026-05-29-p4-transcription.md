# Mneme P4 — Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the transcription module's durable product path: WhisperKit audio transcription, transcript persistence, indexing, Obsidian export, and a UI for importing audio or existing transcript text.

**Architecture:** Store completed transcripts as JSON documents under Application Support. `WhisperKitTranscriptionService` streams timestamped segments into `TranscriptImportService`, and `TranscriptConnector` exposes stored transcript JSON documents to the existing indexing pipeline. `TranscriptObsidianExporter` writes frontmatter and timestamped segments with managed markers so user notes outside Mneme content survive repeated exports.

**Tech Stack:** Swift 5.10 / macOS 14 · SwiftPM · WhisperKit · AVFoundation · Foundation JSON files · existing `MnemeCore` connector/indexing stack · SwiftUI.

---

## Scope

Included:
- Transcript data types with segment timestamps.
- JSON-backed `TranscriptStore`.
- Plain-text import service for existing transcripts.
- `TranscriptConnector` for indexing completed transcripts.
- Obsidian markdown export with frontmatter and timestamped segment list.
- SwiftUI Transcripts tab for importing text, viewing transcript details, exporting, and reindexing.
- Audio file picker and drag/drop, model/language options, explicit first-download permission, WhisperKit transcription, automatic transcript persistence, and indexing handoff.
- Voice-memo/audio folder watching with manual scan and FSEvents-triggered import of new supported files.
- Timestamp segment playback using `AVPlayer`.

Deferred:
- Speaker diarization.
- Long-audio performance tuning and mixed-language recording validation.

## Tasks

### Task 1: Transcript Core

- [x] Write failing tests for transcript persistence and text aggregation.
- [x] Add `TranscriptSegment`, `TranscriptDocument`, `TranscriptStore`, and `TranscriptImportService`.
- [x] Run focused tests.

### Task 2: Connector And Exporter

- [x] Write failing tests for `TranscriptConnector` and Obsidian export.
- [x] Implement connector and exporter.
- [x] Run focused tests.

### Task 3: App Integration

- [x] Add transcript store to `AppEnvironment`.
- [x] Add Transcripts tab with import, list, detail, and export path.
- [x] Route `.transcript` source configs to `TranscriptConnector`.
- [x] Run full tests and build.

### Task 4: WhisperKit Audio Path

- [x] Add audio import tests with a stub transcription service.
- [x] Add supported-audio validation and special-token cleanup.
- [x] Implement WhisperKit-backed transcription service.
- [x] Add audio controls, drag/drop, model options, status text, indexing handoff, and timestamp playback to `TranscriptsView`.
- [x] Run focused tests, full tests, bundle diagnostics, and app smoke.

### Task 5: Voice Memo Folder Intake

- [x] Add watched-audio-folder settings.
- [x] Add manual scan for new supported audio files.
- [x] Add FSEvents watcher that debounces folder changes and imports unprocessed audio files.
- [x] Skip already imported audio by persisted `sourceAudioPath`.

## Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`

Current result:
- `swift test --filter TranscriptStoreTests`: 5 XCTest tests passed, 0 failures.
- `swift test`: 74 XCTest tests passed, 0 failures.
- `swift build`: build complete.
- `MNEME_TRANSCRIBE_DIAGNOSTIC_AUDIO=/private/tmp/en-uk-hello-6.wav MNEME_TRANSCRIBE_DIAGNOSTIC_MODEL=tiny MNEME_TRANSCRIBE_DIAGNOSTIC_LANGUAGE=en .build/Mneme.app/Contents/MacOS/Mneme`: PASS outside the tool sandbox, 1 segment, text `Hello`.
