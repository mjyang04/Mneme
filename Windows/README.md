# Mneme Windows Preview

This directory contains the Windows development preview for Mneme.

The preview is intentionally local-first and dependency-light: it uses Node.js standard library APIs only, stores runtime data under the Windows user profile, and does not call cloud services.

The macOS app remains the packaged v0.1.0 release. The Windows preview exists to validate the same product surface on Windows before a native Windows tray/window shell is built.

## Current Status

This is a development preview, not the final Windows installer.

Implemented in this pass:

- Mneme-style workbench UI with Search / Ask, Sources, Transcripts, Activity, and Settings.
- Local folder source registration.
- Local indexing for notes, code, text files, transcript text, and PDF metadata.
- Local lexical search.
- Extractive Ask answers with numbered citations from local hits.
- Transcript text import and indexing.
- Activity scan for recent files and git commits.
- Smoke test that can run on a real Windows runner through GitHub Actions.

Not yet implemented for Windows:

- Native system tray packaging.
- Global OS hotkey registration outside the browser window.
- CoreML multilingual-e5 embeddings.
- MLX local generation.
- WhisperKit audio transcription.
- Full PDF text extraction.

These gaps exist because the current macOS implementation depends on Apple-only APIs and runtimes: SwiftUI menu bar scenes, AppKit panels, Carbon hotkeys, FSEvents, SMAppService, CoreML, MLX Swift, and WhisperKit.

## Run Locally

Install Node.js 22 or newer, then run:

```powershell
node .\Windows\mneme-windows.mjs
```

Open the printed local URL, usually:

```text
http://127.0.0.1:47732
```

By default on Windows, runtime data is stored at:

```text
%APPDATA%\Mneme
```

For development tests, override the data directory:

```powershell
$env:MNEME_WINDOWS_DATA_DIR = "$env:TEMP\MnemePreview"
node .\Windows\mneme-windows.mjs --data-dir "$env:MNEME_WINDOWS_DATA_DIR"
```

## Test

From the repository root:

```powershell
node --test .\Windows\tests\windows_smoke.mjs
```

The smoke test starts a local preview server, adds a fixture source folder, rebuilds the local index, runs search, runs Ask with citations, imports a transcript, and checks the workbench UI file.

## UI Parity Target

The Windows preview follows the current macOS information architecture:

| macOS surface | Windows preview surface |
| --- | --- |
| Menu bar + main window | Local workbench served on 127.0.0.1 |
| QuickSearch | Top command search with Ctrl+K focus |
| Settings source folders | Sources tab |
| Search / Ask segmented control | Search / Ask segmented control |
| Transcripts tab | Transcript text import tab |
| Activity tab | Recent file and git activity scan |

The release-grade Windows app should replace the local browser workbench with a native tray/window shell while keeping these screens and data contracts.
