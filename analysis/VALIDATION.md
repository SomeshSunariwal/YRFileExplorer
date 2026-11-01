# Validation record — 2026-10-31

Application: YR File Explorer 1.0.0, com.explorer.fileexplorer. Minimum API 31, compile/target API 37. The device used for runtime checks was the installed Pixel_9_Pro emulator on **API 37**. An Android 12 physical device was not available; minimum-version compatibility was checked statically, not exercised on API 31 hardware.

| Check | Result |
|---|---|
| Flutter static analysis | Pass, no issues |
| Flutter unit/widget tests | Pass, 5 tests: formatting, home, analysis counts/filtering, browser counts, cancellation |
| Java FolderAnalyzer fixtures | Pass: total 22 bytes, 4 files, 3 folders; child 14 bytes/2 files/1 descendant folder; hidden files, categories, duplicates, empty folders, progress, cancellation |
| Symlink fixture | Skipped: this Windows host does not permit creating symlinks |
| Java file-engine tests | Pass: copy integrity/conflicts, self-copy rejection, safe names, AES ZIP, wrong passwords, traversal rejection, AES-GCM round trip, deletion |
| Java transfer-server tests | Pass: authorized listing, invalid token rejection, traversal rejection, upload and overwrite protection |
| Android integration test | Pass: actual Flutter/Java bridge, recursive totals, copying/renaming, encrypted ZIP, vault encryption, trash/restore, Wi-Fi GET/PUT, installed-app listing |
| Android lint | Pass: 0 errors, 14 warnings. Store-policy, template-resource and library warnings remain. PropertyEscape is ignored only for Flutter-generated local.properties Windows paths; QUERY_ALL_PACKAGES has a local manifest suppression documenting App Manager usage |
| Debug APK | Built and launched |
| Release APKs | ARM64, ARMv7 and x86-64 built; release signature verified |
| Optimized release UI smoke | Pass: browsed real Downloads fixture, displayed 22 B / 4 files / 3 folders and per-folder counts |
| Debug static tracker signatures | No recognized signatures found; see yr-debug-audit/ |
| Release static tracker signatures | No recognized signatures found; see yr-release-audit/ |

The app contains no analytics, advertising, attribution, crash-reporting or advertising-ID dependencies. The static signature audit is corroborating evidence, not a comprehensive runtime traffic certification. Minification can obscure identifiers, which is why the unminified debug APK was inspected as well.

Screenshots in `screenshots/` are captures of the actual running app, not mockups. `emulator-analysis-labels.txt` records the corresponding accessible UI values. The test fixture exists only under build/ and the disposable emulator's Downloads, not as production application data.

The release artifacts use the local Android development signing certificate. They are suitable for local testing; private distribution signing remains to be configured by the project owner. `release-artifacts.json` records filenames, sizes and SHA-256 hashes.

Remote-server interoperability, provider-specific cloud behavior, Bluetooth/DLNA and other unimplemented parity items are not certified by these checks. See FEATURES.md for the explicit scope.
