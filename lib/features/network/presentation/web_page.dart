import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/dialogs/windows_dialog.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_pane.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_action.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class WebPage extends StatefulWidget {
  final AppSettings settings;
  final int windowId;
  final String address;
  const WebPage({
    super.key,
    required this.settings,
    required this.windowId,
    required this.address,
  });
  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  MethodChannel? channel;
  late String address;
  bool allowed = false, canBack = false, canForward = false;
  int progress = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    address = widget.address;
    requestAccess();
  }

  Future<void> requestAccess() async {
    try {
      await Native.localNetworkAccess();
      if (mounted) {
        setState(() {
          allowed = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void created(int id) {
    channel = MethodChannel('yr/web/$id')
      ..setMethodCallHandler((call) async {
        if (!mounted) return null;
        switch (call.method) {
          case 'progress':
            setState(() => progress = (call.arguments as int).clamp(0, 100));
          case 'state':
            final state = Map<String, dynamic>.from(call.arguments as Map);
            setState(() {
              address = state['url'] as String;
              canBack = state['back'] == true;
              canForward = state['forward'] == true;
            });
            final window = ExplorerWorkspaceSession.instance.windows
                .where((w) => w.id == widget.windowId)
                .firstOrNull;
            if (window != null) window.url = address;
          case 'error':
            setState(() {
              error = call.arguments.toString();
              progress = 100;
            });
          case 'download':
            final job = Map<String, dynamic>.from(call.arguments as Map);
            ExplorerWorkspaceSession.instance.openPage(
              'downloads',
              url: job['url'],
            );
          case 'authenticate':
            final username = await askText(
              context,
              'Web sign in',
              label: 'Username',
            );
            if (username == null || !mounted) return null;
            final password = await askText(
              context,
              'Web sign in',
              label: 'Password',
              secret: true,
            );
            if (password == null) return null;
            return {'username': username, 'password': password};
        }
        return null;
      });
  }

  Future<void> command(String method, [String? value]) async {
    try {
      if (method == 'reload' || method == 'navigate') {
        setState(() {
          error = null;
          progress = 0;
        });
      }
      await channel?.invokeMethod<void>(method, value);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> location() async {
    final value = await askText(
      context,
      'Open web address',
      label: 'HTTP / HTTPS URL',
      initial: address,
    );
    if (value == null || !mounted) return;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      showError(context, Exception('Enter a valid HTTP or HTTPS address'));
      return;
    }
    await command('navigate', value.trim());
  }

  void back() {
    if (canBack) {
      command('back');
      return;
    }
    final session = ExplorerWorkspaceSession.instance;
    final previous = session.previousActiveId;
    session.activate(
      previous != widget.windowId &&
              session.windows.any((w) => w.id == previous)
          ? previous
          : null,
    );
  }

  @override
  void dispose() {
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExplorerPane(
    settings: widget.settings,
    windowId: widget.windowId,
    onBack: back,
    onTitle: location,
    title: Text(
      Uri.tryParse(address)?.host ?? 'Web',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    actions: [
      ExplorerAction(
        icon: Icons.arrow_forward,
        label: 'Forward',
        enabled: canForward,
        onTap: () => command('forward'),
      ),
      ExplorerAction(
        icon: progress < 100 ? Icons.close : Icons.refresh,
        label: progress < 100 ? 'Stop' : 'Refresh',
        onTap: () => command(progress < 100 ? 'stop' : 'reload'),
      ),
      ExplorerAction(
        icon: Icons.download_outlined,
        label: 'Download',
        onTap: () => ExplorerWorkspaceSession.instance.openPage(
          'downloads',
          url: address,
        ),
      ),
      ExplorerAction(
        icon: Icons.filter_none,
        label: 'Windows',
        onTap: () => showExplorerWindows(context),
      ),
    ],
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (allowed)
          AndroidView(
            viewType: 'yr/web',
            creationParams: {'url': address},
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: created,
          ),
        if (!allowed && error == null)
          const Center(child: CircularProgressIndicator()),
        if (error != null)
          ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: EmptyState(
              title: 'Page unavailable',
              message: error!,
              action: FilledButton(
                onPressed: () => allowed ? command('reload') : requestAccess(),
                child: const Text('Try again'),
              ),
            ),
          ),
        if (progress < 100 && allowed)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: progress == 0 ? null : progress / 100,
              minHeight: 2,
            ),
          ),
      ],
    ),
  );
}
