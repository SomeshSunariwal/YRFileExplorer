import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';

class AppSettings extends ChangeNotifier {
  bool dark = false,
      hidden = false,
      grid = true,
      folderSizes = true,
      recycle = true,
      systemApps = false;
  String sort = 'Name';
  String viewMode = 'Medium Icon';
  bool descending = false;
  List<String> favorites = [], trees = [];
  List<Json> connections = [];
  List<Json> defaultWindows = [
    {'kind': 'home'},
    {'path': '/storage/emulated/0'},
  ];
  Future<void> load() async {
    try {
      final m =
          jsonDecode(await Native.call<String>('preferences') ?? '{}') as Map;
      dark = m['dark'] == true;
      hidden = m['hidden'] == true;
      grid = m['grid'] != false;
      viewMode =
          m['viewMode'] as String? ?? (grid ? 'Medium Icon' : 'Medium Detail');
      folderSizes = m['folderSizes'] != false;
      recycle = m['recycle'] != false;
      systemApps = m['systemApps'] == true;
      sort = m['sort'] as String? ?? 'Name';
      descending = m['descending'] == true;
      favorites = List<String>.from(m['favorites'] ?? []);
      trees = List<String>.from(m['trees'] ?? []);
      connections = jsonRows(m['connections']);
      if (m.containsKey('defaultWindows')) {
        defaultWindows = jsonRows(m['defaultWindows']);
      }
    } on Exception {
      /* Defaults remain usable if preferences cannot be read. */
    }
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    await Native.call('savePreferences', {
      'value': jsonEncode({
        'dark': dark,
        'hidden': hidden,
        'grid': grid,
        'viewMode': viewMode,
        'folderSizes': folderSizes,
        'recycle': recycle,
        'systemApps': systemApps,
        'sort': sort,
        'descending': descending,
        'favorites': favorites,
        'trees': trees,
        'connections': connections,
        'defaultWindows': defaultWindows,
      }),
    });
  }

  Future<void> favorite(String path) async {
    favorites.contains(path) ? favorites.remove(path) : favorites.add(path);
    await save();
  }
}
