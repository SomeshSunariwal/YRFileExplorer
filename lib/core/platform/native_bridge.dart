import 'dart:async';

import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/models/json.dart';

class Native {
  static const _operationZoneKey = #fileOperation;
  static Future<T> withFileOperation<T>(
    void Function(Json) report,
    String id,
    Future<T> Function() action,
  ) => runZoned(action, zoneValues: {_operationZoneKey: (id, report)});

  static const channel = MethodChannel('yr/files');
  static const eventChannel = EventChannel('yr/events');
  static final events = eventChannel
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .asBroadcastStream();
  static Future<void> localNetworkAccess() async {
    final allowed = await channel.invokeMethod<bool>('requestLocalNetwork');
    if (allowed != true) {
      throw PlatformException(
        code: 'LOCAL_NETWORK_PERMISSION',
        message: 'Allow local network access in Android app permissions, then try again.',
      );
    }
  }

  static Future<T?> call<T>(String method, [Json args = const {}]) async {
    if ((method == 'network' && args['protocol'] != 'Bluetooth') ||
        method == 'lanScan' ||
        method == 'download' ||
        method == 'retryDownload') {
      await localNetworkAccess();
    }
    final operation =
        Zone.current[_operationZoneKey] as (String, void Function(Json))?;
    if (operation != null) {
      final paths = args['sources'] ?? args['paths'];
      final current = paths is List && paths.isNotEmpty
          ? paths.first.toString()
          : args['path']?.toString() ?? '';
      if (current.isNotEmpty) operation.$2({'current': current});
      args = {...args, 'operationId': operation.$1};
    }
    return channel.invokeMethod<T>(method, args);
  }

  static Future<List<Json>> rows(String method, [Json args = const {}]) async =>
      jsonRows(await call(method, args));
}
