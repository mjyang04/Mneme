# Release Notes

## Unreleased

### Platform Status

- macOS remains the packaged release platform for v0.1.0 through `Mneme-v0.1.0-macos-arm64.dmg`.
- Windows is now covered by a development preview under `Windows/`; it is runnable and tested, but not yet a packaged native Windows installer.

### Windows Development Preview

- Added a Windows development preview under `Windows/`.
- Added a Mneme-style workbench UI for Search / Ask, Sources, Transcripts, Activity, and Settings.
- Added a dependency-free Node.js local server for Windows preview indexing and APIs.
- Added local source registration, notes/code/text indexing, PDF metadata indexing, lexical search, extractive Ask answers with citations, transcript text import, and activity scanning.
- Added `Windows/tests/windows_smoke.mjs` and `.github/workflows/windows-preview.yml` so the Windows preview can be smoke-tested on a Windows GitHub Actions runner.

Current Windows limits:

- The preview is not a packaged native Windows tray app yet.
- CoreML e5, MLX generation, WhisperKit transcription, Carbon hotkeys, FSEvents, and SMAppService remain macOS-only implementation paths.
- PDF support indexes metadata only until a Windows PDF text extraction adapter is added.

### macOS Release Handling

- Added `INSTALL.md` with Gatekeeper and first-launch instructions for the free ad-hoc signed macOS build.
- Updated the DMG release script to include `INSTALL.md` in the staged release image when present.
- Kept macOS release notes explicit about the ad-hoc signed, non-notarized DMG while linking Windows users to the separate preview documentation.
