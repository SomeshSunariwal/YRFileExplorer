import 'package:flutter/material.dart';

import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_navigation_header.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/settings/presentation/settings_page.dart';
import 'package:yr_file_explorer/features/storage/presentation/dialogs/storage_locations_dialog.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/segmented_tabs.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class ExplorerHome extends StatefulWidget {
  final AppSettings settings;
  final FileClipboard clipboard;
  const ExplorerHome({
    super.key,
    required this.settings,
    required this.clipboard,
  });
  @override
  State<ExplorerHome> createState() => _ExplorerHomeState();
}

class _ExplorerHomeState extends State<ExplorerHome>
    with WidgetsBindingObserver {
  FileClipboard get clipboard => widget.clipboard;
  List<Json> volumes = [];
  Map<String, dynamic> categoryCounts = {};
  int countGeneration = 0;
  bool permission = false, loading = true;
  String? error;
  String get primary =>
      volumes.isEmpty ? '/storage/emulated/0' : volumes.first['path'];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    try {
      final allowed = await Native.call<bool>('permission') ?? false;
      final storage = await Native.rows('volumes');
      ExplorerWorkspaceSession.instance.volumes = storage;
      if (storage.isNotEmpty) {
        ExplorerWorkspaceSession.instance.root = storage.first['path'];
      }
      if (mounted) {
        setState(() {
          permission = allowed;
          volumes = storage;
          loading = false;
          error = null;
        });
        if (allowed) {
          loadCategoryCounts();
          ExplorerWorkspaceSession.instance.onPermissionGranted?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> loadCategoryCounts() async {
    final request = ++countGeneration;
    try {
      final counts = await Native.call<Map>('categoryCounts', {
        'path': primary,
      });
      if (mounted && request == countGeneration && counts != null) {
        setState(() => categoryCounts = Map<String, dynamic>.from(counts));
        try {
          final downloaded = await Native.rows('list', {
            'path': '$primary/Download',
            'hidden': widget.settings.hidden,
          });
          if (mounted && request == countGeneration) {
            setState(
              () => categoryCounts['Download'] = downloaded
                  .where((e) => e['directory'] != true)
                  .length,
            );
          }
        } catch (_) {
          if (mounted && request == countGeneration) {
            setState(() => categoryCounts['Download'] = 0);
          }
        }
      }
    } catch (_) {
      /* Keep unavailable counts as a dash. */
    }
  }

  Future<void> push(Widget page) async {
    await Navigator.push(
      context,
      ExplorerPageRoute<void>(builder: (_) => page),
    );
  }

  void browse(
    String path, {
    String? category,
    bool recent = false,
    String? title,
  }) => ExplorerWorkspaceSession.instance.open(
    path,
    category: category,
    recent: recent,
    title: title,
  );
  void analyze([String? path]) => sessionTool('analysis');
  void sessionTool(String page) =>
      ExplorerWorkspaceSession.instance.onTool?.call(page);
  void settings() => push(SettingsPage(settings: widget.settings));
  void drawerAction(VoidCallback action) {
    Navigator.pop(context);
    action();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    appBar: AppBar(
      backgroundColor: explorerChrome(context),
      toolbarHeight: explorerTabHeight,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: ReferenceTabs(
        local: false,
        onHome: () {},
        onLocal: () => browse(primary),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(explorerHeaderHeight),
        child: ExplorerNavigationHeader(
          homepage: true,
          location: InkWell(
            onTap: () => showStorageLocations(context),
            borderRadius: BorderRadius.circular(40),
            child: const ExplorerLocationPill(
              child: Center(child: Text('Homepage')),
            ),
          ),
        ),
      ),
    ),
    body: WorkspaceBodySlide(
      child: SafeArea(
        top: false,
        bottom: false,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    ExplorerBottomBar.contentBottomPadding(context),
                  ),
                  children: [
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(error!),
                      ),
                    if (!permission)
                      ListTile(
                        title: const Text('Storage permission'),
                        trailing: TextButton(
                          onPressed: () => Native.call('requestPermission'),
                          child: const Text('Allow'),
                        ),
                      ),
                    _panel(
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: GridView.count(
                              shrinkWrap: true,
                              primary: false,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              crossAxisCount: 6,
                              mainAxisExtent:
                                  (68 +
                                          MediaQuery.textScalerOf(context)
                                                  .scale(12) *
                                              2)
                                      .clamp(92.0, 192.0),
                              children: [
                                for (final e in [
                                  ('Images', 'image'),
                                  ('Music', 'music'),
                                  ('Movies', 'video'),
                                  ('Documents', 'document'),
                                  ('Compressed', 'Archives'),
                                  ('APP', 'app'),
                                  ('Download', 'download'),
                                  ('Recent', 'history'),
                                ])
                                  _entry(e.$1, e.$2, () {
                                    if (e.$1 == 'Download') {
                                      browse('$primary/Download');
                                    } else if (e.$1 == 'Recent') {
                                      browse(
                                        primary,
                                        recent: true,
                                        title: 'Recent',
                                      );
                                    } else if (e.$1 == 'APP') {
                                      sessionTool('apps');
                                    } else {
                                      browse(
                                        primary,
                                        category: e.$1 == 'Movies'
                                            ? 'Videos'
                                            : e.$1 == 'Compressed'
                                            ? 'Archives'
                                            : e.$1,
                                        title: e.$1,
                                      );
                                    }
                                  }),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          for (final v in volumes) _storage(v),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _shortcutSection('Tools', [
                      _bookmark(
                        'SD Card Analyst',
                        Icons.pie_chart_outline,
                        () => sessionTool('analysis'),
                      ),
                      _bookmark(
                        'System Manager',
                        Icons.apps,
                        () => sessionTool('apps'),
                      ),
                      _bookmark(
                        'Recycle Bin',
                        Icons.delete_outline,
                        () => sessionTool('trash'),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _shortcutSection('Network', [
                      _bookmark(
                        'Network',
                        Icons.dns_outlined,
                        () => sessionTool('network'),
                      ),
                      _bookmark(
                        'LAN',
                        Icons.computer_outlined,
                        () => sessionTool('lan'),
                      ),
                      _bookmark(
                        'FTP',
                        Icons.folder_shared_outlined,
                        () => sessionTool('ftp'),
                      ),
                      _bookmark(
                        'WebDAV',
                        Icons.web_asset_outlined,
                        () => sessionTool('webdav'),
                      ),
                      _bookmark(
                        'Bluetooth',
                        Icons.bluetooth,
                        () => sessionTool('bluetooth'),
                      ),
                      _bookmark(
                        'Download Manager',
                        Icons.downloading_outlined,
                        () => sessionTool('downloads'),
                      ),
                      _bookmark(
                        'Net Manager',
                        Icons.wifi,
                        () => sessionTool('netmanager'),
                      ),
                    ]),
                  ],
                ),
              ),
      ),
    ),
    bottomNavigationBar: ExplorerBottomBar(
      child: Row(
        children: [
          _bottom('toolbar_new', 'New', _newFolder),
          _bottom('toolbar_search', 'Search', _search),
          _bottom('toolbar_refresh', 'Refresh', refresh),
          _bottom('toolbar_setting', 'Settings', settings),
          _bottom('toolbar_windows', 'Windows', _showWindows),
        ],
      ),
    ),
  );
  Widget _panel(Widget child) => AnimatedContainer(
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeInOutCubic,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: widget.settings.dark
            ? const Color(0xff484848)
            : const Color(0xffe3eaf2),
      ),
      color: Theme.of(context).colorScheme.surface,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
  Widget _shortcutSection(
    String title,
    List<Widget> entries, {
    bool initiallyExpanded = false,
  }) => _panel(
    ExpansionTile(
      key: PageStorageKey('home-section-$title'),
      initiallyExpanded: initiallyExpanded,
      minTileHeight: 44,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      children: [
        GridView.builder(
          key: PageStorageKey('home-section-grid-$title'),
          primary: false,
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 56,
          ),
          itemCount: entries.length,
          itemBuilder: (_, index) => entries[index],
        ),
      ],
    ),
  );

  Widget _bookmark(String title, IconData icon, VoidCallback tap) => InkWell(
    onTap: tap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          SizedBox(width: 24, child: Icon(icon, size: 20, color: primaryBlue)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
  void _search() =>
      ExplorerWorkspaceSession.instance.open(primary, search: true);
  void _showWindows() => showExplorerWindows(context);
  Future<void> _newFolder() async {
    final directory = await showDialog<bool>(
      context: context,
      builder: (dialog) => SimpleDialog(
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
    if (directory == null || !mounted) return;
    final name = await askText(context, directory ? 'New folder' : 'New file');
    if (name == null || name.trim().isEmpty) return;
    try {
      await Native.call('create', {
        'path': primary,
        'name': name,
        'directory': directory,
      });
      await refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _entry(String title, String icon, VoidCallback tap) => InkWell(
    onTap: tap,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: primaryBlue.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            title == 'Download'
                ? Icons.download_outlined
                : title == 'Recent'
                ? Icons.history
                : categoryIcons[title == 'Movies'
                          ? 'Videos'
                          : title == 'Compressed'
                          ? 'Archives'
                          : title] ??
                      Icons.android_rounded,
            color: primaryBlue,
            size: 22,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (title == 'Recent')
          const SizedBox(height: 14)
        else
          Text(
            '${categoryCounts[title == 'Movies'
                    ? 'Videos'
                    : title == 'Compressed'
                    ? 'Archives'
                    : title] ?? '—'}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
      ],
    ),
  );
  Widget _bottom(String icon, String title, VoidCallback tap) => ExplorerAction(
    icon: switch (title) {
      'New' => Icons.add,
      'Search' => Icons.search,
      'Refresh' => Icons.refresh,
      'Settings' => Icons.settings_outlined,
      _ => Icons.filter_none,
    },
    label: title,
    onTap: tap,
  );
  Widget _storage(Json v) {
    final total = (v['total'] as num?) ?? 0;
    final used = total - ((v['free'] as num?) ?? 0);
    return InkWell(
      onTap: () => browse(v['path']),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primaryBlue.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.sd_storage_outlined,
                color: primaryBlue,
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v['removable'] == true ? v['name'] : 'sdcard',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0
                          ? (used / total).clamp(0, 1).toDouble()
                          : 0,
                      minHeight: 5,
                      color: primaryBlue,
                      backgroundColor: primaryBlue.withValues(alpha: .09),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        sizeLabel(used),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff7c8da1),
                        ),
                      ),
                      Text(
                        sizeLabel(total),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff7c8da1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xff91a0b2)),
          ],
        ),
      ),
    );
  }
}
