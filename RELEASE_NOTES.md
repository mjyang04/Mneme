# Release Notes

## Unreleased

### Platform Status

- macOS remains the packaged release platform for v0.1.0 through `Mneme-v0.1.0-macos-arm64.dmg`.
- Windows now has a desktop build path under `Windows/` with Electron, a tray/window shell, global shortcut, native folder picker, and Windows CI installer artifacts.

### Windows Desktop

- Added a Windows Desktop implementation under `Windows/`.
- Added a Mneme-style workbench UI for Search / Ask, Sources, Transcripts, Activity, and Settings.
- Added a dependency-free Node.js local backend for Windows Desktop indexing and APIs.
- Added local source registration, notes/code/text indexing, PDF metadata indexing, lexical search, extractive Ask answers with citations, transcript text import, and activity scanning.
- Added an Electron shell with native window, tray menu, `Ctrl+Space` global shortcut, native folder picker, and native file/folder opening.
- Added `package.json`, `package-lock.json`, and `scripts/build_windows_installer.ps1` for repeatable Windows desktop packaging.
- Added `Windows/tests/windows_smoke.mjs` and `.github/workflows/windows-desktop.yml` so the Windows desktop backend can be tested and installer artifacts can be built on a Windows GitHub Actions runner.

Current Windows limits:

- CoreML e5, MLX generation, WhisperKit transcription, Carbon hotkeys, FSEvents, and SMAppService remain macOS-only implementation paths.
- PDF support indexes metadata only until a Windows PDF text extraction adapter is added.

### macOS Release Handling

- Added `INSTALL.md` with Gatekeeper and first-launch instructions for the free ad-hoc signed macOS build.
- Updated the DMG release script to include `INSTALL.md` in the staged release image when present.
- Kept macOS release notes explicit about the ad-hoc signed, non-notarized DMG while linking Windows users to the separate desktop documentation.
