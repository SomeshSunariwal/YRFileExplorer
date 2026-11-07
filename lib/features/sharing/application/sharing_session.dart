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
  Json status = {};
  List<Json> history = [];
  String? loadError;
  List<Json> get devices => jsonRows(status['devices']);
  List<Json> get networks => jsonRows(status['networks']);
  bool get connected => devices.isNotEmpty;
  Future<void> refresh() =>
      _refreshing ??= _load().whenComplete(() => _refreshing = null);
  Future<void> _load() async {
    try {
      status = Map<String, dynamic>.from(
        await Native.call<Map>('sharingStatus') ?? {},
      );
      history = await Native.rows('sharingHistory');
      loadError = null;
    } catch (e) {
      loadError = e.toString();
    }
    notifyListeners();
  }

  Future<void> permission() async {
    if (await Native.call<bool>('sharingPermission') != true) {
      throw StateError('Allow nearby Wi-Fi devices to share files.');
    }
    await Native.localNetworkAccess();
  }

  Future<void> create() async {
    await permission();
    await Native.call('sharingCreate');
    await refresh();
  }

  Future<void> discover() async {
    await permission();
    await Native.call('sharingDiscover');
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
