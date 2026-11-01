import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    slideshow?.cancel();
    pages.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This folder contains one image')),
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
            builder: (dialog) => AlertDialog(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: controls
        ? AppBar(
            backgroundColor: explorerChrome(context),
            foregroundColor: explorerForeground(context),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${baseName(parentPath(path))} (${index + 1}/${images.length})',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  baseName(path),
                  style: TextStyle(
                    fontSize: 12,
                    color: explorerForeground(context).withValues(alpha: .7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Image actions',
                onSelected: action,
                itemBuilder: (_) =>
                    [
                          if (widget.canDelete)
                            ('Delete', Icons.delete_outline),
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
              ),
            ],
          )
        : null,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        stopSlideshow();
        setState(() => controls = !controls);
      },
      child: PageView.builder(
        controller: pages,
        itemCount: images.length,
        onPageChanged: (value) => setState(() => index = value),
        itemBuilder: (_, i) => InteractiveViewer(
          key: ValueKey(images[i]),
          minScale: .5,
          maxScale: 8,
          child: Center(
            child: RotatedBox(
              quarterTurns: rotations[images[i]] ?? 0,
              child: Image.file(
                File(images[i]),
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) => const Text(
                  'Preview unavailable',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    bottomNavigationBar: controls
        ? SafeArea(
            top: false,
            child: Container(
              color: explorerChrome(context),
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                itemBuilder: (_, i) => Semantics(
                  label: 'Image ${i + 1}: ${baseName(images[i])}',
                  selected: i == index,
                  child: InkWell(
                    onTap: () => pages.jumpToPage(i),
                    child: Container(
                      width: 64,
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: i == index ? primaryBlue : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Image.file(
                        File(images[i]),
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        : null,
  );
}
