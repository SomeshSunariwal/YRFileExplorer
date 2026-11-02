import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

/// Gates the entire navigator, including restored tabs and pushed routes.
/// The workspace is not mounted until Android confirms all-files access.
class StoragePermissionGate extends StatefulWidget {
  final Widget child;
  const StoragePermissionGate({super.key, required this.child});

  @override
  State<StoragePermissionGate> createState() => _StoragePermissionGateState();
}

class _StoragePermissionGateState extends State<StoragePermissionGate>
    with WidgetsBindingObserver {
  bool allowed = false, checking = true, requesting = false;
  bool entered = false;
  int generation = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() async {
    final token = ++generation;
    setState(() => checking = true);
    try {
      final granted = await Native.call<bool>('permission') == true;
      if (!mounted || token != generation) return;
      setState(() {
        allowed = granted;
        entered = entered || granted;
        checking = false;
        error = null;
      });
    } catch (_) {
      if (!mounted || token != generation) return;
      setState(() {
        allowed = false;
        checking = false;
        error = 'Unable to check storage access. Please try again.';
      });
    }
  }

  Future<void> request() async {
    if (requesting) return;
    setState(() => requesting = true);
    try {
      await Native.call('requestPermission');
      // Launching Settings does not mean permission was granted. The resume
      // check verifies Android's actual permission state before allowing entry.
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open storage settings. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = checking || !allowed;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (entered)
          Offstage(
            offstage: blocked,
            child: TickerMode(
              enabled: !blocked,
              child: ExcludeFocus(
                excluding: blocked,
                child: IgnorePointer(ignoring: blocked, child: widget.child),
              ),
            ),
          ),
        if (blocked)
          Scaffold(
            body: checking
                ? const Center(child: CircularProgressIndicator())
                : ColoredBox(
                    color: Colors.black.withValues(alpha: .22),
                    child: Center(
                      child: ExplorerDialog(
                        canClose: false,
                        title: const Text('Storage access required'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.folder_open_outlined,
                              size: 38,
                              color: primaryBlue,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Allow access to manage all files to browse and organize your storage. Enable it on the next Android settings screen.',
                              textAlign: TextAlign.center,
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: SystemNavigator.pop,
                            child: const Text('Exit'),
                          ),
                          FilledButton(
                            onPressed: requesting ? null : request,
                            child: const Text('Allow storage access'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}
