import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'widgets/workspace_window.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/models/json.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/features/files/application/file_clipboard.dart';
import 'package:yr_file_explorer/features/home/presentation/home_page.dart';
import 'package:yr_file_explorer/features/network/presentation/network_page.dart';
import 'package:yr_file_explorer/features/settings/presentation/settings_page.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';

class ExplorerWorkspace extends StatefulWidget {
  final AppSettings settings;
  const ExplorerWorkspace({super.key, required this.settings});
  @override
  State<ExplorerWorkspace> createState() => _ExplorerWorkspaceState();
}

class _ExplorerWorkspaceState extends State<ExplorerWorkspace> {
  final session = ExplorerWorkspaceSession.instance;
  final clipboard = FileClipboard();
  bool restoredDefaults = false;
  Timer? previewTimer;
  Future<void>? pendingCapture;
  int? capturingId;
  int? previewActiveId;
  bool previewRequested = false;
  Brightness? previewBrightness;

  void queuePreview() {
    previewTimer?.cancel();
    final id = session.activeId;
    previewTimer = Timer(const Duration(milliseconds: 500), () async {
      if (mounted && id == session.activeId) {
        await captureCurrent();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (previewBrightness != brightness) {
      previewBrightness = brightness;
      queuePreview();
    }
  }

  @override
  void initState() {
    super.initState();
    session.addListener(changed);
    clipboard.addListener(session.clipboardChanged);
    session.onTool = openTool;
    session.onServer = openServer;
    session.servers = widget.settings.connections;
    session.defaults = widget.settings.defaultWindows;
    session.onSaveDefaults = (values) {
      widget.settings.defaultWindows = values;
      widget.settings.save();
    };
    session.beforeSwitch = captureCurrent;
    session.clipboardItems = () => clipboard.paths;
    session.clipboardMove = () => clipboard.move;
    session.clearClipboard = clipboard.clear;
    session.onPermissionGranted = restoreDefaults;
  }

  Future<void> restoreDefaults() async {
    if (restoredDefaults) return;
    restoredDefaults = true;
    session.ensureDeviceWindow();
    for (final entry in session.defaults) {
      if (entry['profile'] is Map) {
        final profile = Map<String, dynamic>.from(entry['profile'] as Map);
        profile['path'] = entry['path'] ?? profile['path'] ?? '/';
        if (profile['rememberPassword'] == true) {
          try {
            profile['password'] =
                await Native.call<String>('connectionPassword', {
                  'id':
                      '${profile['protocol']}|${profile['host']}|${profile['port']}|${profile['username']}',
                }) ??
                '';
          } catch (_) {
            profile.remove('password');
          }
        }
        if (!mounted) return;
        session.openRemote(profile);
        continue;
      }
      if (entry['page'] == 'analysis_results' && entry['path'] is String) {
        session.open(
          entry['path'],
          page: 'analysis_results',
          category: entry['category'],
          title: entry['title'],
        );
        continue;
      }
      if (['analysis', 'storage_analysis'].contains(entry['page']) &&
          entry['path'] is String) {
        session.open(
          entry['path'],
          page: entry['page'],
          title: entry['page'] == 'analysis'
              ? 'Storage Analyzer'
              : 'Folder Analysis',
        );
        continue;
      }
      if (entry['page'] != null &&
          entry['page'] != 'files' &&
          entry['page'] != 'archive') {
        session.openPage(entry['page'], url: entry['url']);
        continue;
      }
      if (entry['path'] is String) {
        session.open(
          entry['path'],
          page: entry['page'] ?? 'files',
          category: entry['category'],
          title: entry['title'],
          recent: entry['recent'] == true,
        );
      }
    }
  }

  void changed() {
    if (!mounted) return;
    setState(() {});
    if (!previewRequested || previewActiveId != session.activeId) {
      previewRequested = true;
      previewActiveId = session.activeId;
      queuePreview();
    }
  }

  Future<void> captureCurrent() async {
    final requestedId = session.activeId;
    final pending = pendingCapture;
    if (pending != null) {
      final sameWindow = capturingId == requestedId;
      await pending;
      if (sameWindow || !mounted || requestedId != session.activeId) return;
    }
    capturingId = requestedId;
    await (pendingCapture ??= capturePreview().whenComplete(
      () => pendingCapture = null,
    ));
  }

  Future<void> capturePreview() async {
    if (!mounted || session.swipeMotion.value != null) return;
    final id = session.activeId;
    if (session.windows.any(
      (window) => window.id == id && window.page == 'private',
    )) {
      return;
    }
    final key = id == null
        ? session.homePreviewKey
        : session.windows.where((w) => w.id == id).firstOrNull?.previewKey;
    final boundary = key?.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    if (boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || id != session.activeId || boundary.debugNeedsPaint) {
        return;
      }
    }
    ui.Image? image;
    try {
      image = await boundary.toImage(pixelRatio: .6);
      if (!mounted ||
          id != session.activeId ||
          session.swipeMotion.value != null) {
        return;
      }
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null &&
          mounted &&
          id == session.activeId &&
          session.swipeMotion.value == null) {
        session.setPreview(id, bytes.buffer.asUint8List());
      }
    } catch (_) {
      /* A loading tab may not have a painted frame yet. */
    } finally {
      image?.dispose();
    }
  }

  void openServer(Json profile) => Navigator.of(context).push(
    ExplorerPageRoute<void>(
      builder: (_) => NetworkPage(
        settings: widget.settings,
        clipboard: clipboard,
        initialProfile: profile,
      ),
    ),
  );
  void openTool(String page) {
    if (page == 'analysis') {
      final current = session.windows
          .where((w) => w.id == session.activeId)
          .firstOrNull;
      final path = current == null || current.profile != null
          ? session.root
          : current.page == 'archive'
          ? parentPath(current.path)
          : current.path;
      session.open(path, page: 'analysis', title: 'Storage Analyzer');
      return;
    }
    if ([
      'private',
      'apps',
      'network',
      'trash',
      'lan',
      'ftp',
      'webdav',
      'bluetooth',
      'netmanager',
      'downloads',
      'sharing',
      'sharing_history',
    ].contains(page)) {
      session.openPage(page);
      return;
    }
    final Widget screen = page == 'sftp'
        ? NetworkPage(
            settings: widget.settings,
            clipboard: clipboard,
            initialProtocol: 'SFTP',
          )
        : SettingsPage(settings: widget.settings);
    Navigator.of(context).push(ExplorerPageRoute<void>(builder: (_) => screen));
  }

  @override
  void dispose() {
    previewTimer?.cancel();
    session.removeListener(changed);
    session.onTool = null;
    session.onServer = null;
    session.beforeSwitch = null;
    session.onPermissionGranted = null;
    session.onSaveDefaults = null;
    clipboard.removeListener(session.clipboardChanged);
    clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WorkspacePageDeck(
    activeId: session.activeId ?? 0,
    pageIds: [0, for (final window in session.windows) window.id],
    children: [
      TickerMode(
        enabled: session.activeId == null,
        child: RepaintBoundary(
          key: session.homePreviewKey,
          child: ExplorerHome(settings: widget.settings, clipboard: clipboard),
        ),
      ),
      for (final window in session.windows)
        TickerMode(
          key: ValueKey(window.id),
          enabled: session.activeId == window.id,
          child: RepaintBoundary(
            key: window.previewKey,
            child: WorkspaceWindow(
              window: window,
              settings: widget.settings,
              clipboard: clipboard,
            ),
          ),
        ),
    ],
  );
}
