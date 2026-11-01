import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

class ExplorerWindow {
  final int id;
  final String page;
  String path;
  final String? category, title;
  final bool recent, search;
  final Json? profile;
  final previewKey = GlobalKey();
  bool locked = false;
  ExplorerWindow(
    this.id,
    this.path, {
    this.page = 'files',
    this.category,
    this.title,
    this.recent = false,
    this.search = false,
    this.profile,
  });
  IconData get icon => switch (page) {
    'apps' => Icons.android,
    'network' || 'ftp' || 'webdav' => Icons.dns_outlined,
    'lan' => Icons.computer_outlined,
    'bluetooth' => Icons.bluetooth,
    'netmanager' => Icons.wifi,
    'trash' => Icons.delete_outline,
    'analysis' => Icons.pie_chart_outline,
    'archive' => Icons.folder_zip_outlined,
    _ =>
      profile != null
          ? Icons.dns_outlined
          : category != null
          ? categoryIcons[category] ?? Icons.folder_outlined
          : recent
          ? Icons.history
          : Icons.home_outlined,
  };
  String get tabLabel =>
      page == 'files' && profile == null && category == null && !recent
      ? 'Home'
      : label;
  String get label =>
      title ?? (path == '/storage/emulated/0' ? 'Home' : baseName(path));
}

class ExplorerWorkspaceSession extends ChangeNotifier {
  static final instance = ExplorerWorkspaceSession();
  final List<ExplorerWindow> windows = [];
  List<Json> volumes = [];
  List<Json> servers = [];
  final homePreviewKey = GlobalKey();
  final Map<int?, Uint8List> previews = {};
  final Map<int, Future<void> Function()> pasteActions = {};
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
    notifyListeners();
  }

  void remember(String path) {
    if (!path.startsWith('/') || !containsStoragePath(path)) return;
    history.remove(path);
    history.insert(0, path);
    if (history.length > 25) history.removeLast();
  }

  void closeOthers() {
    windows.removeWhere((w) => w.id != activeId && !w.locked);
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
          (entry['recent'] == true) == window.recent,
    );
    return matching.lastOrNull?.id == id;
  }

  void setDefaultWindow(int? id) {
    final window = windows.where((w) => w.id == id).firstOrNull;
    if (id != null && (window == null || window.profile != null)) return;
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
            {'path': root, 'name': 'sdcard', 'removable': false},
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
        volume['removable'] == true ? volume['name'] as String : 'sdcard',
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
  void open(
    String path, {
    String page = 'files',
    String? category,
    String? title,
    bool recent = false,
    bool search = false,
    bool reuse = true,
  }) {
    path = storagePath(path);
    if (!containsStoragePath(path)) return;
    if (reuse) {
      for (final window in windows) {
        if (window.page == page &&
            window.profile == null &&
            window.path == path &&
            window.category == category &&
            window.recent == recent &&
            window.search == search) {
          activate(window.id);
          return;
        }
      }
    }
    final window = ExplorerWindow(
      ++_nextId,
      path,
      page: page,
      category: category,
      title: title,
      recent: recent,
      search: search,
    );
    beforeSwitch?.call();
    windows.add(window);
    latestOpenedId = window.id;
    if (window.profile == null && page == 'files') remember(path);
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void openPage(String page, {bool reuse = true}) {
    for (final window in windows) {
      if (reuse && window.page == page) {
        activate(window.id);
        return;
      }
    }
    beforeSwitch?.call();
    final window = ExplorerWindow(
      ++_nextId,
      root,
      page: page,
      title: switch (page) {
        'apps' => 'APP',
        'network' => 'Network',
        'lan' => 'LAN',
        'ftp' => 'FTP',
        'webdav' => 'WebDAV',
        'bluetooth' => 'Bluetooth',
        'netmanager' => 'Net Manager',
        'trash' => 'Recycle Bin',
        'analysis' => 'SD Card Analyst',
        _ => page,
      },
    );
    windows.add(window);
    latestOpenedId = window.id;
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void openRemote(Json profile) {
    final window = ExplorerWindow(
      ++_nextId,
      profile['path'] ?? '/',
      title: profile['name'] ?? profile['host'],
      profile: Map<String, dynamic>.of(profile),
    );
    beforeSwitch?.call();
    windows.add(window);
    latestOpenedId = window.id;
    previousActiveId = activeId;
    activeId = window.id;
    notifyListeners();
  }

  void activate(int? id) {
    if (id != null && !windows.any((w) => w.id == id)) return;
    if (activeId != id) {
      beforeSwitch?.call();
      previousActiveId = activeId;
    }
    activeId = id;
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
    final index = windows.indexWhere((w) => w.id == id);
    if (index < 0 || windows[index].locked) return;
    windows.removeAt(index);
    previews.remove(id);
    pasteActions.remove(id);
    if (activeId == id) activeId = windows.isEmpty ? null : windows.last.id;
    notifyListeners();
  }
}
