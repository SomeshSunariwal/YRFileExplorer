# YR File Explorer

Flutter Android application with a native Java file engine. Open and run **this directory** as the Flutter project; there is no nested Flutter application or backend server.

- Application: **YR File Explorer**
- Package: **com.explorer.fileexplorer**
- Minimum: **Android 12 / API 31**
- Compile and target: **API 37**
- Flutter SDK used: **3.47.8 stable**, Dart **3.13.7**
- No analytics, advertising, attribution, crash-reporting or device-identifier SDKs.

## Run from this root

Connect an Android 12+ phone with USB debugging enabled, or start an Android emulator:

```powershell
.\run.ps1
# Or select an emulator / device:
.\run.ps1 -Device emulator-5554
```

`run.cmd` provides the same entry point if PowerShell script execution is restricted. The script finds Flutter on PATH, from FLUTTER_ROOT, or from the existing D:\develop\flutter installation on this machine.

Standard Flutter commands also work here:

```powershell
flutter pub get
flutter run
flutter build apk --debug
flutter build apk --release --split-per-abi
```

Android Studio's **Open** should select this root, which contains `pubspec.yaml`. Java 17+ and Android SDK 37 are required; Android Studio's bundled JBR is suitable. Flutter generates machine-specific `android/local.properties`. Gradle's wrapper is included.

In Android Studio, select the **main.dart** Flutter run configuration. Link the canonical Gradle project at `android/`, with its application module at `android/app/`. The workspace-root Gradle files now include that Android build and forward `assembleDebug` and `assembleRelease`; they do not declare a nonexistent root `app/` module. Both root and Android project imports can therefore configure without the invalid-directory error. After updating these settings, use **Sync Project with Gradle Files** (or reopen the project) to reload the IDE model. The actual launcher is declared in `android/app/src/main/AndroidManifest.xml`.

On first launch choose **Grant storage access**, enable Android's **Allow access to manage all files**, and return to the app. APK installation is granted separately through Settings when needed.

## Folder analysis

The priority feature uses actual Java filesystem traversal, with no fabricated or sample data in the app:

- Total logical size in bytes, formatted with binary units (1 KB = 1,024 bytes).
- Recursive file and folder counts; the selected folder itself is excluded.
- Hidden files are included in analysis even when hidden in the browser.
- Every immediate child folder shows its recursive size and nested file/folder counts.
- Storage-category ring, proportional usage bars, sorting, drill-down, selection and Recycle Bin actions.
- Streaming progress and cancellation, largest files, empty folders, recent files, optional SHA-256 duplicate verification, clipboard report export.
- Unreadable paths and symbolic links are explicitly counted as skipped; symlinks are not followed.
- Document-provider trees can also be analyzed. Provider sizes can be missing; unknown sizes are reported rather than presented as complete. Provider analysis does not perform content hashing or provider deletion.

Browser folder sizes are calculated in the background and can be disabled in Settings for very large storage trees.

## Other implemented features

Local/removable-storage browsing, grid/list/detail views, sorting, hidden files, multi-selection, search, create, rename, copy, move, share, favorites, properties, SHA-256 checksums, Recycle Bin and restore, AES-encrypted ZIP creation/extraction, password-encrypted individual files, image zoom, UTF-8 text editing, native audio/video playback, Android APK installation, and app inventory/backup/uninstall.

The workspace preserves open local/category tabs and switches them through a segmented top strip with horizontal content slides and fixed headers. The active tab shows its name, inactive tabs show icons, and new tabs slide into the far-right end. Local, Tools, Bookmarks and Network are Homepage cards. The sidebar has been removed; Homepage settings are available through the bottom Settings action; the Homepage header has no side icons. Images, Music, Movies, Documents, Compressed and APP share one equal-width category row above storage. Windows opens a centered floating panel with Windows/Clipboard tabs, preview cards, open-tab count, New, Default, and Close others. Each preview card has a Home action to choose its default startup tab; the selected local tab reopens on launch. Windows → New opens a nested type dropdown while retaining the Windows panel underneath. Only HTTP, File (Local), HTTPS and Samba show Path. Network choices in this dialog are UI-only with Open disabled until network work resumes. Tapping Homepage or a storage title opens History with detected storage volumes and recent folders; folder headers show the last three path segments. The full-width Homepage location contracts as local Back/Close controls enter from the sides, and expands on return. Ancestor clicks stay within the selected internal storage or SD card; device-root navigation is not offered. New Window starts at the current folder.

FTP/SFTP/FTPS connections are explicitly available. Saved profiles exclude plaintext passwords. The optional Remember password setting stores encrypted credentials using Android Keystore; SFTP requires fingerprint verification. Network permission is enabled for these user-configured connections. Ads, tracking, cloud accounts, recommendations, and the floating gesture shortcut are excluded from the UI.

## Scope and original-APK inspection

The current behavior reference is the supplied **ES File Explorer 3.2.3** running on Android 5.1. Captures of the original interactions are under `analysis/screenshots/es-3.2.3/`. The YR interface keeps the navigation placement with modern cards and a centered window switcher. Its Java file engine is independent; complete feature parity is still not established. Newer 4.2.x APK inspection artifacts are retained separately.

See [FEATURES.md](analysis/FEATURES.md) for the implemented scope and remaining differences, and [TRACKERS.md](analysis/TRACKERS.md) for components found in the original APK.

Android blocks other apps' private storage, most Android/data and Android/obb content, silent installation/uninstallation and other privileged operations. All-files permission does not bypass these restrictions.

## Checks

```powershell
.\run.ps1 -Task analyze
# Android lint, from this root:
.\android\gradlew.bat -p android :app:lintDebug
```

Validation uses Dart analysis, Android builds and manual emulator checks. No automated test suites are included.

`tools/emulator-smoke.py` is an optional UI smoke test **for a disposable emulator**. It installs no third-party APK, creates a 22-byte fixture under Downloads, navigates YR, and records screenshots. Do not run it against a personal device without reviewing it first.

## Dependencies and distribution

Direct native library versions were checked against Maven Central on 2026-10-31: Zip4j 2.11.6, Commons Net 3.13.0, JSch 2.28.8, SMBJ 0.15.0 and OkHttp 5.5.1. AGP is 9.5.0. Flutter has no third-party runtime Dart packages. SDK-pinned transitive Dart versions are retained for Flutter compatibility. The development-only package named `leak_tracker` detects memory leaks during Flutter tests; it is not analytics and is not shipped in the release app.

Release builds currently use the local **development signing key**. Configure your private release keystore before distributing through a store. Broad storage/package permissions are used for the file manager and App Manager and need the appropriate store declarations if you publish.

## Source map

| Location | Responsibility |
|---|---|
| `lib/main.dart` | Bootstrap and settings initialization |
| `lib/app/` | Application widget and theme construction |
| `lib/core/` | Native bridge, settings, models, styling and formatting |
| `lib/shared/` | Reusable dialogs and widgets |
| `lib/features/` | Feature pages, feature widgets and application state |
| `android/app/src/main/java/com/explorer/fileexplorer/` | Native engines grouped into Java packages by responsibility |
| `assets/` | Runtime icons and visual assets |
| `tools/` | Development and inspection utilities |
| `analysis/` | Original-APK evidence, review reports and screenshots |

See [Architecture](docs/ARCHITECTURE.md) for the detailed layout and placement rules.
