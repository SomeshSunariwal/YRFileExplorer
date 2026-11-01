import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/models/json.dart';

class Native {
  static const channel = MethodChannel('yr/files');
  static const eventChannel = EventChannel('yr/events');
  static final events = eventChannel
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .asBroadcastStream();
  static Future<T?> call<T>(String method, [Json args = const {}]) =>
      channel.invokeMethod<T>(method, args);
  static Future<List<Json>> rows(String method, [Json args = const {}]) async =>
      jsonRows(await call(method, args));
}
