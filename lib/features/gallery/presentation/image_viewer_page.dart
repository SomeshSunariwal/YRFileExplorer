import 'package:yr_file_explorer/shared/widgets/explorer_notice.dart';
import 'package:yr_file_explorer/shared/dialogs/explorer_dialog.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';

class ImageViewer extends StatefulWidget {
  final String path;
  final List<String>? images;
  final bool recycle, canDelete;
  const ImageViewer({
    super.key,
    required this.path,
    this.images,
    this.recycle = true,
    this.canDelete = true,
  });
  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> with WidgetsBindingObserver {
  late final List<String> images;
  late final PageController pages;
  late final ScrollController thumbnailScroll;
  static const thumbnailExtent = 58.0;
  double thumbnailViewport = 0;
  bool thumbnailSyncQueued = false;
  final rotations = <String, int>{};
  Timer? slideshow;
  late int index;
  bool controls = true;
  String get path => images[index];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    images = List.of(widget.images ?? [widget.path]);
    if (!images.contains(widget.path)) images.insert(0, widget.path);
    index = images.indexOf(widget.path);
    pages = PageController(initialPage: index);
    thumbnailScroll = ScrollController(
      initialScrollOffset: index * thumbnailExtent,
    );
    pages.addListener(syncThumbnails);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    slideshow?.cancel();
    pages.removeListener(syncThumbnails);
    pages.dispose();
    thumbnailScroll.dispose();
    super.dispose();
  }

  void syncThumbnails() {
    if (!mounted ||
        !thumbnailScroll.hasClients ||
        !pages.hasClients ||
        !thumbnailScroll.position.hasContentDimensions ||
        !pages.position.hasContentDimensions) {
      return;
    }
    // Follow the fractional page position, so the strip tracks the finger
    // throughout the swipe instead of moving only after the page changes.
    final page = pages.page ?? index.toDouble();
    final target = (page * thumbnailExtent).clamp(
      thumbnailScroll.position.minScrollExtent,
      thumbnailScroll.position.maxScrollExtent,
    );
    if ((thumbnailScroll.offset - target).abs() > .1) {
      thumbnailScroll.jumpTo(target);
    }
  }

  void queueThumbnailSync() {
    if (thumbnailSyncQueued) return;
    thumbnailSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      thumbnailSyncQueued = false;
      if (mounted) syncThumbnails();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stopSlideshow();
  }

  void stopSlideshow() {
    slideshow?.cancel();
    if (mounted) setState(() => slideshow = null);
  }

  void toggleSlideshow() {
    if (slideshow != null) {
      stopSlideshow();
      return;
    }
    if (images.length < 2) {
      showExplorerNotice(
        context,
        'This folder contains one image',
        icon: Icons.image_outlined,
      );
      return;
    }
    setState(() => controls = false);
    slideshow = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && pages.hasClients) {
        pages.animateToPage(
          (index + 1) % images.length,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> action(String name) async {
    stopSlideshow();
    try {
      switch (name) {
        case 'Delete':
          if (!await confirm(
            context,
            widget.recycle ? 'Move to Recycle Bin?' : 'Delete image?',
            baseName(path),
            action: 'Delete',
          )) {
            return;
          }
          await Native.call('delete', {
            'paths': [path],
            'permanent': !widget.recycle,
          });
          if (!mounted) return;
          if (images.length == 1) {
            Navigator.pop(context);
            return;
          }
          final next = index.clamp(0, images.length - 2);
          setState(() {
            images.removeAt(index);
            index = next;
          });
          pages.jumpToPage(next);
          queueThumbnailSync();
          break;
        case 'Turn right':
          setState(() => rotations[path] = ((rotations[path] ?? 0) + 1) % 4);
          break;
        case 'Set background':
          await Native.call('setWallpaper', {'path': path});
          break;
        case 'Slideshow':
          toggleSlideshow();
          break;
        case 'Share':
          await Native.call('share', {
            'paths': [path],
          });
          break;
        case 'Open with':
          await Native.call('openExternal', {'path': path});
          break;
        case 'Properties':
          final row = await Native.call<Map>('properties', {'path': path});
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (dialog) => ExplorerDialog(
              title: const Text('Properties'),
              content: SingleChildScrollView(
                child: SelectableText(
                  '${baseName(path)}\n\n$path\n\n${sizeLabel(row?['size'] ?? 0)}\n${dateLabel(row?['modified'] ?? 0)}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  bool zoomed = false;

  Widget imageMenu() => PopupMenuButton<String>(
    tooltip: 'Image actions',
    onSelected: action,
    itemBuilder: (_) =>
        [
              if (widget.canDelete) ('Delete', Icons.delete_outline),
              ('Turn right', Icons.rotate_right),
              ('Set background', Icons.wallpaper),
              ('Slideshow', Icons.slideshow_outlined),
              ('Share', Icons.share_outlined),
              ('Open with', Icons.open_in_new),
              ('Properties', Icons.info_outline),
            ]
            .map(
              (entry) => PopupMenuItem(
                value: entry.$1,
                child: Row(
                  children: [
                    Icon(entry.$2, size: 20, color: primaryBlue),
                    const SizedBox(width: 12),
                    Text(entry.$1),
                  ],
                ),
              ),
            )
            .toList(),
  );

  Widget chrome({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    elevation: 4,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            stopSlideshow();
            setState(() => controls = !controls);
          },
          child: PageView.builder(
            controller: pages,
            physics: zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: images.length,
            onPageChanged: (value) => setState(() {
              index = value;
              zoomed = false;
            }),
            itemBuilder: (_, i) => _ImageCanvas(
              key: ValueKey(images[i]),
              path: images[i],
              active: i == index,
              turns: rotations[images[i]] ?? 0,
              onZoom: (value) {
                if (i == index && mounted && zoomed != value) {
                  setState(() => zoomed = value);
                }
              },
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                IgnorePointer(
                  ignoring: !controls,
                  child: AnimatedSlide(
                    offset: controls ? Offset.zero : const Offset(0, -1.3),
                    duration: const Duration(milliseconds: 220),
                    child: AnimatedOpacity(
                      opacity: controls ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: chrome(
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back, size: 22),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    baseName(path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${index + 1} of ${images.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            imageMenu(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IgnorePointer(
                  ignoring: !controls,
                  child: AnimatedSlide(
                    offset: controls ? Offset.zero : const Offset(0, 1.3),
                    duration: const Duration(milliseconds: 220),
                    child: AnimatedOpacity(
                      opacity: controls ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: chrome(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (images.length > 1)
                              SizedBox(
                                height: 64,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    if (thumbnailViewport !=
                                        constraints.maxWidth) {
                                      thumbnailViewport = constraints.maxWidth;
                                      queueThumbnailSync();
                                    }
                                    final inset =
                                        ((constraints.maxWidth -
                                                    thumbnailExtent) /
                                                2)
                                            .clamp(0.0, double.infinity);
                                    return ListView.builder(
                                      controller: thumbnailScroll,
                                      itemExtent: thumbnailExtent,
                                      scrollDirection: Axis.horizontal,
                                      itemCount: images.length,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: inset,
                                        vertical: 6,
                                      ),
                                      itemBuilder: (_, i) => Semantics(
                                        selected: i == index,
                                        label:
                                            'Image ${i + 1}: ${baseName(images[i])}',
                                        child: InkWell(
                                          onTap: () {
                                            setState(() => zoomed = false);
                                            pages.animateToPage(
                                              i,
                                              duration: const Duration(
                                                milliseconds: 260,
                                              ),
                                              curve: Curves.easeInOutCubic,
                                            );
                                          },
                                          child: Container(
                                            width: 52,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: i == index
                                                    ? primaryBlue
                                                    : Colors.transparent,
                                                width: 2,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: Image(
                                                image: ResizeImage(
                                                  FileImage(File(images[i])),
                                                  width: 128,
                                                  height: 128,
                                                  policy: ResizeImagePolicy.fit,
                                                ),
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, _, _) =>
                                                    const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                IconButton(
                                  tooltip: 'Rotate',
                                  onPressed: () => action('Turn right'),
                                  icon: const Icon(
                                    Icons.rotate_right,
                                    color: primaryBlue,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Share',
                                  onPressed: () => action('Share'),
                                  icon: const Icon(
                                    Icons.share_outlined,
                                    color: primaryBlue,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Slideshow',
                                  onPressed: toggleSlideshow,
                                  icon: const Icon(
                                    Icons.slideshow_outlined,
                                    color: primaryBlue,
                                  ),
                                ),
                                if (widget.canDelete)
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => action('Delete'),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ImageCanvas extends StatefulWidget {
  final String path;
  final int turns;
  final bool active;
  final ValueChanged<bool> onZoom;
  const _ImageCanvas({
    super.key,
    required this.path,
    required this.turns,
    required this.active,
    required this.onZoom,
  });
  @override
  State<_ImageCanvas> createState() => _ImageCanvasState();
}

class _ImageCanvasState extends State<_ImageCanvas> {
  final transform = TransformationController();
  Offset tap = Offset.zero;
  @override
  void didUpdateWidget(covariant _ImageCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active || oldWidget.turns != widget.turns) {
      transform.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onDoubleTapDown: (details) => tap = details.localPosition,
    onDoubleTap: () {
      final zoom = transform.value.getMaxScaleOnAxis() <= 1.01;
      final matrix = Matrix4.diagonal3Values(2.5, 2.5, 1);
      matrix.setTranslationRaw(-tap.dx * 1.5, -tap.dy * 1.5, 0);
      transform.value = zoom ? matrix : Matrix4.identity();
      widget.onZoom(zoom);
    },
    child: InteractiveViewer(
      transformationController: transform,
      minScale: 1,
      maxScale: 8,
      onInteractionUpdate: (_) =>
          widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.01),
      child: Center(
        child: RotatedBox(
          quarterTurns: widget.turns,
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              'Preview unavailable',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      ),
    ),
  );
}
