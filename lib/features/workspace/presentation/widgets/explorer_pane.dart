import 'dart:async';

import 'package:yr_file_explorer/shared/widgets/explorer_selection_header.dart';
import 'package:flutter/material.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_navigation_header.dart';

import 'package:yr_file_explorer/shared/widgets/progress_overlay.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/workspace_page_deck.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/explorer_bottom_bar.dart';
import 'package:yr_file_explorer/core/settings/app_settings.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';
import 'package:yr_file_explorer/features/workspace/presentation/widgets/segmented_tabs.dart';
import 'package:yr_file_explorer/shared/widgets/breadcrumbs.dart';

/// Fixed navigation shared by tools that participate in the file workspace.
class ExplorerPane extends StatefulWidget {
  final AppSettings settings;
  final int? windowId;
  final Widget title, body;
  final Widget? searchHeader;
  final List<Widget> actions;
  final bool selecting, interceptBack, busy, extendBody;
  final VoidCallback? onBack,
      onTitle,
      onActivate,
      onSelectAll,
      onClearSelection;
  final String selectAllLabel;
  const ExplorerPane({
    super.key,
    required this.settings,
    this.windowId,
    required this.title,
    this.searchHeader,
    required this.body,
    required this.actions,
    this.selecting = false,
    this.extendBody = true,
    this.busy = false,
    this.interceptBack = false,
    this.onBack,
    this.onTitle,
    this.onActivate,
    this.onSelectAll,
    this.onClearSelection,
    this.selectAllLabel = 'Select all',
  });
  @override
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  final session = ExplorerWorkspaceSession.instance;
  bool wasActive = false;
  Timer? activationRefresh;
  @override
  void initState() {
    super.initState();
    wasActive = session.activeId == widget.windowId;
    session.addListener(workspaceChanged);
  }

  void workspaceChanged() {
    final active =
        widget.windowId != null && session.activeId == widget.windowId;
    if (active && !wasActive) {
      activationRefresh?.cancel();
      // Let the horizontal transition finish before refreshing native data.
      // Preserve the cached body throughout the motion and skip abandoned tabs.
      activationRefresh = Timer(const Duration(milliseconds: 340), () {
        if (mounted && session.activeId == widget.windowId) {
          widget.onActivate?.call();
        }
      });
    } else if (!active) {
      activationRefresh?.cancel();
    }
    wasActive = active;
  }

  @override
  void dispose() {
    activationRefresh?.cancel();
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
      extendBody: widget.extendBody,
      appBar: AppBar(
        backgroundColor: explorerChrome(context),
        automaticallyImplyLeading: false,
        toolbarHeight: explorerTabHeight,
        titleSpacing: 0,
        title: ReferenceTabs(onLocal: () => session.open(session.root)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(explorerHeaderHeight),
          child: widget.searchHeader != null && !widget.selecting
              ? ExplorerHeaderFrame(
                  separators: false,
                  child: widget.searchHeader!,
                )
              : !widget.selecting
              ? ExplorerNavigationHeader(
                  onBack: back,
                  onClose: () {
                    if (widget.windowId != null) {
                      session.close(widget.windowId!);
                    } else {
                      Navigator.maybePop(context);
                    }
                  },
                  location: widget.title is ExplorerBreadcrumbs
                      ? widget.title
                      : InkWell(
                          onTap: widget.onTitle,
                          child: ExplorerLocationPill(
                            child: Center(
                              child: DefaultTextStyle(
                                style: TextStyle(
                                  color: explorerForeground(context),
                                  fontSize: 14,
                                ),
                                child: widget.title,
                              ),
                            ),
                          ),
                        ),
                )
              : ExplorerHeaderFrame(
                  separators: false,
                  child: ExplorerSelectionHeader(
                    count: widget.title,
                    onDone: widget.busy ? null : back,
                    onSelectAll: widget.busy ? null : widget.onSelectAll,
                    onClear: widget.busy ? null : widget.onClearSelection,
                    selectAllLabel: widget.selectAllLabel,
                  ),
                ),
        ),
      ),
      body: WorkspaceBodySlide(
        allowTabSwipe: !widget.selecting,
        child: ExplorerProgressOverlay(
          active: widget.busy,
          child: SafeArea(top: false, bottom: false, child: widget.body),
        ),
      ),
      bottomNavigationBar: ExplorerBottomBar(
        child: Row(children: widget.actions),
      ),
    ),
  );
}
