import 'dart:async';

import 'package:yr_file_explorer/features/storage/presentation/pickers/local_directory_picker.dart';
import 'package:yr_file_explorer/shared/widgets/grouped_file_view.dart';

import 'widgets/split_pane_handle.dart';

import 'package:yr_file_explorer/features/archives/presentation/dialogs/create_archive_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_selection_header.dart';

import 'widgets/folder_drag_drop.dart';

import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_search_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:yr_file_explorer/core/utils/file_sort.dart';
import 'package:flutter/services.dart';

import 'package:yr_file_explorer/shared/widgets/progress_overlay.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_navigation_header.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/archives/presentation/archive_page.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/files/presentation/open_explorer_file.dart';
import 'package:yr_file_explorer/features/sharing/application/sharing_session.dart';
import 'package:yr_file_explorer/features/sharing/presentation/sharing_dialogs.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/segmented_tabs.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
import 'package:yr_file_explorer/shared/widgets/drag_selection_region.dart';
import 'package:yr_file_explorer/shared/widgets/selection_drag_area.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class FileBrowser extends StatefulWidget {
  final String path;
  final AppSettings settings;
  final FileClipboard clipboard;
  final String? category, title;
  final bool recent;
  final bool split, embedded;
  final VoidCallback? onClosePane, onPaneStateChanged;
  final bool initialSearch;
  final int? windowId;
  const FileBrowser({
    super.key,
    required this.path,
    required this.settings,
    required this.clipboard,
    this.category,
    this.title,
    this.recent = false,
    this.split = false,
    this.embedded = false,
    this.onClosePane,
    this.onPaneStateChanged,
    this.initialSearch = false,
    this.windowId,
  });
  @override
  State<FileBrowser> createState() => FileBrowserState();
}

class FileBrowserState extends State<FileBrowser> with WidgetsBindingObserver {
  late String path;
  final lowerPaneKey = GlobalKey<FileBrowserState>();
  bool lowerPaneActive = false, paneNotificationPending = false;
  double splitRatio = .5,
      splitDragY = 0,
      splitDragRatio = .5,
      restoredSplitRatio = .5;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (widget.onPaneStateChanged == null || paneNotificationPending) return;
    paneNotificationPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      paneNotificationPending = false;
      if (mounted) widget.onPaneStateChanged?.call();
    });
  }

  void focusPane(bool lower) {
    if (lowerPaneActive != lower) setState(() => lowerPaneActive = lower);
    if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.pasteActions[widget.windowId!] = lower
          ? lowerPaneKey.currentState?.paste ?? paste
          : paste;
    }
  }

  @override
  void didUpdateWidget(covariant FileBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.split != widget.split) {
      lowerPaneActive = false;
      if (widget.windowId != null) {
        ExplorerWorkspaceSession.instance.pasteActions[widget.windowId!] =
            paste;
      }
    }
  }

  late bool previousHidden, previousFolderSizes;
  List<Json> entries = [];
  List<Json>? _sortedEntries;
  String? _cachedSort;
  bool? _cachedDescending;
  final selected = <String>{};
  String? locatedPath;
  bool locatePending = false;
  final selectionKeys = <String, GlobalKey>{};
  final pickupIconKeys = <String, GlobalKey>{};
  final filesScroll = ScrollController();
  final selectionMenuAnchor = GlobalKey();
  final history = <String>[];
  bool folderDragging = false, movingFolder = false;
  Set<String> draggedFolderPaths = {};
  bool loading = true,
      refreshing = false,
      calculating = false,
      searching = false,
      deepSearch = false;
  String searchType = 'All files';
  String? error;
  String query = '';
  String scanId = '';
  int generation = 0;
  late int seenRevision;
  final searchController = TextEditingController();
  Timer? searchDebounce;
  bool get document => path.startsWith('content:');
  bool get virtual =>
      widget.category != null || widget.recent || query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    path = ExplorerWorkspaceSession.instance.storagePath(widget.path);
    readLocationSelection();
    previousHidden = widget.settings.hidden;
    previousFolderSizes = widget.settings.folderSizes;
    widget.settings.addListener(settingsChanged);
    searching = widget.initialSearch;
    seenRevision = widget.clipboard.revision;
    widget.clipboard.addListener(changed);
    wasActive = ExplorerWorkspaceSession.instance.activeId == widget.windowId;
    ExplorerWorkspaceSession.instance.addListener(workspaceChanged);
    if (widget.windowId != null && widget.category == null && !widget.recent) {
      ExplorerWorkspaceSession.instance.pasteActions[widget.windowId!] = paste;
      ExplorerWorkspaceSession.instance.localNavigationActions[widget
              .windowId!] =
          openLocation;
    }
    load();
  }

  bool wasActive = false;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (widget.windowId == null ||
            ExplorerWorkspaceSession.instance.activeId == widget.windowId)) {
      // Returning from a dismissed system picker must preserve the visible grid.
      load(background: true);
    }
  }

  void workspaceChanged() {
    final active =
        ExplorerWorkspaceSession.instance.activeId == widget.windowId;
    if (active && !wasActive) load(background: true);
    wasActive = active;
  }

  void settingsChanged() {
    final changedHidden = previousHidden != widget.settings.hidden;
    final changedSizes = previousFolderSizes != widget.settings.folderSizes;
    previousHidden = widget.settings.hidden;
    previousFolderSizes = widget.settings.folderSizes;
    if (changedHidden || changedSizes) {
      load();
    } else {
      changed();
    }
  }

  void changed() {
    if (!mounted) return;
    if (seenRevision != widget.clipboard.revision) {
      seenRevision = widget.clipboard.revision;
      load(background: true);
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(settingsChanged);
    widget.clipboard.removeListener(changed);
    ExplorerWorkspaceSession.instance.removeListener(workspaceChanged);
    ExplorerWorkspaceSession.instance.pasteActions.remove(widget.windowId);
    ExplorerWorkspaceSession.instance.localNavigationActions.remove(
      widget.windowId,
    );
    searchController.dispose();
    filesScroll.dispose();
    Native.call('cancelAnalysis', {'id': scanId});
    super.dispose();
  }

  Future<void> load({bool background = false}) async {
    final version = ++generation;
    if (locatedPath != null && parentPath(locatedPath!) != path) {
      locatedPath = null;
      locatePending = false;
    }
    final target = virtual ? null : locatedPath;
    final showHidden = widget.settings.hidden;
    final revealTarget = target != null && baseName(target).startsWith('.');
    Native.call('cancelAnalysis', {'id': scanId});
    setState(() {
      if (!background) loading = true;
      refreshing = background;
      calculating = false;
      error = null;
      if (!background || !selected.contains(target)) selected.clear();
    });
    try {
      if (virtual) scanId = 'search-${DateTime.now().microsecondsSinceEpoch}';
      var rows = virtual
          ? await Native.rows('search', {
              'path': path,
              'query': query,
              'category':
                  widget.category ??
                  (searchType == 'All files' ? '' : searchType),
              'id': scanId,
              'recursive': query.isEmpty || deepSearch,
              'hidden': showHidden,
            })
          : await Native.rows('list', {
              'path': path,
              'hidden': showHidden || revealTarget,
              'countItems': true,
            });
      if (revealTarget && !showHidden) {
        rows.removeWhere(
          (row) =>
              row['path'] != target &&
              baseName(row['path'] as String).startsWith('.'),
        );
      }
      if (widget.recent) {
        rows.removeWhere((e) => e['directory'] == true);
        rows.sort(
          (a, b) => (b['modified'] as num).compareTo(a['modified'] as num),
        );
        rows = rows.take(200).toList();
      }
      if (!mounted || version != generation) return;
      final selectTarget = locatePending && target != null;
      setState(() {
        entries = rows;
        _sortedEntries = null;
        final paths = rows.map((row) => row['path']).toSet();
        selectionKeys.removeWhere((path, _) => !paths.contains(path));
        pickupIconKeys.removeWhere((path, _) => !paths.contains(path));
        selected.retainAll(paths);
        if (selectTarget) {
          locatePending = false;
          if (paths.contains(target)) selected.add(target);
        }
        loading = false;
        refreshing = false;
      });
      if (selectTarget && selected.contains(target)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || version != generation || !selected.contains(target)) {
            return;
          }
          final item = selectionKeys[target]?.currentContext;
          if (item != null) Scrollable.ensureVisible(item, alignment: .5);
        });
      }
      if (widget.settings.folderSizes && !virtual) {
        await calculate(version);
      }
    } catch (e) {
      if (mounted && version == generation) {
        setState(() {
          loading = false;
          refreshing = false;
          error = e is PlatformException ? e.message : e.toString();
        });
      }
    }
  }

  Future<void> calculate(int version) async {
    final id = 'browser-${DateTime.now().microsecondsSinceEpoch}';
    scanId = id;
    setState(() => calculating = true);
    try {
      final data = await Native.call<Map>('analyze', {'path': path, 'id': id});
      if (mounted && version == generation) {
        final byPath = {
          for (final row in jsonRows(data?['children'])) row['path']: row,
        };
        setState(() {
          for (var e in entries) {
            final size = byPath[e['path']];
            if (size != null) e.addAll(size);
          }
          _sortedEntries = null;
          calculating = false;
        });
      }
    } catch (e) {
      if (mounted && version == generation) setState(() => calculating = false);
    }
  }

  void openSearch() {
    setState(() => searching = true);
    searchController.text = query;
  }

  void searchChanged(String value) {
    searchDebounce?.cancel();
    if (document) return;
    final term = value.trim();
    if (term.characters.length < 3) {
      if (query.isNotEmpty) applySearch('', live: true);
    } else if (term != query) {
      searchDebounce = Timer(const Duration(milliseconds: 180), () {
        if (mounted && searching && searchController.text.trim() == term) {
          applySearch(term, live: true);
        }
      });
    }
  }

  void submitSearch(String value) {
    searchDebounce?.cancel();
    final term = value.trim();
    if (term.isEmpty) return;
    if (term == query && !deepSearch && error == null) {
      setState(() => searching = false);
      return;
    }
    applySearch(term, live: false);
  }

  void applySearch(String term, {required bool live}) {
    setState(() {
      query = term;
      deepSearch = false;
      searching = live;
    });
    if (filesScroll.hasClients) filesScroll.jumpTo(0);
    load(background: live);
  }

  void closeSearch() {
    searchDebounce?.cancel();
    final reload = query.isNotEmpty || deepSearch;
    FocusScope.of(context).unfocus();
    searchController.clear();
    setState(() {
      searching = false;
      query = '';
      deepSearch = false;
    });
    if (reload) load();
  }

  Widget searchHeader() => ExplorerSearchHeader(
    controller: searchController,
    onClose: closeSearch,
    onChanged: searchChanged,
    onSubmitted: submitSearch,
    hint: searchType == 'All files' ? 'Search files' : searchType,
    leading: PopupMenuButton<String>(
      tooltip: 'Search type',
      initialValue: searchType,
      onSelected: (value) {
        setState(() => searchType = value);
        if (query.isNotEmpty) load(background: true);
      },
      itemBuilder: (_) => [
        'All files',
        'Folders',
        'Images',
        'Music',
        'Videos',
        'Documents',
        'Apps',
      ].map((type) => PopupMenuItem(value: type, child: Text(type))).toList(),
      icon: const Icon(Icons.search, color: primaryBlue, size: 22),
    ),
  );

  Widget breadcrumbs() {
    final session = ExplorerWorkspaceSession.instance;
    final entries = widget.category != null || widget.recent
        ? <(String, String)>[
            (widget.title ?? widget.category ?? 'Recent', path),
          ]
        : document
        ? <(String, String)>[('Connected storage', path)]
        : session.breadcrumbsFor(path);
    return ExplorerBreadcrumbs(
      entries: entries,
      onNavigate: navigate,
      onCurrent: () => showStorageLocations(context, onSelect: navigate),
    );
  }

  void readLocationSelection() {
    locatedPath = ExplorerWorkspaceSession.instance.takePendingSelection(
      widget.windowId,
    );
    locatePending = locatedPath != null;
  }

  void openLocation(String next, bool startSearch) {
    searchDebounce?.cancel();
    final hadQuery = query.isNotEmpty || deepSearch;
    final hadLocatedPath = locatedPath != null;
    readLocationSelection();
    if (locatePending && lowerPaneActive) focusPane(false);
    searching = startSearch;
    query = '';
    deepSearch = false;
    searchController.clear();
    selected.clear();
    if (next != path) {
      navigate(next);
    } else {
      setState(() {});
      if (hadQuery || hadLocatedPath || locatePending) load();
    }
  }

  void navigate(String next) {
    final session = ExplorerWorkspaceSession.instance;
    next = session.storagePath(next);
    if (!session.containsStoragePath(next)) return;
    if (next == path) return;
    searchDebounce?.cancel();
    // Retain one return sequence when breadcrumbs revisit the same folders.
    // Repeating sdcard -> Download -> sdcard must not grow the stack forever.
    final previousVisit = history.lastIndexOf(path);
    if (previousVisit >= 0) {
      history.removeRange(previousVisit, history.length);
    }
    history.add(path);
    path = next;
    if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
    }
    query = '';
    searchController.clear();
    load();
  }

  void back() {
    if (selected.isNotEmpty) {
      setState(() => selected.clear());
      return;
    }
    if (searching || query.isNotEmpty) {
      closeSearch();
      return;
    }
    history.removeWhere(
      (p) => !ExplorerWorkspaceSession.instance.containsStoragePath(p),
    );
    if (history.isNotEmpty) {
      path = history.removeLast();
      if (widget.windowId != null) {
        ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
      }
      query = '';
      searchController.clear();
      load();
    } else if (!document &&
        !virtual &&
        ExplorerWorkspaceSession.instance.containsStoragePath(
          parentPath(path),
        )) {
      // Moving up after history is exhausted must not push this folder back
      // onto history, otherwise Back would bounce between child and parent.
      path = parentPath(path);
      if (widget.windowId != null) {
        ExplorerWorkspaceSession.instance.updatePath(widget.windowId!, path);
      }
      query = '';
      searchController.clear();
      load();
    } else {
      goHome();
    }
  }

  void goHome() {
    if (widget.embedded) return;
    if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.activate(null);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> open(Json e) async {
    if (selected.isNotEmpty) {
      toggle(e['path']);
      return;
    }
    if (e['directory'] == true) {
      if (virtual) {
        if (widget.windowId != null) {
          ExplorerWorkspaceSession.instance.open(e['path']);
          return;
        }
        Navigator.push(
          context,
          ExplorerPageRoute<void>(
            builder: (_) => FileBrowser(
              path: e['path'],
              settings: widget.settings,
              clipboard: widget.clipboard,
            ),
          ),
        );
      } else {
        navigate(e['path']);
      }
      return;
    }
    try {
      final refresh = await openExplorerFile(
        context,
        e,
        nearby: sorted,
        recycle: widget.settings.recycle,
        openArchive: widget.windowId != null
            ? null
            : (path) => Navigator.of(context).push<void>(
                ExplorerPageRoute<void>(
                  builder: (_) => ArchivePage(
                    path: path,
                    settings: widget.settings,
                    clipboard: widget.clipboard,
                  ),
                ),
              ),
      );
      if (refresh && mounted) await load();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void toggle(String p) => setState(() {
    selected.contains(p) ? selected.remove(p) : selected.add(p);
  });
  List<Json> get sorted {
    final settings = widget.settings;
    if (_sortedEntries == null ||
        _cachedSort != settings.sort ||
        _cachedDescending != settings.descending) {
      _cachedSort = settings.sort;
      _cachedDescending = settings.descending;
      _sortedEntries = sortedFileEntries(
        entries,
        sort: settings.sort,
        descending: settings.descending,
      );
    }
    return _sortedEntries!;
  }

  Future<void> create(bool dir) async {
    final name = await askText(context, dir ? 'New folder' : 'New file');
    if (name == null || name.isEmpty) return;
    try {
      await Native.call('create', {
        'path': path,
        'name': name,
        'directory': dir,
      });
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> paste() async {
    try {
      await busy(
        widget.clipboard.move ? 'Moving files…' : 'Copying files…',
        () => Native.call('paste', {
          'path': path,
          'sources': widget.clipboard.paths,
          'move': widget.clipboard.move,
        }),
      );
      widget.clipboard.clear();
      widget.clipboard.filesChanged();
    } catch (e) {
      if (mounted) {
        showError(context, e);
        await load();
      }
    }
  }

  Future<void> dropFolder(FolderDragData source, Json destination) async {
    final session = ExplorerWorkspaceSession.instance;
    final target = session.storagePath(destination['path'] as String);
    if (movingFolder || !source.canMoveInto(target)) return;
    movingFolder = true;
    try {
      final accepted = await confirm(
        context,
        source.paths.length == 1 ? 'Move item' : 'Move items',
        source.paths.length == 1
            ? 'Move "${source.name}" into "${destination['name']}"?'
            : 'Move ${source.paths.length} selected items into "${destination['name']}"?',
        action: 'Move',
      );
      if (!accepted || !mounted) return;
      await busy(
        source.paths.length == 1 ? 'Moving item…' : 'Moving items…',
        () => Native.call('paste', {
          'path': target,
          'sources': dragRootPaths(source.paths),
          'move': true,
          'preflight': true,
        }),
      );
      if (!mounted) return;
      setState(() => selected.removeAll(source.paths));
      widget.clipboard.filesChanged();
    } catch (error) {
      if (mounted) {
        showError(context, error);
        widget.clipboard.filesChanged();
      }
    } finally {
      movingFolder = false;
    }
  }

  void analyze([String? target]) => ExplorerWorkspaceSession.instance.open(
    target ?? path,
    page: 'storage_analysis',
    title: 'Folder Analysis',
  );

  Future<void> action(String action, List<Json> rows) async {
    if (rows.isEmpty) return;
    final paths = rows.map((e) => e['path'] as String).toList(),
        first = rows.first;
    try {
      switch (action) {
        case 'Open':
          navigate(paths.first);
          break;
        case 'Open with':
          await Native.call('openExternal', {'path': paths.first});
          break;
        case 'Copy to':
        case 'Move to':
          final destination = await chooseDirectory();
          if (destination == null) return;
          await busy(
            action == 'Move to' ? 'Moving…' : 'Copying…',
            () => Native.call('paste', {
              'path': destination,
              'sources': paths,
              'move': action == 'Move to',
            }),
          );
          await load();
          break;
        case 'Move to Private Space':
          try {
            await Native.call('privateUnlock');
            if (!mounted) return;
            await busy(
              'Moving to Private Space…',
              () =>
                  Native.call('privateImport', {'paths': dragRootPaths(paths)}),
            );
            if (!mounted) return;
            selected.clear();
            await load();
            if (mounted) {
              showExplorerNotice(
                context,
                paths.length == 1
                    ? 'Item moved to Private Space'
                    : '${paths.length} items moved to Private Space',
                icon: Icons.lock_outline,
              );
            }
          } finally {
            await Native.call('privateLock');
            await Native.call('privateShield', {'enabled': false});
            if (mounted) await load(background: true);
          }
          break;
        case 'Associate app':
          await Native.call('openExternal', {'path': paths.first});
          break;
        case 'Copy':
        case 'Cut':
          widget.clipboard.put(paths, action == 'Cut');
          setState(() => selected.clear());
          break;
        case 'Share':
          await Native.call('share', {'paths': paths});
          break;
        case 'Send':
          await showSharingDevices(context, dragRootPaths(paths));
          break;
        case 'Rename':
          final name = await askText(context, 'Rename', initial: first['name']);
          if (name == null || name.isEmpty) return;
          await Native.call('rename', {'path': paths.first, 'name': name});
          await load();
          break;
        case 'Delete':
          final recycle = widget.settings.recycle;
          if (!await confirm(
            context,
            recycle ? 'Move to Recycle Bin?' : 'Delete permanently?',
            '${paths.length} selected items${recycle ? ' can be restored from the Recycle Bin.' : ' will be permanently deleted.'}',
            action: recycle ? 'Move' : 'Delete',
          )) {
            return;
          }
          await busy(
            recycle ? 'Moving files to Recycle Bin…' : 'Deleting files…',
            () =>
                Native.call('delete', {'paths': paths, 'permanent': !recycle}),
          );
          if (widget.clipboard.paths.any(paths.contains)) {
            final remaining = widget.clipboard.paths
                .where((p) => !paths.contains(p))
                .toList();
            widget.clipboard.put(remaining, widget.clipboard.move);
          }
          await load();
          break;
        case 'Hide':
        case 'Unhide':
          for (final row in rows) {
            final name = row['name'] as String;
            final next = action == 'Hide' ? '.$name' : name.substring(1);
            if (next.isEmpty) continue;
            await Native.call('rename', {'path': row['path'], 'name': next});
          }
          await load();
          break;
        case 'Favorite':
          final removing =
              paths.length == 1 &&
              widget.settings.favorites.contains(paths.first);
          if (paths.length == 1) {
            await widget.settings.favorite(paths.first);
          } else {
            for (final selectedPath in paths) {
              if (!widget.settings.favorites.contains(selectedPath)) {
                widget.settings.favorites.add(selectedPath);
              }
            }
            await widget.settings.save();
          }
          if (!mounted) return;
          setState(() => selected.clear());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showExplorerNotice(
              context,
              removing
                  ? 'Removed from Favorites'
                  : paths.length == 1
                  ? 'Folder added to Favorites'
                  : '${paths.length} items added to Favorites',
              icon: removing ? Icons.star_outline : Icons.star_rounded,
            );
          });
          break;
        case 'Analyze':
          analyze(paths.first);
          break;
        case 'Properties':
          await properties(first);
          break;
        case 'Compress':
          final archive = await showCreateArchiveDialog(
            context,
            first['name'].toString(),
          );
          if (archive == null || !mounted) return;
          await busy(
            'Compressing…',
            () => Native.call('archiveCreate', {
              'paths': paths,
              'destination': '${parentPath(paths.first)}/${archive['name']}',
              'password': archive['password'],
              'format': archive['format'],
            }),
          );
          await load();
          break;
        case 'Extract':
          final name = await askText(
            context,
            'Extract to a new folder',
            initial: archiveStem(first['name'].toString()),
          );
          if (name == null || name.isEmpty || !mounted) return;
          final password = await askText(
            context,
            'Archive password',
            secret: true,
            label: 'Password (leave blank if none)',
          );
          if (password == null) return;
          await busy(
            'Extracting…',
            () => Native.call('archiveExtract', {
              'entries': <String>[],
              'path': paths.first,
              'destination': '${parentPath(paths.first)}/$name',
              'password': password,
            }),
          );
          await load();
          break;
        case 'Encrypt':
        case 'Decrypt':
          final password = await askText(
            context,
            action,
            secret: true,
            label: 'Password (8+ characters)',
            description:
                'Your original file is kept. Passwords cannot be recovered.',
          );
          if (password == null) return;
          String? outputName;
          if (action == 'Decrypt') {
            final original = baseName(paths.first)
                .replaceFirst(RegExp(r'\.yrvault$'), '');
            final dot = original.lastIndexOf('.');
            final suggested = dot > 0
                ? '${original.substring(0, dot)} (decrypted)${original.substring(dot)}'
                : '$original (decrypted)';
            if (!mounted) return;
            outputName = await askText(
              context,
              'Save decrypted file',
              initial: suggested,
            );
            if (outputName == null || outputName.trim().isEmpty) return;
          }
          await busy(
            '$action file…',
            () => Native.call('crypt', {
              'path': paths.first,
              'password': password,
              'decrypt': action == 'Decrypt',
              'name': outputName ?? '',
            }),
          );
          await load();
          break;
        case 'Save to Downloads':
          await busy(
            'Importing…',
            () => Native.call('documentImport', {
              'uri': paths.first,
              'name': first['name'],
              'path': '/storage/emulated/0/Download',
            }),
          );
          if (mounted) {
            showExplorerNotice(
              context,
              'Saved to Downloads',
              icon: Icons.download_outlined,
            );
          }
          break;
        case 'Copy path':
          await Clipboard.setData(ClipboardData(text: paths.join('\n')));
          break;
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> busy(String label, Future<dynamic> Function() operation) async {
    await runFileOperation(context, label, operation);
  }

  Future<void> properties(Json e) async {
    Json row = e;
    final isDir = e['directory'] == true;
    if (!e['path'].toString().startsWith('content:')) {
      row = Map<String, dynamic>.from(
        (await Native.call<Map>('properties', {'path': e['path']}))!,
      );
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ExplorerDialog(
        title: const Text('Properties'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e['name'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SelectableText(e['path'], style: const TextStyle(fontSize: 12)),
              const Divider(height: 24),
              _property('Type', isDir ? 'Folder' : e['category'] ?? 'File'),
              _property(
                'Size',
                isDir && e['files'] == null
                    ? 'Tap Analyze to calculate'
                    : '${sizeLabel(e['size'])}\n${countLabel(e['size'])} bytes',
              ),
              if (isDir && e['files'] != null) ...[
                _property(
                  'Contains',
                  '${countLabel(e['folders'] ?? 0)} folders, ${countLabel(e['files'])} files',
                ),
              ],
              _property('Modified', dateLabel(row['modified'] ?? 0)),
              if (row['readable'] != null)
                _property(
                  'Access',
                  '${row['readable'] == true ? 'Read' : ''} ${row['writable'] == true ? '/ Write' : ''}',
                ),
            ],
          ),
        ),
        actions: [
          if (isDir && !document)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                analyze(e['path']);
              },
              child: const Text('Analyze'),
            ),
          if (!isDir && !document)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final hash = await Native.call<String>('checksum', {
                    'path': e['path'],
                  });
                  if (mounted) {
                    await Clipboard.setData(ClipboardData(text: hash!));
                    if (mounted) {
                      showDialog<void>(
                        context: this.context,
                        builder: (c) => ExplorerDialog(
                          title: const Text('SHA-256 (copied)'),
                          content: SelectableText(hash),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                } catch (error) {
                  if (mounted) showError(this.context, error);
                }
              },
              child: const Text('SHA-256'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _property(String name, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            name,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
  List<String> actions(Json e) => document
      ? [
          if (e['directory'] == true) 'Open' else 'Open with',
          'Share',
          if (e['directory'] != true) 'Save to Downloads',
          if (e['directory'] == true) 'Analyze',
          'Copy path',
        ]
      : [
          if (e['directory'] == true) 'Open' else 'Open with',
          if (e['directory'] != true) 'Associate app',
          'Copy',
          'Cut',
          'Copy to',
          'Move to',
          'Move to Private Space',
          'Rename',
          'Delete',
          'Share',
          'Compress',
          if (e['directory'] == true)
            'Analyze'
          else ...[
            if (isSupportedArchive(e['name'].toString())) 'Extract',
            if (e['name'].toString().endsWith('.yrvault'))
              'Decrypt'
            else
              'Encrypt',
          ],
          e['name'].toString().startsWith('.') ? 'Unhide' : 'Hide',
          'Favorite',
          if (!document && !virtual && SharingSession.instance.connected)
            'Send',
          'Properties',
          'Copy path',
        ];
  @override
  Widget build(BuildContext context) {
    final browser = browserPane(context);
    if (!widget.split || widget.embedded) return browser;
    return Scaffold(
      extendBody: true,
      primary: false,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = (constraints.maxHeight - explorerTabHeight).clamp(
              1.0,
              double.infinity,
            );
            final minimum = (120 / available).clamp(.2, .5);
            final ratio = splitRatio.clamp(minimum, 1 - minimum);
            void resize(double delta) => setState(
              () =>
                  splitRatio = (splitRatio + delta).clamp(minimum, 1 - minimum),
            );
            final handle = SplitPaneHandle(
              expanded: ratio <= minimum + .001,
              onToggle: () {
                focusPane(true);
                setState(() {
                  if (ratio <= minimum + .001) {
                    splitRatio = restoredSplitRatio.clamp(minimum, 1 - minimum);
                  } else {
                    restoredSplitRatio = ratio;
                    splitRatio = minimum;
                  }
                });
              },
              onIncrease: () => resize(.05),
              onDecrease: () => resize(-.05),
              onDragStart: (details) {
                splitDragY = details.globalPosition.dy;
                splitDragRatio = ratio;
              },
              onDragUpdate: (details) => setState(() {
                splitRatio =
                    (splitDragRatio +
                            (details.globalPosition.dy - splitDragY) /
                                available)
                        .clamp(minimum, 1 - minimum);
              }),
            );
            return Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: explorerTabHeight,
                      child: ReferenceTabs(
                        onLocal: () => ExplorerWorkspaceSession.instance
                            .activate(widget.windowId),
                      ),
                    ),
                    Expanded(
                      flex: (ratio * 1000).round(),
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        removeBottom: true,
                        child: Listener(
                          onPointerDown: (_) => focusPane(false),
                          child: ClipRect(child: browser),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: ((1 - ratio) * 1000).round(),
                      child: Listener(
                        onPointerDown: (_) => focusPane(true),
                        child: ClipRect(
                          child: FileBrowser(
                            key: lowerPaneKey,
                            path: ExplorerWorkspaceSession.instance.root,
                            settings: widget.settings,
                            clipboard: widget.clipboard,
                            embedded: true,
                            onPaneStateChanged: () {
                              if (mounted && widget.split && lowerPaneActive) {
                                setState(() {});
                              }
                            },
                            onClosePane: () => ExplorerWorkspaceSession.instance
                                .setSplit(widget.windowId!, false),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top:
                      explorerTabHeight +
                      available * ratio -
                      SplitPaneHandle.height / 2,
                  height: SplitPaneHandle.height,
                  child: handle,
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: lowerPaneActive && lowerPaneKey.currentState != null
          ? lowerPaneKey.currentState!.bottomToolbar()
          : bottomToolbar(),
    );
  }

  Widget browserPane(BuildContext context) {
    final rows = sorted;
    return PopScope(
      canPop: widget.embedded
          ? true
          : widget.windowId != null
          ? ExplorerWorkspaceSession.instance.activeId != widget.windowId
          : history.isEmpty && selected.isEmpty && !searching && query.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            !widget.embedded &&
            (widget.windowId == null ||
                ExplorerWorkspaceSession.instance.activeId ==
                    widget.windowId)) {
          back();
        }
      },
      child: Scaffold(
        primary: !widget.embedded && !widget.split,
        extendBody: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: explorerChrome(context),
          foregroundColor: explorerForeground(context),
          primary: !widget.embedded && !widget.split,
          toolbarHeight: widget.embedded || widget.split
              ? 0
              : explorerTabHeight,
          leadingWidth: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: widget.embedded || widget.split
              ? null
              : ReferenceTabs(
                  onLocal: () => ExplorerWorkspaceSession.instance.open(
                    ExplorerWorkspaceSession.instance.root,
                  ),
                ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(explorerHeaderHeight),
            child: searching || selected.isNotEmpty
                ? ExplorerHeaderFrame(
                    separators: false,
                    child: searching
                        ? searchHeader()
                        : ExplorerSelectionHeader(
                            count: Text('${selected.length}/${entries.length}'),
                            onDone: () => setState(() => selected.clear()),
                            onSelectAll: () => setState(
                              () => selected.addAll(
                                entries.map((e) => e['path'] as String),
                              ),
                            ),
                            onClear: () => setState(() => selected.clear()),
                          ),
                  )
                : ExplorerNavigationHeader(
                    onBack: back,
                    onClose: widget.split
                        ? null
                        : widget.embedded
                        ? widget.onClosePane
                        : !document &&
                              widget.category == null &&
                              !widget.recent &&
                              ExplorerWorkspaceSession.instance.volumeFor(
                                    path,
                                  )?['primary'] !=
                                  false
                        ? null
                        : () {
                            if (widget.windowId != null) {
                              ExplorerWorkspaceSession.instance.close(
                                widget.windowId!,
                              );
                            } else {
                              Navigator.maybePop(context);
                            }
                          },
                    location: query.isNotEmpty
                        ? InkWell(
                            onTap: () => showStorageLocations(
                              context,
                              onSelect: navigate,
                            ),
                            child: const ExplorerLocationPill(
                              child: Center(child: Text('Search Result')),
                            ),
                          )
                        : breadcrumbs(),
                  ),
          ),
        ),
        body: dropSurface(
          ExplorerProgressOverlay(
            active: refreshing || calculating,
            child: WorkspaceBodySlide(
              allowTabSwipe:
                  selected.isEmpty &&
                  !folderDragging &&
                  !widget.split &&
                  !widget.embedded,
              child: SafeArea(
                top: false,
                bottom: false,
                child: Column(
                  children: [
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                          ? EmptyState(
                              icon: Icons.lock_outline,
                              title: 'Cannot open folder',
                              message: error!,
                              action: FilledButton(
                                onPressed: load,
                                child: const Text('Retry'),
                              ),
                            )
                          : rows.isEmpty
                          ? EmptyState(
                              title: virtual
                                  ? 'No matching files'
                                  : 'Empty folder',
                              message: virtual
                                  ? 'Try a different search or category.'
                                  : 'Create a folder or paste files here.',
                            )
                          : DragSelectionRegion(
                              continueFromLongPress: !folderDragging,
                              enabled: selected.isNotEmpty && !folderDragging,
                              itemKeys: selectionKeys,
                              scroll: filesScroll,
                              isSelected: selected.contains,
                              onSelection: (p, value) => setState(() {
                                value ? selected.add(p) : selected.remove(p);
                              }),
                              child: RefreshIndicator(
                                onRefresh: () => load(background: true),
                                child: widget.settings.grid
                                    ? LayoutBuilder(
                                        builder: (context, constraints) => GroupedFileView(
                                          entries: rows,
                                          groupBy: widget.settings.groupBy,
                                          descending:
                                              widget.settings.groupDescending,
                                          child: GridView.builder(
                                            key: PageStorageKey(
                                              'files-grid-${widget.windowId}-${widget.embedded}',
                                            ),
                                            controller: filesScroll,
                                            padding: EdgeInsets.fromLTRB(
                                              12,
                                              14,
                                              12,
                                              (widget.split
                                                  ? 12.0
                                                  : ExplorerBottomBar.contentBottomPadding(
                                                      context,
                                                    )),
                                            ),
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount:
                                                      ((constraints.maxWidth -
                                                                  24 +
                                                                  8) /
                                                              (gridIconSize +
                                                                  10 +
                                                                  8))
                                                          .floor()
                                                          .clamp(1, 12),
                                                  mainAxisExtent:
                                                      gridIconSize +
                                                      16 +
                                                      gridLabelHeight(context),
                                                  crossAxisSpacing: 8,
                                                  mainAxisSpacing: 8,
                                                ),
                                            itemCount: rows.length,
                                            itemBuilder: (_, i) =>
                                                selectionItem(
                                                  rows[i],
                                                  _grid(rows[i]),
                                                ),
                                          ),
                                        ),
                                      )
                                    : GroupedFileView(
                                        entries: rows,
                                        groupBy: widget.settings.groupBy,
                                        descending:
                                            widget.settings.groupDescending,
                                        child: ListView.builder(
                                          controller: filesScroll,
                                          padding: EdgeInsets.only(
                                            bottom: widget.split
                                                ? 12.0
                                                : ExplorerBottomBar.contentBottomPadding(
                                                    context,
                                                  ),
                                          ),
                                          itemCount: rows.length,
                                          itemBuilder: (_, i) => selectionItem(
                                            rows[i],
                                            _row(rows[i]),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                    ),
                    if (virtual &&
                        entries.length >= (widget.recent ? 200 : 10000))
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          'Showing the first ${entries.length} results',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    if (query.isNotEmpty && !deepSearch && !loading)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: const RoundedRectangleBorder(),
                          ),
                          onPressed: () {
                            deepSearch = true;
                            load();
                          },
                          child: const Text(
                            'File not found? Try deeper search',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.split || widget.embedded
            ? null
            : bottomToolbar(),
      ),
    );
  }

  Widget bottomToolbar() {
    List<Json> picks() =>
        entries.where((e) => selected.contains(e['path'])).toList();
    return ExplorerBottomBar(
      child: selected.isNotEmpty
          ? Row(
              children: [
                _tool(Icons.copy, 'Copy', () => action('Copy', picks())),
                _tool(Icons.content_cut, 'Cut', () => action('Cut', picks())),
                _tool(
                  Icons.delete_outline,
                  'Delete',
                  () => action('Delete', picks()),
                ),
                _tool(
                  Icons.edit_outlined,
                  'Rename',
                  () => action('Rename', picks()),
                ),
                ExplorerAction(
                  key: selectionMenuAnchor,
                  icon: Icons.more_horiz,
                  label: 'More',
                  onTap: () => showSelectionMenu(picks()),
                ),
              ],
            )
          : widget.clipboard.paths.isNotEmpty && !document && !virtual
          ? Row(
              children: [
                IconButton(
                  tooltip: 'Clear clipboard',
                  onPressed: widget.clipboard.clear,
                  icon: Icon(
                    Icons.close,
                    color: explorerForeground(context).withValues(alpha: .7),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${widget.clipboard.paths.length} to ${widget.clipboard.move ? 'move' : 'copy'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: explorerForeground(context),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Windows and Clipboard',
                  onPressed: showWindows,
                  icon: Icon(
                    Icons.filter_none,
                    color: explorerForeground(context),
                  ),
                ),
                FilledButton.icon(
                  onPressed: loading ? null : paste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste'),
                ),
                const SizedBox(width: 12),
              ],
            )
          : Row(
              children: [
                _tool(Icons.add, 'New', showNewMenu),
                _tool(Icons.search, 'Search', openSearch),
                _tool(Icons.refresh, 'Refresh', () => load(background: true)),
                _tool(Icons.grid_view, 'View', showViewMenu),
                _tool(Icons.filter_none, 'Windows', showWindows),
              ],
            ),
    );
  }

  Widget dropSurface(Widget child) {
    if (document || virtual) return child;
    return FolderDropTarget(
      path: path,
      enabled: !loading && !movingFolder,
      onDrop: (source) => dropFolder(source, {
        'path': path,
        'name': displayFileName(baseName(path)),
      }),
      child: child,
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) =>
      ExplorerAction(icon: icon, label: label, onTap: onTap);

  Future<String?> chooseDirectory() => chooseLocalDirectory(
    context,
    initialPath: path,
    hidden: widget.settings.hidden,
  );

  Future<void> showNewMenu() async {
    final directory = await chooseNewItemType(context);
    if (directory != null) create(directory);
  }

  Future<void> showSelectionMenu(List<Json> picks) async {
    final names = picks.length == 1
        ? actions(picks.first)
              .where(
                (name) => ![
                  'Open',
                  'Copy',
                  'Cut',
                  'Delete',
                  'Rename',
                  'Associate app',
                ].contains(name),
              )
              .toList()
        : [
            'Favorite',
            'Share',
            if (!document && !virtual && SharingSession.instance.connected)
              'Send',
            'Copy to',
            'Move to',
            'Move to Private Space',
            'Compress',
            'Copy path',
          ];
    final box = selectionMenuAnchor.currentContext?.findRenderObject();
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    final anchor = box is RenderBox && overlay is RenderBox
        ? box.localToGlobal(Offset.zero, ancestor: overlay) & box.size
        : null;
    final name = await showExplorerActionMenu(
      context,
      names,
      anchor: anchor,
      isFavorite:
          picks.isNotEmpty &&
          picks.every(
            (entry) => widget.settings.favorites.contains(entry['path']),
          ),
    );
    if (name != null && mounted) await action(name, picks);
  }

  void showViewMenu() => showExplorerViewMenu(
    context,
    mode: widget.settings.viewMode,
    sort: widget.settings.sort,
    descending: widget.settings.descending,
    sorts: const ['Name', 'Type', 'Size', 'Modified'],
    groupBy: widget.settings.groupBy,
    groupDescending: widget.settings.groupDescending,
    onGroupingChanged: (group, reverse) {
      setState(() {
        widget.settings.groupBy = group;
        widget.settings.groupDescending = reverse;
      });
      widget.settings.save();
    },
    onChanged: (mode, sort, descending) {
      widget.settings.viewMode = mode;
      widget.settings.grid = mode.endsWith('Icon');
      widget.settings.sort = sort;
      widget.settings.descending = descending;
      widget.settings.save();
    },
  );

  void showWindows() => showExplorerWindows(context);

  String subtitle(Json e) {
    if (e['directory'] == true) {
      if (e['files'] != null) {
        return '${sizeLabel(e['size'])}  ·  ${e['folders']} folders, ${e['files']} files${(e['skipped'] as num? ?? 0) > 0 ? ' · partial' : ''}';
      }
      return e['items'] == -1
          ? 'Access restricted'
          : '${e['items'] ?? '—'} items';
    }
    return [
      sizeLabel(e['size'], decimals: 1),
      listDateTimeLabel(e['modified'] ?? 0),
    ].where((value) => value.isNotEmpty).join('  ·  ');
  }

  Widget _row(Json e) => ListTile(
    dense: widget.settings.viewMode.startsWith('Small'),
    selected: selected.contains(e['path']),
    selectedTileColor: primaryBlue.withValues(alpha: .08),
    leading: SizedBox.square(
      key: pickupIconKeys.putIfAbsent(e['path'] as String, GlobalKey.new),
      dimension: widget.settings.viewMode.startsWith('Large') ? 48 : 40,
      child: Center(
        child: selected.contains(e['path'])
            ? const Icon(Icons.check_circle, color: primaryBlue, size: 29)
            : FileGlyph(
                e,
                size: widget.settings.viewMode.startsWith('Large')
                    ? 48
                    : widget.settings.viewMode.startsWith('Small')
                    ? 24
                    : 36,
              ),
      ),
    ),
    title: Text(
      displayFileName(e['name'].toString()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14),
    ),
    subtitle: Text(
      virtual && widget.settings.viewMode.contains('Detail')
          ? '${subtitle(e)}\n${e['path']}'
          : subtitle(e),
      maxLines: virtual && widget.settings.viewMode.contains('Detail') ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    ),
    trailing: SizedBox.square(
      dimension: 48,
      child: selected.isNotEmpty
          ? Transform.scale(
              scale: .75,
              transformHitTests: false,
              child: Checkbox(
                value: selected.contains(e['path']),
                onChanged: (_) => toggle(e['path']),
              ),
            )
          : null,
    ),
    onTap: () => open(e),
  );
  bool canDragEntry(Json entry) =>
      !document && (entry['path'] as String).startsWith('/');

  FolderDragData folderDragData(Json entry) {
    final session = ExplorerWorkspaceSession.instance;
    final path = session.storagePath(entry['path']);
    final paths = <String>{path};
    final dragEntries = <Json>[
      {...entry, 'path': path},
    ];
    for (final item in entries) {
      if (selected.contains(item['path']) && canDragEntry(item)) {
        final itemPath = session.storagePath(item['path']);
        if (paths.add(itemPath)) dragEntries.add({...item, 'path': itemPath});
      }
    }
    return FolderDragData(
      path,
      entry['name'],
      paths: paths.toList(),
      entries: dragEntries,
      directory: entry['directory'] == true,
      category: entry['category'] as String? ?? 'Other',
    );
  }

  Map<String, Offset> visiblePickupOrigins(FolderDragData data) {
    final session = ExplorerWorkspaceSession.instance;
    final paths = data.paths.toSet();
    final origins = <String, Offset>{};
    for (final path in selected) {
      final box = pickupIconKeys[path]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport is! RenderBox || !viewport.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      if (!(Offset.zero & viewport.size).contains(
        viewport.globalToLocal(center),
      )) {
        continue;
      }
      final canonical = session.storagePath(path);
      if (paths.contains(canonical)) origins[canonical] = center;
    }
    return origins;
  }

  // A selected parent already contains its selected descendants. Moving both
  // separately would attempt to move a child that no longer exists.
  List<String> dragRootPaths(List<String> paths) {
    final all = paths.toSet();
    return paths.where((path) {
      var parent = parentPath(path);
      while (parent != '/') {
        if (all.contains(parent)) return false;
        parent = parentPath(parent);
      }
      return true;
    }).toList();
  }

  Widget selectionItem(Json e, Widget child) {
    final hidden = e['name'].toString().startsWith('.');
    if (hidden) child = Opacity(opacity: .5, child: child);
    final localEntry = canDragEntry(e);
    if (localEntry) {
      final folderPath = ExplorerWorkspaceSession.instance.storagePath(
        e['path'],
      );
      if (!loading && !movingFolder) {
        final dragData = folderDragData(e);
        child = FolderDraggable(
          data: dragData,
          pickupOrigins: () => visiblePickupOrigins(dragData),
          isSelected: () => selected.contains(e['path']),
          onHold: () {
            if (mounted) setState(() => selected.add(e['path'] as String));
          },
          iconSize: widget.settings.grid
              ? (widget.settings.viewMode.startsWith('Large')
                    ? 76
                    : widget.settings.viewMode.startsWith('Small')
                    ? 44
                    : 60)
              : (widget.settings.viewMode.startsWith('Large')
                    ? 48
                    : widget.settings.viewMode.startsWith('Small')
                    ? 24
                    : 36),
          onDragging: (value) {
            if (mounted) {
              setState(() {
                folderDragging = value;
                draggedFolderPaths = value ? dragData.paths.toSet() : {};
                if (value) selected.add(e['path'] as String);
              });
            }
          },
          child: Opacity(
            opacity: draggedFolderPaths.contains(folderPath) ? .5 : 1,
            child: child,
          ),
        );
      }
      if (e['directory'] == true) {
        child = FolderDropTarget(
          path: folderPath,
          enabled: !loading && !movingFolder,
          onDrop: (source) => dropFolder(source, e),
          child: child,
        );
      }
    } else {
      child = SelectionHold(onHold: () => toggle(e['path']), child: child);
    }
    return KeyedSubtree(
      key: selectionKeys.putIfAbsent(e['path'] as String, () => GlobalKey()),
      child: child,
    );
  }

  double get gridIconSize => widget.settings.viewMode.startsWith('Large')
      ? 76
      : widget.settings.viewMode.startsWith('Small')
      ? 44
      : 60;

  double get gridFontSize => widget.settings.viewMode.startsWith('Small')
      ? 11
      : widget.settings.viewMode.startsWith('Large')
      ? 13
      : 12;

  double gridLabelHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(gridFontSize) * 1.2 * 2 + 4;

  Widget _grid(Json e) => Stack(
    children: [
      Positioned.fill(
        child: InkWell(
          onTap: () => open(e),
          child: Container(
            decoration: BoxDecoration(
              color: selected.contains(e['path'])
                  ? primaryBlue.withValues(alpha: .12)
                  : null,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(5),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    key: pickupIconKeys.putIfAbsent(
                      e['path'] as String,
                      GlobalKey.new,
                    ),
                    child: FileGlyph(e, size: gridIconSize),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: gridLabelHeight(context),
                  child: Text(
                    displayFileName(e['name'].toString()),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: gridFontSize,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontStyle: FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (selected.isNotEmpty)
        Positioned(
          top: 0,
          right: 0,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Transform.scale(
              scale: .75,
              transformHitTests: false,
              child: Checkbox(
                value: selected.contains(e['path']),
                onChanged: (_) => toggle(e['path']),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
    ],
  );
}
