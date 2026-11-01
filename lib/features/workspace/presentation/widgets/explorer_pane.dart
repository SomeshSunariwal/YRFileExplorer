import 'package:flutter/material.dart';

import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/segmented_tabs.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';

/// Fixed navigation shared by tools that participate in the file workspace.
class ExplorerPane extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  final Widget title, body;
  final List<Widget> actions;
  final bool selecting, interceptBack;
  final VoidCallback? onBack, onTitle, onActivate;
  const ExplorerPane({
    super.key,
    required this.settings,
    this.windowId,
    required this.title,
    required this.body,
    required this.actions,
    this.selecting = false,
    this.interceptBack = false,
    this.onBack,
    this.onTitle,
    this.onActivate,
  });
  @override
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  final session = ExplorerWorkspaceSession.instance;
  bool wasActive = false;
  @override
  void initState() {
    super.initState();
    wasActive = session.activeId == widget.windowId;
    session.addListener(workspaceChanged);
  }

  void workspaceChanged() {
    final active =
        widget.windowId != null && session.activeId == widget.windowId;
    if (active && !wasActive) widget.onActivate?.call();
    wasActive = active;
  }

  @override
  void dispose() {
    session.removeListener(workspaceChanged);
    super.dispose();
  }

  void back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (widget.windowId != null) {
      session.activate(null);
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.windowId == null
        ? !widget.selecting && !widget.interceptBack
        : session.activeId != widget.windowId,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop &&
          (widget.windowId == null || session.activeId == widget.windowId)) {
        back();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        backgroundColor: explorerChrome(context),
        automaticallyImplyLeading: false,
        toolbarHeight: explorerTabHeight,
        titleSpacing: 0,
        title: ReferenceTabs(
          local: true,
          onHome: () => session.activate(null),
          onLocal: () => session.open(session.root),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(explorerHeaderHeight),
          child: ExplorerHeaderFrame(
            separators: !widget.selecting,
            child: Row(
              children: [
                IconButton(
                  tooltip: widget.selecting ? 'Done' : 'Back',
                  onPressed: back,
                  icon: Icon(
                    widget.selecting ? Icons.check : Icons.arrow_back,
                    color: primaryBlue,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: widget.onTitle,
                    child: DefaultTextStyle(
                      style: TextStyle(
                        color: explorerForeground(context),
                        fontSize: 14,
                      ),
                      child: Center(
                        child:
                            widget.title is ExplorerBreadcrumbs ||
                                widget.selecting
                            ? widget.title
                            : ExplorerLocationPill(child: widget.title),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close window',
                  onPressed: () {
                    if (widget.windowId != null) {
                      session.close(widget.windowId!);
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
                  icon: const Icon(
                    Icons.cancel_outlined,
                    color: primaryBlue,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: WorkspaceBodySlide(
        child: SafeArea(top: false, bottom: false, child: widget.body),
      ),
      bottomNavigationBar: ExplorerBottomBar(
        child: Row(children: widget.actions),
      ),
    ),
  );
}
