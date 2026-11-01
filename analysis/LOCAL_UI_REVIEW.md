# Local UI and workflow review — 2026-11-01

Reference: ES File Explorer 3.2.3 on Android 5.1 (emulator-5580). YR: debug build on Android 37 (emulator-5582). Network, cloud and Remote Manager excluded from this pass. Checks were performed through the applications with isolated review files; no unit or integration test cases were added or run.

## Confirmed fixes

- Back closes the navigation drawer without changing the active local window.
- Breadcrumbs now show the last three complete locations consistently after selection/rename.
- Local files, Apps and ZIP archives share the nine-mode View chooser; its contents scroll on short screens.
- More, App Manager More and Home Toolbox use compact anchored menus.
- Apps search clears its query when closed; standalone selection/search and nested archive Back states are intercepted correctly.
- Returning to a local file, Apps, archive or Recycle Bin window refreshes its contents.
- Clipboard Choose destination opens local storage when the current page cannot paste. Deleted clipboard sources are removed from the clipboard.
- Unavailable Recycle Bin actions are visibly disabled. Input dialogs scroll with the keyboard.
- Image viewer has gallery counters/thumbnails, local rotation, slideshow, Properties, Share, Open with, Delete and Android wallpaper selection. It reloads the browser after returning.
- Popup/menu colors and small-grid filename sizing were normalized. Prior-screen snackbars are hidden when opening a file viewer.
- Repeated native video error dialogs are guarded.
- Removed an unused duplicate system-app setting; the App Manager System Apps filter is functional.

## Exercised workflows

| Workflow | Result / evidence |
|---|---|
| New folder, copy/paste, rename | Passed with Notes.txt and Destination under Download/YR_UI_Review |
| Cut/paste | Passed: Renamed.txt moved from Destination to Nested; audit-cut-fixed |
| Delete and restore | Passed: review file entered Recycle Bin and returned to its original path; audit-trash-restore |
| Search | Shallow search showed no match; deeper search found Nested/Deep.txt; Local tab retained; audit-search-shallow/deep |
| More and Properties | Opened anchored actions and correct real file path/size; audit-more/properties |
| ZIP browsing, nested text preview, extraction | Passed with Sample.zip; audit-archive-inner/extract |
| Archive View | Large Detail selection changed actual archive rows; audit-archive-view |
| All nine local file view modes | Rendered/captured under audit-view-large/medium/small-icon/list/detail |
| Image viewer | Opened gallery 2/2, thumbnails and rotation/menu; audit-image-gallery/rotated/actions |
| Text editor | Read-to-edit, save; pulled file contained the edited text and exactly two CRLF separators, no doubled CR; audit-editor-saved |
| App manager | User/System filtering, search, app backup and Backed-up Apps listing; audit-app-backup/backups/system/search |
| Landscape View dialog | Bounded and scrollable; audit-landscape-view. Emulator disconnected during the following keyboard check and was restarted; that check is not a pass. |
| Runtime logs | No Flutter exception or native crash found in the captured completed-workflow log; audit-runtime.txt |

## Acceptance limits

This is not an assertion of complete ES parity. Additional archive engines (RAR/7z/TAR), ES encryption compatibility, split-APK restore, and complete parity for every ES local tool are not implemented. Real removable SD/USB lifecycles, every file/media codec, all accessibility sizes and all Android versions are not certified by these emulator checks. The remaining review results are appended below as completed.

## Latest path-header requirement

- Local files, archives, SD Card Analyst and detailed analysis share a fixed last-three-segment breadcrumb. Fewer than three available segments are shown without artificial placeholders.
- There is no horizontal breadcrumb clipping/scrolling. Each visible ancestor retains its full destination, with labels ellipsized within equal-width cells when necessary.
- Device (`/`) was removed from the drawer and storage history. Parent actions, new-window entry and local navigation reject paths above internal storage or SD-card boundaries.
- Opening analysis from a local folder keeps that folder.
- Captures: header-last-three, header-ancestor, header-locations, header-analyst-preserved, header-archive-three.
- Windows New, Close Others, saving defaults and restart restoration passed; audit-window-new-final/default-windows/default-restored.
- Archive creation passed with Reviewed.zip; audit-compress.
- Playback review was stopped at the user's request; no further media checks are part of this UI priority pass.

## Final focused checks

- New Window defaults to the exact current folder. Entering `/` keeps the dialog open with “Choose a folder in internal storage or SD card.” Cancelling returns to the unchanged folder; header-new-current-folder/root-blocked-final/current-unchanged.
- YR encryption/decryption passed with the isolated 54-byte review text file. Decryption asks for a new filename, preserving the original. Both files had SHA-256 `4cab6874279722deec563e5a7173a085ea0e9c44ae6dab02dc68e3198805689f`. This is the YR format, not ES encryption compatibility.
- The final captured runtime log had no RenderFlex overflow, Flutter exception or native fatal exception matches; audit-final-runtime.txt.
- A removable physical SD/USB device was not available for hardware lifecycle verification; storage boundaries use each detected volume's path.

Final debug APK built successfully after the storage-navigation changes. No test suite was run. Full ES parity remains incomplete; the verified workflows above are the scope of this review.

## Homepage and segmented-tab revision

The user's latest tab reference supersedes the earlier cyan strip and insertion-after-active behavior. The top strip is now a rounded segmented control: active name only, inactive icons only, with a sliding selection and right-side entrance for new tabs. Local browsing is labeled Home. Newly created windows append at the far right; existing tabs retain their order and folder state. The strip scrolls horizontally to reveal the active tab when necessary.

Tools, Library and Network were removed from the sidebar and moved into Homepage cards. Tools, Bookmarks, Library and Network share three-column grids, 64 dp rows, icon slots and padding. Expansion and grid scroll state have distinct storage keys; the expansion collision found during review was fixed. Horizontal safe areas are shared by local pages, text editing and detailed analysis so landscape content lines up with the header/footer. The category row adapts to larger text.

Manually reviewed light/dark Homepage, both selected-tab states, all four expanded/collapsed cards, simplified sidebar, moved Library navigation, new rightmost tabs, ten-tab overflow/selection, and landscape alignment. Screenshots use the segmented-* prefix in analysis/screenshots/yr-review. Network card expansion was checked visually; no network connection or playback checks were performed in this revision. No unit/integration test cases were added or run. Debug APK built successfully.


## Source organization and latest Homepage revision

Reorganized Dart into app/core/shared/features (43 modules), split feature pages and workspace dialogs/widgets, and grouped Java engines into responsibility packages. Updated Java imports and Android manifest registrations while retaining the launcher, channel names and sharing authority. Architecture and placement rules are documented in docs/ARCHITECTURE.md.

The sidebar and Library card are removed. Local is on Homepage immediately before Tools, the header gear opens Settings, Compressed follows Documents in the category row, and APP is in Applications. Breadcrumb controls retain divider lines and a rounded current location. Dark chrome uses #292929.

Validation: Dart analysis reports no issues; root assembleDebug succeeds. The installed APK cold-launches on emulator-5582. Manually checked local storage listing, segmented tabs, Homepage, Settings, dark theme, App Manager inventory and the Compressed category listing. Fresh runtime logs have no matches for Flutter errors, native fatal exceptions, missing classes or RenderFlex overflow. Evidence: organized-*.png and refactor-runtime.txt. No automated test cases, network connections or media playback checks were run. These checks establish the scope reviewed, not complete ES feature parity.


## Floating actions, icon placement and stable chrome

The shared bottom actions now use a fully rounded floating surface with outer spacing and theme-adjusted shadows across Homepage, file browsing and workspace tools. APP is the sixth matching category icon tile, directly beneath Images and above storage, with the same icon size, label and count styling. The separate Applications card/list row is removed. Category cells have consistent inset spacing; storage icons are 44 dp.

Breadcrumbs now share one rounded container around all visible locations; Homepage has no dropdown chevron. Workspace content slides horizontally according to tab order with live outgoing/incoming pages, while headers and actions stay fixed. File browser breadcrumbs were moved from the body into the app bar so they do not slide with the file list. Tab state remains mounted; inactive content excludes pointer and accessibility interaction.

App bar scrolledUnderElevation is zero and surface tint is transparent. Expanded Local and Tools to make Homepage scrollable, then scrolled it: status, top-tab background and header samples remain RGBA (255,255,255,255) before/after scrolling in light theme. Captures: scrolling-header-before/after, final-icon-home, final-capsule and fixed-slide-* under analysis/screenshots/yr-review. Light/dark floating surfaces reviewed. Dart analysis has no issues; Android debug build and install pass; captured runtime log has no fatal/Flutter/overflow/duplicate-key matches. No automated test cases, network connections or media playback checks were run.


## Single-row categories and transparent footer surroundings

Latest user direction supersedes the earlier second-row APP placement: all six categories now occupy one equal-width row, with 36 dp icon surfaces, consistent labels/counts and vertical breathing room. Homepage section headings use 13 sp semibold type and consistent insets; shortcut rows are 56 dp. Homepage and local browser extend their content behind the floating footer, removing the reserved rectangular footer band. Bottom padding inside their scrollables lets the last item clear the pill. Toolbar surroundings remain transparent, with a softer shadow.

Dart analysis reports no issues and assembleDebug succeeds. Manually checked expanded Homepage sections scrolling to the last card, and the browser's last file rows clearing the toolbar. Final single-row capture: six-icons-final.png. No test cases were added or run.


## Header Settings cleanup and window close alignment

Homepage has no left logo or right gear/separator slots. Its bottom Settings action replaces Toolbox and opens Settings directly. Window previews now have a dedicated control row, consistent inner padding and grid gaps, rounded card borders, and fully circular 44 dp close buttons inside the card. Locked tabs retain disabled close behavior. Preview images and labels no longer sit underneath the close button.

Dart analysis has no issues; debug APK builds and installs. Manually opened Settings through the new bottom action, returned to the clean Homepage header, opened a three-window panel, and closed a card through its circular control: the panel updated to two windows. Captures: clean-home-header, settings-bottom, modern-windows and modern-windows-closed. No automated test cases were added or run.


## Search close control

The search cross previously only cleared the text controller, leaving search mode open (and doing nothing visible when empty). It now closes search, unfocuses the keyboard, clears the query/deep-search state and reloads the current folder when results were active. Back uses the same cancellation path. Folder path and tab are preserved.

Dart analysis and debug build pass. On emulator-5582 manually closed an empty search at sdcard, submitted Readme within Download, reopened search, and closed it to restore the complete Download contents and breadcrumb. Captures: search-empty-closed, search-download-results and search-results-closed. No test cases were added or run.


## New window flow, header morph, defaults and Settings redesign

Windows → New now retains its parent Windows dialog and opens one rounded modal with a scrollable Type dropdown. Device, Sdcard, categories, APP, Download, tools and the requested path-based types are present; Cloud and Remote Manager remain excluded. Only HTTP, File (Local), HTTPS and Samba reveal Path, with per-type draft preservation. Local entries create new tabs rather than reusing an existing one; File starts at the current folder and remains bounded to storage volumes. The user's explicit UI-only network choice is enforced: network types are selectable but Open is disabled, with no network dispatch in this dialog. The first attempted Samba callback was rejected by automatic review and removed before any implementation was executed.

Homepage now has a full-width location pill. A shared navigation header contracts the location and brings Back/Close inward from the left/right while content slides; returning reverses the motion. Offstage ticker state is reset to the shared source geometry so repeat switches animate. Preview capture is scheduled after transition settlement, and stale captures from a tab that is no longer active are discarded.

Window cards have equal 12 dp content padding, transparent button backgrounds, red close icons and a blue filled Home icon for the default. The bottom sixth is a theme-toned vertical gradient from opacity 100% at the bottom to 0% at the top; centered floating text sits on that band. Previews fill their area with a crop focused on page content beneath the header. The per-card Home action persists a single startup choice and updates the panel without closing it. Duplicate local tabs do not all become marked as default.

Settings now groups Appearance, Files & storage, Permissions, and Privacy & about into rounded cards with uniform icon tiles, inset dividers, clearer labels, concise subtitles and expandable explanatory text. Existing switch, permission and licenses callbacks are retained. Light/dark themes were manually reviewed.

Validation: Dart analysis has no issues; debug build and installation pass. Manually verified File Path visibility/local creation, Cancel and Open retaining the parent dialog (count 2→3), HTTP Path presence with Open enabled=false/clickable=false, full-width Homepage and intermediate header morph frames, default icon selection and persistence across force-stop/relaunch (APP restored), Settings theme switching and expandable privacy. No test cases, media playback checks or network connections were run. Evidence: new-window-*, final-new-*, header-*, modern-settings-*, chosen-default-app, default-app-restarted, gradient-cards-* and final-settings-light under the review capture directories.

Final card refinements: equal 12 dp padding, no circular backgrounds behind Home/Close controls, red close glyphs, blue default Home glyph, and a dedicated bottom sixth with a vertical theme-toned opacity gradient (100% bottom to 0% top) under the centered floating label. Final source validates with no analyzer issues and builds successfully.


## Full-card preview background

Latest refinement replaces the inset screenshot box with a screenshot filling the entire rounded card. The unchanged lower-sixth gradient and centered label overlay that background. Home and red Close controls are positioned 2 dp from their top/side edges with 44 dp hit areas and transparent backgrounds. The selected default Home remains blue. No window-selection, default persistence, or close behavior changed. Dart analysis has no issues and assembleDebug passes; final rendering reviewed on emulator-5582. No test cases added or run.
