# Feature and visual review status

Updated 2026-11-01. This is not a complete acceptance sign-off.

## Current UI phase

Latest revision: rounded segmented tabs (active name / inactive icons), Home label for local browsing, sliding selection and far-right tab insertion. Tools, Library and Network live in aligned collapsible Homepage cards; the sidebar is simplified. See LOCAL_UI_REVIEW.md and segmented-* captures for the reviewed states.

Network work is deferred until the user explicitly resumes it. The agreed order is UI, local functionality, then comparison against the original application. Remote Manager remains excluded.

Alignment pass: shared 24 dp tab strip, 44 dp header and 56 dp footer across Home, local browsing and workspace tools; matching header icon sizes; consistent folder grid spacing; fixed two-line app-label slots; clipped inactive tab labels; compact storage-row spacing; white untinted dialogs; left sidebar constrained to 80% of the screen (maximum 360 dp). Analyst column headings now use the same horizontal gutters as row values.

The Android debug build passed. Home, left sidebar, loaded app grid, folder breadcrumbs, storage History and Windows panel were manually captured on the review emulator under `analysis/screenshots/yr-review/aligned-*.png`. This covers those portrait states, not every screen, font scale, theme or orientation. No test cases were added or run.

Detailed current local workflow evidence and acceptance limits: [LOCAL_UI_REVIEW.md](LOCAL_UI_REVIEW.md). Audio/video checks were deprioritized at the user’s request; network work remains deferred.

The current reference is **ES File Explorer 3.2.3**, operated on the Android 5.1 emulator. The original APK's executable code is not reused in YR. Earlier 4.2.x static/runtime inspection records are separate historical artifacts.

**Build passed** means the APK compiled. **Manually checked** means the named interaction was exercised on an emulator. Neither establishes all feature parity or all visual states. No test cases were added or run in this work.

| Area | Implementation | Functional verification | Visual verification / remaining work |
|---|---|---|---|
| Homepage | Categories, detected storage, collapsible Tools/Bookmarks | Homepage displayed; category navigation exercised | Original homepage captured; modern appearance still under review |
| Navigation menu | Left Scaffold drawer shared by Homepage and file views | Earlier file-view handler incorrectly opened a floating bottom sheet; replaced with openDrawer | Latest sidebar correction builds; broad drawer-state review pending |
| Storage History | Storage title opens attached volumes and recent folders; Clear clears recent history | Original title and slash interactions exercised; YR title opens detected storage | Prior rounded/tinted design rejected by user; compact white revision built, installed, and visually inspected; recent-folder state captured in yr-history-compact.png |
| Breadcrumb and storage boundaries | Fixed last three segments shared by local files, archives and both analysis views; device-root links removed | Deep local/archive paths and ancestor navigation manually checked; analysis retains selected folder | Storage title opens attached volumes/history; parent navigation stops at the storage boundary |
| Local/category windows | Independent local/category browser state, top icon switching, new/close windows | Category tab flows inspected in reference; YR switching and basic panel exercised | No full-page fade for workspace switching; all category/header states not reviewed |
| Windows panel | Centered Windows/Clipboard tabs, preview cards, active outline, count, New/Default/Close others | Panel and empty Clipboard opened on Android | Centered panel captured; populated Clipboard and all tab-management actions still need full review |
| Clipboard | Copy/cut state, clear, paste; panel entry available in paste bar | Selection/copy exercised; source-folder paste correctly rejected | Populated panel and destination-paste flow not fully verified |
| Default windows | Save current local windows, remove defaults, restore on launch | Code present; complete save/restart review pending | Settings dialog review pending |
| Views and sorting | Icon/list/detail sizes and sorting | Original View dialog operated; YR full combination review pending | Every size/theme/orientation combination pending |
| Search and refresh | Recursive search, refresh, hidden-file control | Code present; full search/cancellation/failure review pending | Search, empty/error/loading states pending |
| Local file operations | Create, rename, copy/move, selection, share, properties, hashes, favorites | Code present; comprehensive manual file-operation review pending | Dialog/menu parity and error states pending |
| Recycle Bin | App trash, restore, permanent deletion | Code present; full manual lifecycle review pending | Pending |
| Folder analysis | Java traversal, sizes/counts, categories, largest/recent/empty/duplicate files, cancellation | Earlier development checks exist; no comprehensive current acceptance review | Modern analysis page and all drill-down states pending |
| Archives | ZIP/AES ZIP creation and extraction | Code present; full manual archive review pending | RAR/7z/TAR engines and archive browsing parity not implemented |
| Encryption | YR AES-GCM format; decryption chooses a separate output filename | Isolated encrypt/decrypt round trip passed; original/decrypted SHA-256 values matched | Not compatible with ES encrypted-file format |
| Image/text/media | Image zoom, UTF-8 editor, native audio/video | Code present; broad manual review pending | ES playlist/player/editor feature parity incomplete |
| App manager | App list, backup, Android install/uninstall integration | Code present; device-specific workflow review pending | Original app-manager states and detailed visual parity pending |
| FTP/SFTP/FTPS | Connection forms, saved profiles without passwords, list/get/put/mkdir/delete; SFTP key verification | Server interoperability not verified; no server credentials supplied | Connection, errors, remote tabs and transfer states need full review |
| Other network code | Native SMB/WebDAV/transfer helpers remain in source | Not part of current exposed FTP/SFTP UI sign-off | Cloud accounts, recommendations, ads and tracking excluded |
| Storage providers | Detected mounted volumes; native SAF helpers | Real removable SD/USB/provider lifecycle not verified | Device-dependent states pending |
| Gestures | Standard selection/zoom/refresh retained | Broad gesture review pending | Only the middle floating gesture shortcut intentionally excluded |

Outstanding parity gaps include ES encryption compatibility, additional archive engines, full media playlists, and other local ES tools. Modern Android restrictions also affect app-private storage and system operations. The application must not be described as a fully verified ES clone.

Reference captures: `analysis/screenshots/es-3.2.3/`. Current YR captures: `analysis/screenshots/yr-*.png`. Captures document specific states, not complete visual acceptance.
