import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';

/// One live sharing session across tabs, menus, and transfer history.
class SharingSession extends ChangeNotifier {
  static final instance = SharingSession._();
  SharingSession._() {
    Native.events.where((e) => e['type'] == 'sharingChanged').listen((_) {
      _refreshTimer ??= Timer(const Duration(milliseconds: 150), () {
        _refreshTimer = null;
        refresh();
      });
    });
  }
  Timer? _refreshTimer;
  Future<void>? _refreshing;
  bool _refreshAgain = false;
  int _historyRevision = -1;
  final _connection = ValueNotifier(false);
  ValueListenable<bool> get connection => _connection;
  Json status = {};
  List<Json> history = [];
  List<Json> devices = [];
  List<Json> networks = [];
  String? loadError;
  bool get connected => _connection.value;

  Future<void> refresh() {
    final pending = _refreshing;
    if (pending != null) {
      _refreshAgain = true;
      return pending;
    }
    return _refreshing = _load().whenComplete(() => _refreshing = null);
  }

  Future<void> _load() async {
    do {
      _refreshAgain = false;
      try {
        final snapshot = Map<String, dynamic>.from(
          await Native.call<Map>('sharingStatus', {
                'historyRevision': _historyRevision,
              }) ??
              {},
        );
        final updatedHistory = snapshot.remove('history') as Map?;
        if (updatedHistory != null) {
          history = jsonRows(updatedHistory['rows']);
          _historyRevision = updatedHistory['revision'] as int;
        }
        status = snapshot;
        devices = jsonRows(snapshot['devices']);
        networks = jsonRows(snapshot['networks']);
        loadError = null;
        _connection.value = devices.isNotEmpty;
      } catch (e) {
        loadError = e.toString();
      }
      notifyListeners();
    } while (_refreshAgain);
  }

  Future<void> permission() async {
    if (await Native.call<bool>('sharingPermission') != true) {
      throw StateError('Allow nearby Wi-Fi devices to share files.');
    }
    await Native.localNetworkAccess();
  }

  Future<void> create() => _start('sharingCreate');

  Future<void> discover() => _start('sharingDiscover');

  Future<void> _start(String method) async {
    await permission();
    await Native.call(method);
    await refresh();
  }

  Future<void> join(String device, String code) async {
    await Native.call('sharingJoin', {'device': device, 'code': code});
    await refresh();
  }

  Future<void> stop() async {
    await Native.call('sharingStop');
    await refresh();
  }

  Future<void> send(String device, List<String> paths) async {
    await Native.call('sharingSend', {'device': device, 'paths': paths});
  }
}
