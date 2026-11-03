# YR File Explorer

Release notes: [v1.0.0](docs/releases/1.0.0.md).

## Overview

YR File Explorer is an Android file manager built with Flutter and a native Java engine. It brings local storage, removable drives, storage analysis, archives, media viewers, and user-configured network connections into one tabbed workspace.

The interface uses cyan accents, light surfaces, a `#292929` dark theme, and floating action bars. The app contains no advertising, tracking, or analytics SDKs. Local file management works without a backend server; network connections run when requested by the user.

### License

Original project code and project-owned assets are **source-available** under the [PolyForm Noncommercial License 1.0.0](LICENSE). This is not an OSI-approved open-source license.

- You may build, use, modify, and share the software for purposes permitted by the license, including personal and noncommercial use.
- Commercial use, including selling compiled builds, commercial rebranding, or bundling the app into a commercial offering, requires separate permission from the copyright holders.
- Preserve the license terms or their URL and the required notices in [NOTICE](NOTICE) when redistributing covered source or binaries.
- Third-party components and assets retain their own licenses; this license covers only rights the project copyright holders can grant.

The restriction covers commercial use generally, not only resale. The full license text governs. `LICENSE` and `NOTICE` are also packaged as Flutter assets in app builds.

## Features

### Files and navigation

- Browse Device storage, named external storage, and supported document-provider locations.
- Create, rename, copy, move, share, hide, and delete files and folders.
- Search files, view properties, calculate checksums, and save favorite folders on the homepage.
- Use Grid, List, or Details views with selectable item sizes and sorting. Folders remain before files, including hidden items.
- Group items by Name, Size, or Type with lined, collapsible headings and independent ascending/descending ordering.
- Select multiple items, swipe to select or deselect, and drag selected files or folders in ghosted form after a one-second hold.
- Work with tabs, breadcrumbs, history, window previews, and the copy/cut clipboard.
- Open a resizable top/bottom split view with independent navigation and a shared action bar. Transfer items between panes. Page swiping is disabled while split view is open.
- Restore deleted items from the Recycle Bin, or empty it explicitly.

### Storage analysis

- Scan folders for recursive sizes, file/folder counts, category totals, and proportional storage usage.
- Inspect large files, recently modified files, empty folders, and SHA-256-verified duplicates in dedicated result tabs.
- Expand duplicate groups and select individual copies for deletion.
- Track scans in a cancellable progress dialog and copy analysis reports.
- Optionally calculate folder sizes during normal browsing. This is off by default to reduce scanning work.

Analysis includes hidden files. Unreadable paths and symbolic links are skipped; symbolic links are not followed. Document-provider results depend on the metadata and access supplied by the provider.

### Archives, viewers, and applications

- Browse, create, and extract ZIP and 7z archives, with optional passwords.
- Encrypt and decrypt individual files with passwords.
- View images with zoom, thumbnails, and aspect-ratio-preserving previews.
- Read PDFs offline with continuous scrolling, zoom, and page navigation.
- Edit text files with encoding, line-ending, and font-size controls.
- Play local music with artwork, a playlist, seeking, previous/next, shuffle, and repeat-all/repeat-one controls. Playing and Playlist pages share a swipe-linked top switcher.
- Recognize common Android audio formats, including MP3, AAC, M4A/M4B, FLAC, WAV, OGG/Opus, AMR, and MIDI. Actual decoding depends on the device and the file's codec.
- Play local videos in the built-in video viewer.
- Display APK artwork, launch Android's installation flow, and browse, back up, share, or uninstall installed apps through supported system flows.

### Network connections

- User-configured FTP, FTPS, SFTP, SMB/LAN, and WebDAV connections.
- Remote browsing, uploads/downloads, folder creation, rename, copy/move, and deletion where supported by the protocol and server.
- Optional saved connection profiles and Android-Keystore-protected passwords.
- User-triggered LAN discovery, HTTP/HTTPS web tabs, and Download Manager.
- Bluetooth discovery, pairing controls, sharing, and OBEX browsing when supported by the other device.

Server-specific interoperability and Bluetooth transfers require checks against compatible peers. Google Drive and other cloud-account integrations are not currently implemented. Remote Manager is excluded.

### Default settings

| Setting | Default |
| --- | --- |
| Theme | Light |
| View | Medium Icon grid |
| Group by | None |
| Show hidden files | Off |
| Show folder sizes while browsing | Off |
| Music background playback | Off; leaving the player stops playback |
| Recycle Bin | On |

Explicitly saved user preferences are retained across updates.

## Setup Guide

### 1. Install the development tools

- Install Flutter compatible with the Dart SDK requirement in `pubspec.yaml` (`^3.13.7`). The versions used for development are listed above.
- Install Android Studio, its Flutter/Dart plugins, Android SDK Platform 37, Android SDK Platform-Tools, and the Android SDK Command-line Tools.
- Use Android Studio's bundled JDK for Gradle. Java source and target compatibility are set to 17.
- Add Flutter's `bin` directory to `PATH`, or set `FLUTTER_ROOT` when using the provided helper script.

From the repository root, check the toolchain and resolve dependencies:

```powershell
flutter doctor -v
flutter doctor --android-licenses
flutter pub get
```

Flutter and Gradle must be able to download dependencies on the first setup. Use the included Gradle wrapper rather than installing a separate Gradle version.

### 2. Open and run the project

Open **this repository root** in Android Studio: the directory containing `pubspec.yaml` and `lib/main.dart`. Select the Flutter run configuration for `lib/main.dart`. The Android module is at `android/app/`.

Connect an Android 12+ device, enable USB debugging, and approve the computer's debugging connection on the device. Then run:

```powershell
flutter devices
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with the identifier printed by `flutter devices`.

For a native Android/Gradle import, open `android/`. Machine-specific SDK paths belong in `android/local.properties`; Flutter normally creates this file. If needed, configure `sdk.dir` and `flutter.sdk` there with the paths on your computer. Do not commit that file.

### 3. Grant access on the device

On first launch, use **Grant storage access** and enable **Allow access to manage all files**, then return to the app. The file browser remains gated until access is granted.

Android manages this under **Special app access**, separately from ordinary app permissions. You can reopen it through **Settings → Storage access** in the app. APK installation and Bluetooth permissions are requested separately when needed.

All-files access does not bypass Android's restrictions on other apps' private data or protected `Android/data` and `Android/obb` content.

### 4. Use the optional Windows shortcuts

`run.ps1` finds Flutter through `PATH`, `FLUTTER_ROOT`, or the existing `D:\develop\flutter` installation if present. It runs `flutter pub get` before the selected task.

```powershell
.\run.ps1 -Device DEVICE_ID
.\run.ps1 -Task debug
.\run.ps1 -Task release
.\run.ps1 -Task analyze
.\run.ps1 -Task doctor
```

`run.cmd` invokes the same PowerShell helper if launching a `.ps1` file directly is restricted. These scripts are development tools and are not packaged in the Android app.

### 5. Build and install an APK

```powershell
# Debug APK
flutter build apk --debug

# Release APKs, one per processor architecture
flutter build apk --release --split-per-abi

# ARM64 release for devices such as the S23 Ultra
flutter build apk --release --target-platform android-arm64
adb -s DEVICE_ID install -r build/app/outputs/flutter-apk/app-release.apk
```

Build output is under `build/app/outputs/flutter-apk/`. `install -r` preserves existing app data when the package and signing certificate match.

Release builds currently use the development signing key configured in `android/app/build.gradle.kts`. Configure production signing before distributing a store release.

### 6. Check code quality

```powershell
flutter analyze
.\android\gradlew.bat -p android :app:lintDebug
```

Use source analysis, Android builds, and manual device checks for validation. Do not add or run automated test suites unless requested. Follow `AGENTS.md` for the project's UI workflow and emulator-testing restrictions.

### Project structure

| Directory | Responsibility |
| --- | --- |
| `lib/app/` | App entry widget and themes |
| `lib/core/` | Settings, models, native bridge, and common utilities |
| `lib/shared/` | Reusable dialogs and widgets |
| `lib/features/` | Feature pages, state, and feature-specific widgets |
| `android/app/src/main/java/com/somesh/yrfileexplorer/` | Native Java engines organized by responsibility |
| `android/app/src/main/res/` | Android resources and native viewer icons |
| `assets/` | Runtime branding and visual assets |

Commit source, runtime assets, build configuration, Gradle wrapper files, dependency lockfiles, and maintained documentation. Build output, SDK paths, caches, inspection artifacts, and private signing files are excluded by `.gitignore`.
