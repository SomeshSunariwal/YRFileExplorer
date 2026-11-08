import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';

const _deviceVolume = {
  'path': '/storage/emulated/0',
  'name': 'Device',
  'primary': true,
};

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
  final contentKey = GlobalKey();
  bool split = false;
  String? pendingSelection;
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
  bool get isLocalBrowser =>
      page == 'files' && profile == null && category == null && !recent;
  IconData get icon => switch (page) {
    'private' => Icons.lock_outline,
    'sharing' => Icons.wifi_tethering_rounded,
    'sharing_history' => Icons.swap_horiz_rounded,
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
          : ExplorerWorkspaceSession.instance.volumeFor(path)?['primary'] ==
                false
          ? Icons.sd_storage_outlined
          : Icons.phone_android_outlined,
  };
  String get tabLabel => isLocalBrowser ? _storageLabel : label;
  String get _storageLabel {
    final volume = ExplorerWorkspaceSession.instance.volumeFor(path);
    return volume?['primary'] == false ? volume!['name'] as String : 'Device';
  }

  String get label => switch (page) {
    'analysis' => 'Storage Analyzer',
    'storage_analysis' => 'Folder Analysis',
    'sharing' => 'Sharing',
    'sharing_history' => 'Sharing History',
    _ =>
      isLocalBrowser &&
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
    _removeWindows({
      for (final w in windows)
        if (w.id != activeId && !w.split) w.id,
    });
    notifyListeners();
  }

  void _removeWindows(Set<int> ids, {int? replacementId}) {
    if (ids.isEmpty) return;
    windows.removeWhere((w) => ids.contains(w.id));
    for (final id in ids) {
      previews.remove(id);
      pasteActions.remove(id);
      localNavigationActions.remove(id);
    }
    if (ids.contains(_defaultWindowId)) _defaultWindowId = replacementId;
    if (ids.contains(previousActiveId)) previousActiveId = null;
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

  final swipeMotion = ValueNotifier<WorkspaceSwipe?>(null);
  bool lastSwitchWasSwipe = false;

  int? activeId, previousActiveId;
  int _nextId = 0;
  String get root =>
      volumes.where((v) => v['primary'] == true).firstOrNull?['path']
          as String? ??
      _deviceVolume['path'] as String;
  String storagePath(String path) {
    if (path.startsWith('content:')) return path;
    if (path == '/sdcard' || path.startsWith('/sdcard/')) {
      path = '$root${path.substring(7)}';
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

  Json? volumeFor(String path) => _volumeForPath(storagePath(path));

  Json? _volumeForPath(String path) {
    Json? match;
    var longest = 0;
    for (final volume in volumes.isEmpty ? const [_deviceVolume] : volumes) {
      final root = volume['path'] as String;
      if (root.length > longest &&
          (path == root || path.startsWith('$root/'))) {
        match = volume;
        longest = root.length;
      }
    }
    return match;
  }

  bool containsStoragePath(String path) =>
      path.startsWith('content:') || volumeFor(path) != null;
  List<(String, String)> breadcrumbsFor(String path) {
    path = storagePath(path);
    final volume = _volumeForPath(path);
    if (volume == null) return [(baseName(path), path)];
    var current = volume['path'] as String;
    final crumbs = <(String, String)>[
      (
        volume['primary'] == false ? volume['name'] as String : 'Device',
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
    _removeWindows({
      for (final w in matches)
        if (w != existing) w.id,
    }, replacementId: existing.id);
    activate(existing.id);
    return true;
  }

  /// The Device tab is a real swipe destination from the first loaded frame.
  /// Keep Homepage active while preparing it, unlike an explicit open action.
  void ensureDeviceWindow() {
    if (windows.any((window) => window.isLocalBrowser)) {
      return;
    }
    windows.insert(0, ExplorerWindow(++_nextId, root));
    notifyListeners();
  }

  void open(
    String path, {
    String page = 'files',
    String? category,
    String? title,
    bool recent = false,
    bool search = false,
    String? selectPath,
    Json? payload,
  }) {
    path = storagePath(path);
    if (!path.startsWith('content:') && _volumeForPath(path) == null) return;
    // Local folders share one Home tab, even when opened from New or search.
    if (page == 'files' && category == null && !recent) {
      final homes = windows.where((w) => w.isLocalBrowser).toList();
      if (homes.isNotEmpty) {
        final home = homes.last;
        _removeWindows({
          for (final w in homes)
            if (w != home) w.id,
        }, replacementId: home.id);
        home.path = path;
        home.pendingSelection = selectPath;
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
    )..pendingSelection = selectPath;
    _openWindow(window, rememberPath: page == 'files');
  }

  String? takePendingSelection(int? id) {
    final window = windows.where((w) => w.id == id).firstOrNull;
    final selection = window?.pendingSelection;
    window?.pendingSelection = null;
    return selection == null ? null : storagePath(selection);
  }

  void openPage(String page, {String? url}) {
    final window = ExplorerWindow(
      _nextId + 1,
      root,
      page: page,
      url: url,
      title: switch (page) {
        'private' => 'Private Space',
        'sharing' => 'Sharing',
        'sharing_history' => 'Sharing History',
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
    _openWindow(window);
  }

  void openRemote(Json profile) {
    final window = ExplorerWindow(
      _nextId + 1,
      profile['path'] ?? '/',
      title: profile['name'] ?? profile['host'],
      profile: Map<String, dynamic>.of(profile),
    );
    _openWindow(window);
  }

  void _openWindow(ExplorerWindow window, {bool rememberPath = false}) {
    if (_activateExisting(window)) return;
    _nextId++;
    lastSwitchWasSwipe = false;
    beforeSwitch?.call();
    windows.add(window);
    if (rememberPath) remember(window.path);
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
    if (window == null) return;
    final ftp =
        window.page == 'ftp' ||
        const ['FTP', 'FTPS', 'SFTP'].contains(window.profile?['protocol']);
    if (!window.isLocalBrowser && !ftp) {
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

  void close(int id) {
    lastSwitchWasSwipe = false;
    final index = windows.indexWhere((w) => w.id == id);
    if (index < 0 || windows[index].split) return;
    _removeWindows({id});
    if (activeId == id) activeId = windows.isEmpty ? null : windows.last.id;
    notifyListeners();
  }
}
