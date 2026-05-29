# Mneme Windows Desktop

This directory contains the Windows Desktop implementation for Mneme.

The app is intentionally local-first. The desktop shell uses Electron for native Windows window/tray/global-shortcut behavior, while the backend uses Node.js standard library APIs only, stores runtime data under the Windows user profile, and does not call cloud services.

The macOS app remains the packaged v0.1.0 release. The Windows Desktop build now provides the same top-level product surface through a native Windows shell.

## Current Status

This is the first landed Windows desktop path. It can be run locally with Electron during development and packaged on a Windows host or GitHub Actions runner.

Implemented in this pass:

- Mneme-style workbench UI with Search / Ask, Sources, Transcripts, Activity, and Settings.
- Native desktop window, tray entry, and `Ctrl+Space` global shortcut.
- Native folder picker for adding sources.
- Native open/show-in-folder actions for local result paths.
- Local folder source registration.
- Local indexing for notes, code, text files, transcript text, and PDF metadata.
- Local lexical search.
- Extractive Ask answers with numbered citations from local hits.
- Transcript text import and indexing.
- Activity scan for recent files and git commits.
- NSIS and portable `.exe` artifact path through `electron-builder`.
- Smoke and packaging jobs that run on a real Windows runner through GitHub Actions.

Not yet implemented for Windows:

- CoreML multilingual-e5 embeddings.
- MLX local generation.
- WhisperKit audio transcription.
- Full PDF text extraction.

These gaps exist because the current macOS implementation depends on Apple-only APIs and runtimes: SwiftUI menu bar scenes, AppKit panels, Carbon hotkeys, FSEvents, SMAppService, CoreML, MLX Swift, and WhisperKit.

## Run The Desktop App Locally

Install Node.js 22 or newer, then run:

```powershell
npm ci
npm run windows:dev
```

The Electron app opens a native Mneme window and keeps a tray icon active. `Ctrl+Space` toggles the window.

## Package A Windows Build

On Windows:

```powershell
npm ci
npm run windows:dist
```

Artifacts are written to:

```text
dist\windows\
```

The GitHub Actions workflow `.github/workflows/windows-desktop.yml` runs the same packaging path on `windows-latest` and uploads `.exe` artifacts.

By default on Windows, runtime data is stored at:

```text
%APPDATA%\Mneme
```

For development tests, override the data directory:

```powershell
$env:MNEME_WINDOWS_DATA_DIR = "$env:TEMP\MnemeDesktop"
node .\Windows\mneme-windows.mjs --data-dir "$env:MNEME_WINDOWS_DATA_DIR"
```

## Test

From the repository root:

```powershell
npm run windows:check
npm run windows:test
```

The smoke test starts a local backend server, adds a fixture source folder, rebuilds the local index, runs search, runs Ask with citations, imports a transcript, and checks the workbench UI files.

## UI Parity

The Windows Desktop app follows the current macOS information architecture:

| macOS surface | Windows Desktop surface |
| --- | --- |
| Menu bar + main window | Native Electron window + tray |
| QuickSearch | `Ctrl+Space` global shortcut + top command search |
| Settings source folders | Sources tab + native folder picker |
| Search / Ask segmented control | Search / Ask segmented control |
| Transcripts tab | Transcript text import tab |
| Activity tab | Recent file and git activity scan |

The remaining Windows runtime work is to replace metadata-only PDF support and lexical/extractive retrieval with native Windows text extraction, embedding, generation, and transcription runtimes.
