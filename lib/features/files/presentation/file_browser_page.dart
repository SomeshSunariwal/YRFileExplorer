import 'package:yr_file_explorer/features/archives/presentation/dialogs/create_archive_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_selection_header.dart';

import 'widgets/folder_drag_drop.dart';

import 'package:yr_file_explorer/shared/dialogs/operation_progress_dialog.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_search_header.dart';
import 'package:flutter/material.dart';
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
import 'package:yr_file_explorer/features/editor/presentation/text_editor_page.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/gallery/presentation/image_viewer_page.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/segmented_tabs.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
import 'package:yr_file_explorer/shared/widgets/drag_selection_region.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class FileBrowser extends StatefulWidget {
  final String path;
  final AppSettings settings;
  final FileClipboard clipboard;
  final String? category, title;
  final bool recent;
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
    this.initialSearch = false,
    this.windowId,
  });
  @override
  State<FileBrowser> createState() => _FileBrowserState();
}

class _FileBrowserState extends State<FileBrowser> with WidgetsBindingObserver {
  late String path;
  late bool previousHidden, previousFolderSizes;
  List<Json> entries = [];
  List<Json>? _sortedEntries;
  String? _cachedSort;
  bool? _cachedDescending;
  final selected = <String>{};
  final selectionKeys = <String, GlobalKey>{};
  final filesScroll = ScrollController();
  final selectionMenuAnchor = GlobalKey();
  final history = <String>[];
  final future = <String>[];
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
  final searchController = TextEditingController();
  bool get document => path.startsWith('content:');
  bool get virtual =>
      widget.category != null || widget.recent || query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    path = ExplorerWorkspaceSession.instance.storagePath(widget.path);
    previousHidden = widget.settings.hidden;
    previousFolderSizes = widget.settings.folderSizes;
    widget.settings.addListener(settingsChanged);
    searching = widget.initialSearch;
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
    Native.call('cancelAnalysis', {'id': scanId});
    setState(() {
      if (!background) loading = true;
      refreshing = background;
      calculating = false;
      error = null;
      selected.clear();
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
              'hidden': widget.settings.hidden,
            })
          : await Native.rows('list', {
              'path': path,
              'hidden': widget.settings.hidden,
            });
      if (widget.recent) {
        rows.removeWhere((e) => e['directory'] == true);
        rows.sort(
          (a, b) => (b['modified'] as num).compareTo(a['modified'] as num),
        );
        rows = rows.take(200).toList();
      }
      if (!mounted || version != generation) return;
      setState(() {
        entries = rows;
        _sortedEntries = null;
        final paths = rows.map((row) => row['path']).toSet();
        selectionKeys.removeWhere((path, _) => !paths.contains(path));
        selected.retainAll(paths);
        loading = false;
        refreshing = false;
      });
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

  void submitSearch(String value) {
    if (value.trim().isEmpty) return;
    setState(() {
      query = value.trim();
      deepSearch = false;
      searching = false;
    });
    FocusScope.of(context).unfocus();
    load();
  }

  void closeSearch() {
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
    onSubmitted: submitSearch,
    hint: searchType == 'All files' ? 'Search files' : searchType,
    leading: PopupMenuButton<String>(
      tooltip: 'Search type',
      initialValue: searchType,
      onSelected: (value) => setState(() => searchType = value),
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

  void openLocation(String next, bool startSearch) {
    final hadQuery = query.isNotEmpty || deepSearch;
    searching = startSearch;
    query = '';
    deepSearch = false;
    searchController.clear();
    selected.clear();
    if (next != path) {
      navigate(next);
    } else {
      setState(() {});
      if (hadQuery) load();
    }
  }

  void navigate(String next) {
    final session = ExplorerWorkspaceSession.instance;
    next = session.storagePath(next);
    if (!session.containsStoragePath(next)) return;
    if (next == path) return;
    // Retain one return sequence when breadcrumbs revisit the same folders.
    // Repeating sdcard -> Download -> sdcard must not grow the stack forever.
    final previousVisit = history.lastIndexOf(path);
    if (previousVisit >= 0) {
      history.removeRange(previousVisit, history.length);
    }
    history.add(path);
    future.clear();
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
      future.add(path);
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
      future.clear();
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
      final p = e['path'] as String;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (!p.startsWith('content:') &&
          e['category'] == 'Images' &&
          !p.toLowerCase().endsWith('.svg')) {
        await Navigator.push(
          context,
          ExplorerPageRoute<void>(
            builder: (_) => ImageViewer(
              path: p,
              recycle: widget.settings.recycle,
              images: sorted
                  .where(
                    (row) =>
                        row['category'] == 'Images' &&
                        !row['path'].toString().startsWith('content:') &&
                        !row['path'].toString().endsWith('.svg'),
                  )
                  .map((row) => row['path'] as String)
                  .toList(),
            ),
          ),
        );
        await load();
      } else if (!p.startsWith('content:') &&
          RegExp(
            r'\.(txt|md|json|xml|html|csv|log|dart|java|yaml|yml|ini|sh|css|js)$',
            caseSensitive: false,
          ).hasMatch(p)) {
        await Navigator.push(
          context,
          ExplorerPageRoute<void>(builder: (_) => TextEditor(path: p)),
        );
        await load();
      } else if (isSupportedArchive(p)) {
        if (widget.windowId != null) {
          ExplorerWorkspaceSession.instance.open(
            p,
            page: 'archive',
            title: baseName(p),
          );
        } else {
          await Navigator.push(
            context,
            ExplorerPageRoute<void>(
              builder: (_) => ArchivePage(
                path: p,
                settings: widget.settings,
                clipboard: widget.clipboard,
              ),
            ),
          );
        }
      } else {
        await Native.call('open', {'path': p});
      }
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
      await load();
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
        source.paths.length == 1 ? 'Move folder' : 'Move folders',
        source.paths.length == 1
            ? 'Move "${source.name}" into "${destination['name']}"?'
            : 'Move ${source.paths.length} selected folders into "${destination['name']}"?',
        action: 'Move',
      );
      if (!accepted || !mounted) return;
      await busy(
        source.paths.length == 1 ? 'Moving folder…' : 'Moving folders…',
        () => Native.call('paste', {
          'path': target,
          'sources': dragRootPaths(source.paths),
          'move': true,
          'preflight': true,
        }),
      );
      if (!mounted) return;
      setState(() => selected.removeAll(source.paths));
      await load();
    } catch (error) {
      if (mounted) {
        showError(context, error);
        await load();
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
            final theme = Theme.of(context);
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  backgroundColor: theme.colorScheme.surface,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  content: Row(
                    children: [
                      Icon(
                        removing ? Icons.star_outline : Icons.star_rounded,
                        color: primaryBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          removing
                              ? 'Removed from Favorites'
                              : paths.length == 1
                              ? 'Folder added to Favorites'
                              : '${paths.length} items added to Favorites',
                          style: TextStyle(color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Saved to Downloads')));
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
          'Properties',
          'Copy path',
        ];
  @override
  Widget build(BuildContext context) {
    final rows = sorted;
    final picks = entries.where((e) => selected.contains(e['path'])).toList();

    return PopScope(
      canPop: widget.windowId != null
          ? ExplorerWorkspaceSession.instance.activeId != widget.windowId
          : history.isEmpty && selected.isEmpty && !searching && query.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            (widget.windowId == null ||
                ExplorerWorkspaceSession.instance.activeId ==
                    widget.windowId)) {
          back();
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: explorerChrome(context),
          foregroundColor: explorerForeground(context),
          toolbarHeight: explorerTabHeight,
          leadingWidth: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: ReferenceTabs(
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
                    onClose: () {
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
        body: ExplorerProgressOverlay(
          active: refreshing || calculating,
          child: WorkspaceBodySlide(
            allowTabSwipe: selected.isEmpty && !folderDragging,
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
                                  ? GridView.builder(
                                      controller: filesScroll,
                                      physics: selected.isNotEmpty
                                          ? const NeverScrollableScrollPhysics()
                                          : null,
                                      padding: EdgeInsets.fromLTRB(
                                        12,
                                        14,
                                        12,
                                        ExplorerBottomBar.contentBottomPadding(
                                          context,
                                        ),
                                      ),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount:
                                                widget.settings.viewMode
                                                    .startsWith('Large')
                                                ? 3
                                                : widget.settings.viewMode
                                                      .startsWith('Small')
                                                ? 5
                                                : 4,
                                            childAspectRatio: .84,
                                            crossAxisSpacing: 8,
                                            mainAxisSpacing: 8,
                                          ),
                                      itemCount: rows.length,
                                      itemBuilder: (_, i) => selectionItem(
                                        rows[i],
                                        _grid(rows[i]),
                                      ),
                                    )
                                  : ListView.builder(
                                      controller: filesScroll,
                                      physics: selected.isNotEmpty
                                          ? const NeverScrollableScrollPhysics()
                                          : null,
                                      padding: EdgeInsets.only(
                                        bottom:
                                            ExplorerBottomBar.contentBottomPadding(
                                              context,
                                            ),
                                      ),
                                      itemCount: rows.length,
                                      itemBuilder: (_, i) =>
                                          selectionItem(rows[i], _row(rows[i])),
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
                        child: const Text('File not found? Try deeper search'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: ExplorerBottomBar(
          child: selected.isNotEmpty
              ? Row(
                  children: [
                    _tool(Icons.copy, 'Copy', () => action('Copy', picks)),
                    _tool(Icons.content_cut, 'Cut', () => action('Cut', picks)),
                    _tool(
                      Icons.delete_outline,
                      'Delete',
                      () => action('Delete', picks),
                    ),
                    _tool(
                      Icons.edit_outlined,
                      'Rename',
                      () => action('Rename', picks),
                    ),
                    ExplorerAction(
                      key: selectionMenuAnchor,
                      icon: Icons.more_horiz,
                      label: 'More',
                      onTap: () => showSelectionMenu(picks),
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
                        color: explorerForeground(context)
                            .withValues(alpha: .7),
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
                    _tool(
                      Icons.refresh,
                      'Refresh',
                      () => load(background: true),
                    ),
                    _tool(Icons.grid_view, 'View', showViewMenu),
                    _tool(Icons.filter_none, 'Windows', showWindows),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) =>
      ExplorerAction(icon: icon, label: label, onTap: onTap);

  Future<String?> chooseDirectory() {
    var destination = path.startsWith('/') ? path : '/storage/emulated/0';
    Future<List<Json>> listing = Native.rows('list', {
      'path': destination,
      'hidden': widget.settings.hidden,
    });
    return showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => ExplorerDialog(
          title: const Text('Select folder'),
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          content: SizedBox(
            width: 320,
            height: 360,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Parent folder',
                      onPressed:
                          !ExplorerWorkspaceSession.instance
                              .containsStoragePath(parentPath(destination))
                          ? null
                          : () => update(() {
                              destination = parentPath(destination);
                              listing = Native.rows('list', {
                                'path': destination,
                                'hidden': widget.settings.hidden,
                              });
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    Expanded(
                      child: Text(
                        destination,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: FutureBuilder<List<Json>>(
                    future: listing,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('${snapshot.error}'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final folders = snapshot.data!
                          .where((entry) => entry['directory'] == true)
                          .toList();
                      return ListView(
                        children: [
                          for (final folder in folders)
                            ListTile(
                              leading: FileGlyph(folder, size: 32),
                              title: Text(folder['name']),
                              onTap: () => update(() {
                                destination = folder['path'];
                                listing = Native.rows('list', {
                                  'path': destination,
                                  'hidden': widget.settings.hidden,
                                });
                              }),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, destination),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showNewMenu() async {
    final directory = await showDialog<bool>(
      context: context,
      builder: (dialog) => ExplorerChoiceDialog(
        title: const Center(child: Text('New')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('File'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Folder'),
            ),
          ),
        ],
      ),
    );
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
        : ['Favorite', 'Share', 'Copy to', 'Move to', 'Compress', 'Copy path'];
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
    return '${sizeLabel(e['size'])}  ·  ${dateLabel(e['modified'] ?? 0)}';
  }

  Widget _row(Json e) => ListTile(
    dense: widget.settings.viewMode.startsWith('Small'),
    selected: selected.contains(e['path']),
    selectedTileColor: primaryBlue.withValues(alpha: .08),
    leading: selected.contains(e['path'])
        ? const SizedBox(
            width: 38,
            child: Icon(Icons.check_circle, color: primaryBlue, size: 29),
          )
        : FileGlyph(
            e,
            size: widget.settings.viewMode.startsWith('Large')
                ? 48
                : widget.settings.viewMode.startsWith('Small')
                ? 24
                : 36,
          ),
    title: Text(
      displayFileName(e['name'].toString()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14),
    ),
    subtitle: widget.settings.viewMode.contains('Detail')
        ? Text(
            virtual ? '${subtitle(e)}\n${e['path']}' : subtitle(e),
            maxLines: virtual ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          )
        : null,
    trailing: selected.isNotEmpty
        ? Transform.scale(
            scale: .75,
            transformHitTests: false,
            child: Checkbox(
              value: selected.contains(e['path']),
              onChanged: (_) => toggle(e['path']),
            ),
          )
        : PopupMenuButton<String>(
            tooltip: 'File actions',
            onSelected: (v) => action(v, [e]),
            itemBuilder: (_) =>
                actions(e)
                    .map((a) => PopupMenuItem(value: a, child: Text(a)))
                    .toList(),
          ),
    onLongPress: canDragFolder(e) ? null : () => toggle(e['path']),
    onTap: () => open(e),
  );
  bool canDragFolder(Json entry) =>
      entry['directory'] == true &&
      !document &&
      (entry['path'] as String).startsWith('/');

  FolderDragData folderDragData(Json entry) {
    final session = ExplorerWorkspaceSession.instance;
    final path = session.storagePath(entry['path']);
    final paths = <String>{path};
    for (final item in entries) {
      if (selected.contains(item['path']) && canDragFolder(item)) {
        paths.add(session.storagePath(item['path']));
      }
    }
    return FolderDragData(path, entry['name'], paths: paths.toList());
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
    final localFolder = canDragFolder(e);
    if (localFolder) {
      final folderPath = ExplorerWorkspaceSession.instance.storagePath(
        e['path'],
      );
      if (!loading && !movingFolder) {
        final dragData = folderDragData(e);
        child = FolderDraggable(
          data: dragData,
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
      child = FolderDropTarget(
        path: folderPath,
        enabled: !loading && !movingFolder,
        onDrop: (source) => dropFolder(source, e),
        child: child,
      );
    }
    return KeyedSubtree(
      key: selectionKeys.putIfAbsent(e['path'] as String, () => GlobalKey()),
      child: child,
    );
  }

  Widget _grid(Json e) => Stack(
    children: [
      Positioned.fill(
        child: InkWell(
          onLongPress: canDragFolder(e) ? null : () => toggle(e['path']),
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
                    child: FileGlyph(
                      e,
                      size: widget.settings.viewMode.startsWith('Large')
                          ? 76
                          : widget.settings.viewMode.startsWith('Small')
                          ? 44
                          : 60,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: widget.settings.viewMode.startsWith('Small')
                      ? 32
                      : 36,
                  child: Text(
                    displayFileName(e['name'].toString()),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: widget.settings.viewMode.startsWith('Small')
                          ? 11
                          : widget.settings.viewMode.startsWith('Large')
                          ? 13
                          : 12,
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
