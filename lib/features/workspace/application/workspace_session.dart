import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

class WorkspaceSwipe {
  final int fromId, toId;
  final double progress;
  const WorkspaceSwipe(this.fromId, this.toId, this.progress);
}

class ExplorerWindow {
  final int id;
  final String page;
  String path;
  final String? category, title;
  final bool recent, search;
  final Json? profile;
  final previewKey = GlobalKey();
  bool locked = false;
  bool split = false;
  String? url;
  Json? payload;
  ExplorerWindow(
    this.id,
    this.path, {
    this.page = 'files',
    this.category,
    this.title,
    this.recent = false,
    this.search = false,
    this.profile,
    this.url,
    this.payload,
  });
  IconData get icon => switch (page) {
    'apps' => Icons.android,
    'network' || 'ftp' || 'webdav' => Icons.dns_outlined,
    'web' => Icons.public,
    'downloads' => Icons.downloading_outlined,
    'lan' => Icons.computer_outlined,
    'bluetooth' => Icons.bluetooth,
    'netmanager' => Icons.wifi,
    'trash' => Icons.delete_outline,
    'analysis' => Icons.pie_chart_outline,
    'storage_analysis' => Icons.bar_chart_rounded,
    'analysis_results' => switch (category) {
      'large' => Icons.insert_drive_file_outlined,
      'recent' => Icons.history,
      'empty' => Icons.folder_off_outlined,
      _ => Icons.copy_all_outlined,
    },
    'archive' => Icons.folder_zip_outlined,
    _ =>
      profile != null
          ? Icons.dns_outlined
          : category != null
          ? categoryIcons[category] ?? Icons.folder_outlined
          : recent
          ? Icons.history
          : ExplorerWorkspaceSession.instance.volumeFor(path)?['removable'] ==
                true
          ? Icons.sd_storage_outlined
          : Icons.phone_android_outlined,
  };
  String get tabLabel =>
      page == 'files' && profile == null && category == null && !recent
      ? _storageLabel
      : label;
  String get _storageLabel {
    final volume = ExplorerWorkspaceSession.instance.volumeFor(path);
    return volume?['removable'] == true ? volume!['name'] as String : 'Device';
  }

  String get label => switch (page) {
    'analysis' => 'Storage Analyzer',
    'storage_analysis' => 'Folder Analysis',
    _ =>
      page == 'files' &&
              profile == null &&
              category == null &&
              !recent &&
              ExplorerWorkspaceSession.instance.volumeFor(path)?['path'] == path
          ? _storageLabel
          : title ?? baseName(path),
  };
}

class ExplorerWorkspaceSession extends ChangeNotifier {
  static final instance = ExplorerWorkspaceSession();
  final List<ExplorerWindow> windows = [];
  List<Json> volumes = [];
  List<Json> servers = [];
  final homePreviewKey = GlobalKey();
  final Map<int?, Uint8List> previews = {};
  final previewChanges = ValueNotifier<int>(0);
  late final Listenable windowChanges = Listenable.merge([
    this,
    previewChanges,
  ]);
  final Map<int, Future<void> Function()> pasteActions = {};
  final Map<int, void Function(String path, bool search)>
  localNavigationActions = {};
  final List<String> history = [];
  List<Json> defaults = [];
  Future<void> Function()? beforeSwitch;
  VoidCallback? onPermissionGranted, clearClipboard;
  List<String> Function()? clipboardItems;
  bool Function()? clipboardMove;
  void Function(List<Json>)? onSaveDefaults;
  void clipboardChanged() => notifyListeners();
  void setPreview(int? id, Uint8List bytes) {
    previews[id] = bytes;
    previewChanges.value++;
  }

  void remember(String path) {
    if (!path.startsWith('/') || !containsStoragePath(path)) return;
    history.remove(path);
    history.insert(0, path);
    if (history.length > 25) history.removeLast();
  }

  void closeOthers() {
    windows.removeWhere((w) => w.id != activeId && !w.locked && !w.split);
    previews.removeWhere(
      (id, _) => id != null && !windows.any((w) => w.id == id),
    );
    pasteActions.removeWhere((id, _) => !windows.any((w) => w.id == id));
    notifyListeners();
  }

  Json _defaultEntry(ExplorerWindow window) => {
    'path': window.path,
    'page': window.page,
    'category': window.category,
    'title': window.title,
    'recent': window.recent,
    if (window.url != null) 'url': window.url,
    if (window.profile != null)
      'profile': {...window.profile!}..remove('password'),
  };

  int? _defaultWindowId;

  bool isDefaultWindow(int? id) {
    final entry = defaults.lastOrNull;
    if (id == null) return entry == null || entry['kind'] == 'home';
    if (entry == null || entry['kind'] == 'home') return false;
    if (_defaultWindowId != null &&
        windows.any((w) => w.id == _defaultWindowId)) {
      return id == _defaultWindowId;
    }
    final matching = windows.where(
      (window) =>
          (entry['page'] ?? 'files') == window.page &&
          entry['path'] == window.path &&
          entry['category'] == window.category &&
          (entry['recent'] == true) == window.recent &&
          (entry['profile'] == null
              ? window.profile == null
              : window.profile != null &&
                    ['protocol', 'host', 'port', 'username', 'share'].every(
                      (key) =>
                          (entry['profile'] as Map)[key] ==
                          window.profile![key],
                    )),
    );
    return matching.lastOrNull?.id == id;
  }

  void setDefaultWindow(int? id) {
    final window = windows.where((w) => w.id == id).firstOrNull;
    if (id != null && window == null) return;
    _defaultWindowId = id;
    defaults = [
      {'kind': 'home'},
      if (window != null) _defaultEntry(window),
    ];
    onSaveDefaults?.call(defaults);
    notifyListeners();
  }

  void saveDefaults() {
    _defaultWindowId = null;
    defaults = [
      {'kind': 'home'},
      for (final w in windows.where((w) => w.profile == null))
        {
          'path': w.path,
          'page': w.page,
          'category': w.category,
          'title': w.title,
          'recent': w.recent,
        },
    ];
    onSaveDefaults?.call(defaults);
    notifyListeners();
  }

  final swipeMotion = ValueNotifier<WorkspaceSwipe?>(null);
  bool lastSwitchWasSwipe = false;

  int? activeId, previousActiveId, latestOpenedId;
  int _nextId = 0;
  String root = '/storage/emulated/0';
  String storagePath(String path) {
    if (path.startsWith('content:')) return path;
    if (path == '/sdcard' || path.startsWith('/sdcard/')) {
      final primary =
          volumes.where((v) => v['removable'] != true).firstOrNull?['path'] ??
          root;
      path = '$primary${path.substring(7)}';
    }
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }

  Json? volumeFor(String path) {
    path = storagePath(path);
    final roots = volumes.isEmpty
        ? <Json>[
            {'path': root, 'name': 'Device', 'removable': false},
          ]
        : volumes;
    return (List<Json>.of(roots)..sort(
          (a, b) => (b['path'] as String).length.compareTo(
            (a['path'] as String).length,
          ),
        ))
        .where((v) => path == v['path'] || path.startsWith('${v['path']}/'))
        .firstOrNull;
  }

  bool containsStoragePath(String path) =>
      path.startsWith('content:') || volumeFor(path) != null;
  List<(String, String)> breadcrumbsFor(String path) {
    path = storagePath(path);
    final volume = volumeFor(path);
    if (volume == null) return [(baseName(path), path)];
    var current = volume['path'] as String;
    final crumbs = <(String, String)>[
      (
        volume['removable'] == true ? volume['name'] as String : 'Device',
        current,
      ),
    ];
    for (final part
        in path
            .substring(current.length)
            .split('/')
            .where((p) => p.isNotEmpty)) {
      current = '$current/$part';
      crumbs.add((part, current));
    }
    return crumbs;
  }

  void Function(String page)? onTool;
  void Function(Json profile)? onServer;
  int get count => windows.length + 1;
  int get activeIndex =>
      activeId == null ? 0 : windows.indexWhere((w) => w.id == activeId) + 1;
  // Tab names are unique. Keep the last opened matching window and its state,
  // even if its folder or analysis path has changed since it was opened.
  bool _activateExisting(ExplorerWindow requested) {
    final name = requested.tabLabel.trim().toLowerCase();
    final matches = windows
        .where((window) => window.tabLabel.trim().toLowerCase() == name)
        .toList();
    if (matches.isEmpty) return false;
    final existing = matches.last;
    final removed = matches.take(matches.length - 1).map((w) => w.id).toSet();
    if (removed.isNotEmpty) {
      windows.removeWhere((w) => removed.contains(w.id));
      previews.removeWhere((id, _) => removed.contains(id));
      pasteActions.removeWhere((id, _) => removed.contains(id));
      localNavigationActions.removeWhere((id, _) => removed.contains(id));
      if (removed.contains(_defaultWindowId)) _defaultWindowId = existing.id;
      if (removed.contains(latestOpenedId)) latestOpenedId = existing.id;
      if (removed.contains(previousActiveId)) previousActiveId = null;
    }
    activate(existing.id);
    return true;
  }

  void open(
    String path, {
    String page = 'files',
    String? category,
    String? title,
    bool recent = false,
    bool search = false,
    Json? payload,
  }) {
    path = storagePath(path);
    if (!containsStoragePath(path)) return;
    // Local folders share one Home tab, even when opened from New or search.
    if (page == 'files' && category == null && !recent) {
      final homes = windows
          .where(
            (w) =>
                w.page == 'files' &&
                w.profile == null &&
                w.category == null &&
                !w.recent,
          )
          .toList();
      if (homes.isNotEmpty) {
        final home = homes.last;
        final removed = homes.take(homes.length - 1).map((w) => w.id).toSet();
        windows.removeWhere((w) => removed.contains(w.id));
        previews.removeWhere((id, _) => removed.contains(id));
        pasteActions.removeWhere((id, _) => removed.contains(id));
        localNavigationActions.removeWhere((id, _) => removed.contains(id));
        if (removed.contains(_defaultWindowId)) _defaultWindowId = home.id;
        home.path = path;
        localNavigationActions[home.id]?.call(path, search);
        remember(path);
        activate(home.id);
        return;
      }
    }
    final window = ExplorerWindow(
      _nextId + 1,
      path,
      page: page,
      category: category,
      title: title,
      recent: recent,
      search: search,
      payload: payload,
    );
    if (_activateExisting(window)) return;
    _nextId++;
    lastSwitchWasSwipe = false;
    beforeSwitch?.call();
    windows.add(window);
    latestOpenedId = window.id;
    if (window.profile == null && page == 'files') remember(path);
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void openPage(String page, {String? url}) {
    final window = ExplorerWindow(
      _nextId + 1,
      root,
      page: page,
      url: url,
      title: switch (page) {
        'apps' => 'APP',
        'network' => 'Network',
        'web' => 'Web',
        'downloads' => 'Download Manager',
        'lan' => 'LAN',
        'ftp' => 'FTP',
        'webdav' => 'WebDAV',
        'bluetooth' => 'Bluetooth',
        'netmanager' => 'Net Manager',
        'trash' => 'Recycle Bin',
        'analysis' => 'Storage Analyzer',
        'storage_analysis' => 'Folder Analysis',
        _ => page,
      },
    );
    if (_activateExisting(window)) return;
    _nextId++;
    lastSwitchWasSwipe = false;
    beforeSwitch?.call();
    windows.add(window);
    latestOpenedId = window.id;
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void openRemote(Json profile) {
    final window = ExplorerWindow(
      _nextId + 1,
      profile['path'] ?? '/',
      title: profile['name'] ?? profile['host'],
      profile: Map<String, dynamic>.of(profile),
    );
    if (_activateExisting(window)) return;
    _nextId++;
    lastSwitchWasSwipe = false;
    beforeSwitch?.call();
    windows.add(window);
    latestOpenedId = window.id;
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void activate(int? id, {bool fromSwipe = false}) {
    if (id != null && !windows.any((w) => w.id == id)) return;
    if (activeId != id) {
      lastSwitchWasSwipe = fromSwipe;
      if (!fromSwipe) beforeSwitch?.call();
      previousActiveId = activeId;
    }
    activeId = id;
    notifyListeners();
  }

  void setSplit(int id, bool enabled) {
    final window = windows.where((w) => w.id == id).firstOrNull;
    if (window == null ||
        window.page != 'files' ||
        window.profile != null ||
        window.category != null ||
        window.recent) {
      return;
    }
    if (window.split == enabled) return;
    window.split = enabled;
    notifyListeners();
  }

  void updatePath(int id, String path) {
    final index = windows.indexWhere((w) => w.id == id);
    if (index < 0 || windows[index].path == path) return;
    if (windows[index].profile == null) {
      path = storagePath(path);
      if (!containsStoragePath(path)) return;
    }
    windows[index].path = path;
    remember(path);
    notifyListeners();
  }

  void lock(int id) {
    final window = windows.firstWhere((w) => w.id == id);
    window.locked = !window.locked;
    notifyListeners();
  }

  void close(int id) {
    lastSwitchWasSwipe = false;
    final index = windows.indexWhere((w) => w.id == id);
    if (index < 0 || windows[index].locked || windows[index].split) return;
    windows.removeAt(index);
    previews.remove(id);
    pasteActions.remove(id);
    localNavigationActions.remove(id);
    if (activeId == id) activeId = windows.isEmpty ? null : windows.last.id;
    notifyListeners();
  }
}
