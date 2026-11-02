# YR File Explorer

Flutter Android application with a native Java file engine. Open and run **this directory** as the Flutter project; there is no nested Flutter application or backend server.

- Application: **YR File Explorer**
- Package: **com.somesh.yrfileexplorer**
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

Local/removable-storage browsing, grid/list/detail views, sorting, hidden files, multi-selection, search, create, rename, copy, move, share, favorites, properties, SHA-256 checksums, Recycle Bin and restore, in-app ZIP/7z browsing, creation and extraction with optional passwords, password-encrypted individual files, image zoom with floating controls and thumbnails, UTF-8 text editing, native audio/video playback, offline paginated PDF reading with pinch zoom, Android APK installation, and app inventory/backup/uninstall.

Archive creation offers ZIP and 7z in the same dialog. Extraction uses a new destination directory and rejects unsafe archive paths. The 7z changes have passed source analysis; Android build and runtime verification are pending.

The workspace preserves local, category, tool and user-requested network tabs. App pages use the same horizontal slide transition; the active top tab shows its title and inactive tabs show icons. Folders reuse the last Device window; removable storage retains its storage name. Homepage shows eight category shortcuts in two rows of four (Recent has no count), then storage volumes, Tools and Network. The old sidebar, Local card and Bookmarks card are removed. Floating bottom navigation leaves underlying content visible and scrollables reserve clearance for their final item.

SD Card Analyst has proportional row fills, selection, copy/cut/delete and a narrow floating red/green capacity bar above navigation. Storage Analyzer is a workspace tab with summary statistics and icon tiles for large files, recently modified items, empty folders and duplicate detection; each shortcut opens a dedicated results tab with inspection and selection actions. Folder scans use a separate cancellable progress dialog, keeping the existing page underneath and committing the new folder only after a successful scan. The duplicate Space usage section is removed. Windows has a clipped Windows/Clipboard selector, screenshot previews, New and Close others; each card's Home icon chooses a startup tab. New opens a nested dialog while retaining Windows underneath.

## Network implementation

User-configured FTP (active/passive), explicit/implicit FTPS, SFTP with host-key verification, SMB share discovery/browsing and HTTP/HTTPS WebDAV provide listing, recursive download/upload, mkdir, rename, server-folder copy/move and deletion. Existing destinations are refused. Profiles support editing/removal, guest/anonymous access and optional Android-Keystore password storage; plaintext passwords are excluded from saved profiles and startup windows. LAN discovery is user-triggered, cancellable and bounded to the current local subnet (at most 254 addresses). Bluetooth supports Android pairing/permissions, discovery, system sharing and OBEX file browsing where the peer supports it. Net Manager shows connection details and opens Android Wi-Fi/hotspot controls.

HTTP/HTTPS addresses open web tabs with navigation, progress, authentication prompts, certificate verification and download handoff. Download Manager tracks Android-managed jobs, progress/completion, cancellation, retry, opening and history removal. Only the final HTTP, File, HTTPS and Samba choices in Windows → New show Path. All network choices are enabled. Android 17's local-network permission is requested at runtime; Android 12–16 do not receive that newer permission prompt. Cloud, Remote Manager, ads, analytics, recommendations and the floating gesture shortcut remain excluded.

Network runtime validation is **pending**: source analysis and Java compilation were completed, but this session's sandbox denied loopback socket connections and automatic approval review hit an account usage limit. Successful protocol transfers, TLS behavior and Android 12/17 emulator flows must still be verified before calling the network work complete. Bluetooth validation is limited to UI/permissions until a compatible physical peer is available, per the user's instruction.

## Scope and original-APK inspection

The current behavior reference is the supplied **ES File Explorer 3.2.3** running on Android 5.1. Captures of the original interactions are under `analysis/screenshots/es-3.2.3/`. The YR interface keeps the navigation placement with modern cards and a centered window switcher. Its Java file engine is independent; complete feature parity is still not established. Newer 4.2.x APK inspection artifacts are retained separately.

Original-APK audit reports and captures are local inspection artifacts and are excluded from the GitHub source package.

Android blocks other apps' private storage, most Android/data and Android/obb content, silent installation/uninstallation and other privileged operations. All-files permission does not bypass these restrictions.

## Checks

```powershell
.\run.ps1 -Task analyze
# Android lint, from this root:
.\android\gradlew.bat -p android :app:lintDebug
```

Validation uses Dart analysis, Android builds and manual emulator checks. No automated test suites are included.

## Dependencies and distribution

Direct native library versions were checked against Maven Central on 2026-10-31: Zip4j 2.11.6, Commons Net 3.13.0, JSch 2.28.8, SMBJ 0.15.0, SMBJ-RPC 0.12.13 and OkHttp 5.5.1. AGP is 9.5.0. Flutter has no third-party runtime Dart packages. SDK-pinned transitive Dart versions are retained for Flutter compatibility. The development-only package named `leak_tracker` detects memory leaks during Flutter tests; it is not analytics and is not shipped in the release app.

Release builds currently use the local **development signing key**. Configure your private release keystore before distributing through a store. Broad storage/package permissions are used for the file manager and App Manager and need the appropriate store declarations if you publish.

## Source map

| Location | Responsibility |
|---|---|
| `lib/main.dart` | Bootstrap and settings initialization |
| `lib/app/` | Application widget and theme construction |
| `lib/core/` | Native bridge, settings, models, styling and formatting |
| `lib/shared/` | Reusable dialogs and widgets |
| `lib/features/` | Feature pages, feature widgets and application state |
| `lib/core/utils/file_sort.dart` | Shared directory-first sorting for files and archives |
| `lib/features/analysis/domain/` | Analysis kinds and cached result projections |
| `lib/features/workspace/presentation/widgets/workspace_window.dart` | Workspace page dispatch, separated from session lifecycle |
| `android/app/src/main/java/com/somesh/yrfileexplorer/` | Native engines grouped into Java packages by responsibility |
| `assets/` | Runtime icons and visual assets |

File and analyst list ordering is cached until source data or sorting changes. Tab label measurements are cached until labels or text scale change. Screenshot previews notify the Windows panel separately from navigation state; capture requests are coalesced and images are disposed after encoding. Hidden tabs stop their tickers, while translated page bodies have repaint boundaries. These changes retain the existing layout, colors and navigation timing; runtime frame-rate measurements still require a device run.

The GitHub source package keeps application source, runtime assets, Flutter/Gradle configuration and wrapper files, dependency lockfiles, and maintained project documentation. Local SDK paths, build output, caches, APK inspection material and private signing files are excluded.
