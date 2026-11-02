import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/core/utils/file_sort.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/editor/presentation/text_editor_page.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/gallery/presentation/image_viewer_page.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/dialogs/view_menu.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';
import 'package:yr_file_explorer/shared/widgets/file_glyph.dart';

class ArchivePage extends StatefulWidget {
  final String path;
  final AppSettings settings;
  final FileClipboard clipboard;
  final int? windowId;
  const ArchivePage({
    super.key,
    required this.path,
    required this.settings,
    required this.clipboard,
    this.windowId,
  });
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<Json> rows = [];
  final selected = <String>{};
  String prefix = '',
      password = '',
      charset = 'UTF-8',
      viewMode = 'Medium Icon',
      sort = 'Name';
  bool descending = false;
  bool loading = true, busy = false, grid = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  bool get isSevenZip => widget.path.toLowerCase().endsWith('.7z');

  Future<void> changePassword() async {
    final value = await askText(
      context,
      'Archive password',
      label: 'Password',
      secret: true,
    );
    if (value == null || !mounted) return;
    password = value;
    await load();
  }

  Json get args => {
    'path': widget.path,
    'prefix': prefix,
    'password': password,
    'charset': charset,
  };
  Future<void> load({bool background = false}) async {
    setState(() {
      if (!background) loading = true;
      error = null;
      selected.clear();
    });
    try {
      final result = await Native.rows('archiveList', args);
      if (mounted) {
        setState(() {
          rows = result;
          sortRows();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (isSevenZip &&
            password.isEmpty &&
            e.toString().toLowerCase().contains('password')) {
          final value = await askText(
            context,
            'Archive password',
            label: 'Password',
            secret: true,
          );
          if (!mounted) return;
          if (value != null && value.isNotEmpty) {
            password = value;
            await load();
            return;
          }
        }
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void sortRows() {
    rows = sortedFileEntries(rows, sort: sort, descending: descending);
  }

  Future<void> view() => showExplorerViewMenu(
    context,
    mode: viewMode,
    sort: sort,
    descending: descending,
    sorts: const ['Name', 'Size', 'Modified'],
    onChanged: (mode, nextSort, nextDescending) => setState(() {
      viewMode = mode;
      grid = mode.endsWith('Icon');
      sort = nextSort;
      descending = nextDescending;
      sortRows();
    }),
  );

  void back() {
    if (selected.isNotEmpty) {
      setState(() => selected.clear());
      return;
    }
    if (prefix.isNotEmpty) {
      final pieces = prefix.split('/')..removeWhere((s) => s.isEmpty);
      pieces.removeLast();
      prefix = pieces.isEmpty ? '' : '${pieces.join('/')}/';
      load();
    } else if (widget.windowId != null) {
      ExplorerWorkspaceSession.instance.activate(null);
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<T?> archiveRequest<T>(String method, Json values) async {
    try {
      return await Native.call<T>(method, values);
    } on PlatformException catch (error) {
      // Some 7z files encrypt content but leave their directory readable.
      if (!isSevenZip ||
          password.isNotEmpty ||
          !error.toString().toLowerCase().contains('password') ||
          !mounted) {
        rethrow;
      }
      final value = await askText(
        context,
        'Archive password',
        label: 'Password',
        secret: true,
      );
      if (value == null || value.isEmpty || !mounted) rethrow;
      password = value;
      return Native.call<T>(method, {...values, 'password': password});
    }
  }

  Future<bool> unlock(List<Json> entries) async {
    if (password.isNotEmpty || !entries.any((e) => e['encrypted'] == true)) {
      return true;
    }
    final value = await askText(
      context,
      'Archive password',
      label: 'Password',
      secret: true,
    );
    if (value == null) return false;
    password = value;
    return true;
  }

  Future<void> open(Json entry) async {
    if (selected.isNotEmpty) {
      toggle(entry);
      return;
    }
    if (entry['directory'] == true) {
      prefix = entry['path'];
      await load();
      return;
    }
    if (!await unlock([entry])) return;
    setState(() => busy = true);
    try {
      final file = (await archiveRequest<String>('archiveOpen', {
        ...args,
        'entry': entry['path'],
      }))!;
      if (!mounted) return;
      if (entry['category'] == 'Images') {
        await Navigator.push(
          context,
          ExplorerPageRoute<void>(
            builder: (_) => ImageViewer(path: file, canDelete: false),
          ),
        );
      } else if (RegExp(
        r'\.(txt|md|json|xml|csv|log|yaml|yml|ini|java|dart|js|css|html)$',
        caseSensitive: false,
      ).hasMatch(file)) {
        await Navigator.push(
          context,
          ExplorerPageRoute<void>(
            builder: (_) => TextEditor(path: file, readOnly: true),
          ),
        );
      } else {
        await Native.call('open', {'path': file});
      }
    } catch (e) {
      password = '';
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toggle(Json entry) => setState(() {
    selected.contains(entry['path'])
        ? selected.remove(entry['path'])
        : selected.add(entry['path']);
  });
  Future<void> extract() async {
    final picks = selected.isEmpty
        ? rows
        : rows.where((e) => selected.contains(e['path'])).toList();
    if (!await unlock(picks)) return;
    if (!mounted) return;
    final stem = archiveStem(baseName(widget.path));
    final destination = await askText(
      context,
      'Extract to',
      label: 'New destination folder',
      initial: '${parentPath(widget.path)}/$stem',
    );
    if (destination == null || destination.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await archiveRequest('archiveExtract', {
        ...args,
        'destination': destination,
        'entries': selected.isEmpty
            ? (prefix.isEmpty ? <String>[] : [prefix])
            : selected.toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Extracted to $destination'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () =>
                  ExplorerWorkspaceSession.instance.open(destination),
            ),
          ),
        );
        setState(() => selected.clear());
      }
    } catch (e) {
      password = '';
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copy() async {
    final picks = rows.where((e) => selected.contains(e['path'])).toList();
    if (picks.isEmpty || !await unlock(picks)) return;
    setState(() => busy = true);
    try {
      final files = <String>[];
      for (final e in picks) {
        files.add(
          (await archiveRequest<String>('archiveOpen', {
            ...args,
            'entry': e['path'],
          }))!,
        );
      }
      widget.clipboard.put(files, false);
      if (mounted) {
        setState(() => selected.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a folder and paste the extracted files.'),
          ),
        );
      }
    } catch (e) {
      password = '';
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseCharset() async {
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => ExplorerChoiceDialog(
        title: const Text('Charset'),
        children: [
          for (final name in [
            'UTF-8',
            'CP437',
            'GBK',
            'Big5',
            'Shift_JIS',
            'ISO-8859-1',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, name),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(name),
              ),
            ),
        ],
      ),
    );
    if (value != null) {
      charset = value;
      await load();
    }
  }

  List<(String, String)> get breadcrumbs {
    final crumbs = <(String, String)>[(baseName(widget.path), '')];
    var target = '';
    for (final part in prefix.split('/').where((p) => p.isNotEmpty)) {
      target = '$target$part/';
      crumbs.add((part, target));
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String title, VoidCallback onTap) =>
        ExplorerAction(icon: icon, label: title, onTap: busy ? () {} : onTap);
    return ExplorerPane(
      busy: busy,
      onActivate: () => load(background: true),
      settings: widget.settings,
      windowId: widget.windowId,
      selecting: selected.isNotEmpty,
      onSelectAll: () =>
          setState(() => selected.addAll(rows.map((e) => e['path'] as String))),
      onClearSelection: () => setState(() => selected.clear()),
      interceptBack: prefix.isNotEmpty,
      title: selected.isNotEmpty
          ? Text('${selected.length}/${rows.length}')
          : ExplorerBreadcrumbs(
              entries: breadcrumbs,
              onCurrent: () => showStorageLocations(context),
              onNavigate: (value) {
                prefix = value;
                load();
              },
            ),
      onBack: back,
      onTitle: () => showDialog<void>(
        context: context,
        builder: (dialog) => ExplorerDialog(
          title: const Text('Archive location'),
          content: SelectableText('${widget.path} / $prefix'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialog);
                prefix = '';
                load();
              },
              child: const Text('Archive root'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      actions: selected.isEmpty
          ? [
              if (isSevenZip)
                action(Icons.lock_outline, 'Password', changePassword)
              else
                action(Icons.translate, 'Charset', chooseCharset),
              action(Icons.unarchive_outlined, 'Extract', extract),
              action(Icons.refresh, 'Refresh', load),
              action(Icons.grid_view, 'View', view),
              action(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ]
          : [
              action(Icons.copy, 'Copy', copy),
              action(Icons.unarchive_outlined, 'Extract', extract),
              action(
                Icons.select_all,
                'Select all',
                () => setState(
                  () => selected.addAll(rows.map((e) => e['path'] as String)),
                ),
              ),
              action(
                Icons.deselect,
                'Clear',
                () => setState(() => selected.clear()),
              ),
              action(
                Icons.filter_none,
                'Windows',
                () => showExplorerWindows(context),
              ),
            ],
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? EmptyState(
                    title: 'Cannot open archive',
                    message: error!,
                    action: FilledButton(
                      onPressed: load,
                      child: const Text('Retry'),
                    ),
                  )
                : rows.isEmpty
                ? const EmptyState(
                    title: 'Empty archive folder',
                    message: 'There are no entries in this folder.',
                  )
                : grid
                ? GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      10,
                      10,
                      ExplorerBottomBar.contentBottomPadding(context),
                    ),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: explorerGridColumns(viewMode),
                      childAspectRatio: .82,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final e = rows[i];
                      return InkWell(
                        onTap: () => open(e),
                        onLongPress: () => toggle(e),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected.contains(e['path'])
                                ? primaryBlue.withValues(alpha: .12)
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              selected.contains(e['path'])
                                  ? const Icon(
                                      Icons.check_circle,
                                      size: 42,
                                      color: primaryBlue,
                                    )
                                  : FileGlyph(
                                      e,
                                      size: explorerGlyphSize(viewMode),
                                    ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 32,
                                child: Text(
                                  e['name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: ExplorerBottomBar.contentBottomPadding(context),
                    ),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final e = rows[i];
                      return ListTile(
                        selected: selected.contains(e['path']),
                        dense: viewMode.startsWith('Small'),
                        leading: selected.contains(e['path'])
                            ? const Icon(Icons.check_circle, color: primaryBlue)
                            : FileGlyph(e),
                        title: Text(e['name']),
                        subtitle: viewMode.endsWith('Detail')
                            ? Text(sizeLabel(e['size']))
                            : null,
                        onTap: () => open(e),
                        onLongPress: () => toggle(e),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
