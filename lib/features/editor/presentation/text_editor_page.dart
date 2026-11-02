import 'package:flutter/material.dart';

import 'package:yr_file_explorer/shared/widgets/progress_overlay.dart';
import 'package:yr_file_explorer/core/platform/native_bridge.dart';
import 'package:yr_file_explorer/core/utils/file_format.dart';
import 'package:yr_file_explorer/shared/dialogs/input_dialogs.dart';
import 'package:yr_file_explorer/shared/widgets/empty_state.dart';

class TextEditor extends StatefulWidget {
  final String path;
  final bool readOnly;
  const TextEditor({super.key, required this.path, this.readOnly = false});
  @override
  State<TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<TextEditor> {
  final controller = TextEditingController(),
      find = TextEditingController(),
      replacement = TextEditingController();
  final undo = UndoHistoryController();
  final focus = FocusNode();
  final scroll = ScrollController();
  late String path;
  String original = '',
      encoding = 'UTF-8',
      lineEnding = 'LF',
      savedEncoding = 'UTF-8',
      savedEnding = 'LF';
  bool loading = true,
      saving = false,
      editing = false,
      searching = false,
      replacing = false,
      matchCase = false,
      bom = false;
  String? error;
  double percent = 0, fontSize = 14;
  int match = 0;
  bool get dirty =>
      controller.text != original ||
      encoding != savedEncoding ||
      lineEnding != savedEnding;
  @override
  void initState() {
    super.initState();
    path = widget.path;
    controller.addListener(changed);
    undo.addListener(changed);
    scroll.addListener(scrolled);
    read();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void scrolled() {
    if (scroll.hasClients && mounted) {
      setState(
        () => percent = scroll.position.maxScrollExtent <= 0
            ? 0
            : (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1),
      );
    }
  }

  Future<void> read({String? charset}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = Map<String, dynamic>.from(
        (await Native.call<Map>('textInfo', {
          'path': path,
          'encoding': charset ?? '',
        }))!,
      );
      if (!mounted) return;
      setState(() {
        original = data['text'];
        controller.text = original;
        encoding = data['encoding'];
        lineEnding = data['lineEnding'];
        savedEncoding = encoding;
        savedEnding = lineEnding;
        bom = data['bom'] == true;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> save({bool asNew = false}) async {
    String target = path;
    if (asNew) {
      final value = await askText(
        context,
        'Save as',
        label: 'New file path',
        initial: '${parentPath(path)}/${baseName(path)}.copy.txt',
      );
      if (value == null || value.isEmpty) return;
      target = value;
    }
    setState(() => saving = true);
    try {
      await Native.call(asNew ? 'writeTextAs' : 'writeText', {
        'path': target,
        'text': controller.text,
        'encoding': encoding,
        'lineEnding': lineEnding,
        'bom': bom,
      });
      if (mounted) {
        setState(() {
          path = target;
          original = controller.text;
          savedEncoding = encoding;
          savedEnding = lineEnding;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<int> get matches {
    if (find.text.isEmpty) return [];
    final text = matchCase ? controller.text : controller.text.toLowerCase(),
        needle = matchCase ? find.text : find.text.toLowerCase();
    final offsets = <int>[];
    int from = 0, index;
    while ((index = text.indexOf(needle, from)) >= 0 &&
        offsets.length < 10000) {
      offsets.add(index);
      from = index + needle.length;
    }
    return offsets;
  }

  void findNext({bool previous = false}) {
    final offsets = matches;
    if (offsets.isEmpty) return;
    match = (match + (previous ? -1 : 1)) % offsets.length;
    final start = offsets[match];
    controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + find.text.length,
    );
    if (scroll.hasClients) {
      final text = controller.text;
      final before = text.substring(0, start).split('\n').length - 1;
      final lines = text.split('\n').length;
      scroll.jumpTo(
        (scroll.position.maxScrollExtent * before / lines).clamp(
          0,
          scroll.position.maxScrollExtent,
        ),
      );
    }
    changed();
  }

  void replace({bool all = false}) {
    final offsets = matches;
    if (offsets.isEmpty) return;
    if (all) {
      controller.text = controller.text.replaceAll(
        RegExp(RegExp.escape(find.text), caseSensitive: matchCase),
        replacement.text,
      );
    } else {
      final start = offsets[match % offsets.length];
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(
          start,
          start + find.text.length,
          replacement.text,
        ),
        selection: TextSelection.collapsed(
          offset: start + replacement.text.length,
        ),
      );
    }
    changed();
  }

  Future<void> menu(String action) async {
    switch (action) {
      case 'Edit':
        setState(() => editing = true);
        focus.requestFocus();
      case 'Save as':
        await save(asNew: true);
      case 'Find':
        setState(() => searching = true);
      case 'Replace':
        setState(() {
          searching = true;
          replacing = true;
          editing = true;
        });
      case 'Select all':
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        focus.requestFocus();
      case 'Encoding':
        final value = await showDialog<String>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Encoding'),
            children: [
              for (final name in [
                'UTF-8',
                'UTF-16LE',
                'UTF-16BE',
                'GBK',
                'Big5',
                'Shift_JIS',
                'ISO-8859-1',
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, name),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(name),
                  ),
                ),
            ],
          ),
        );
        if (value != null) {
          if (editing) {
            setState(() => encoding = value);
          } else {
            await read(charset: value);
          }
        }
      case 'Line terminator':
        final value = await showDialog<String>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Line Terminator'),
            children: [
              for (final item in [
                ('CRLF', 'DOS Terminators - CR/LF'),
                ('LF', 'UNIX Terminators - LF'),
                ('CR', 'MAC Terminators - CR'),
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, item.$1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(item.$2),
                  ),
                ),
            ],
          ),
        );
        if (value != null) setState(() => lineEnding = value);
      case 'Font size':
        final value = await showDialog<double>(
          context: context,
          builder: (dialog) => SimpleDialog(
            title: const Text('Font size'),
            children: [
              for (final size in [12.0, 14.0, 16.0, 18.0, 20.0, 24.0])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialog, size),
                  child: Text('${size.toInt()}'),
                ),
            ],
          ),
        );
        if (value != null) setState(() => fontSize = value);
      case 'Share':
        await Native.call('share', {
          'paths': [path],
        });
      case 'Delete':
        if (await confirm(
          context,
          'Move file to Recycle Bin?',
          'Move ${baseName(path)} to Recycle Bin?',
          action: 'Move',
        )) {
          await Native.call('delete', {
            'paths': [path],
            'permanent': false,
          });
          if (mounted) {
            setState(() => original = controller.text);
            Navigator.pop(context);
          }
        }
    }
  }

  Future<void> back() async {
    if (dirty &&
        !await confirm(
          context,
          'Discard changes?',
          'The file has unsaved changes.',
          action: 'Discard',
        )) {
      return;
    }
    if (mounted) {
      setState(() {
        original = controller.text;
        savedEncoding = encoding;
        savedEnding = lineEnding;
      });
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    undo.removeListener(changed);
    scroll.removeListener(scrolled);
    controller.dispose();
    find.dispose();
    replacement.dispose();
    undo.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          '${baseName(path)}${dirty ? ' *' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (editing) ...[
            IconButton(
              tooltip: 'Undo',
              onPressed: undo.value.canUndo ? undo.undo : null,
              icon: const Icon(Icons.undo, size: 21),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: undo.value.canRedo ? undo.redo : null,
              icon: const Icon(Icons.redo, size: 21),
            ),
            IconButton(
              tooltip: 'Save',
              onPressed: saving || !dirty ? null : save,
              icon: const Icon(Icons.save_outlined, size: 21),
            ),
          ] else
            IconButton(
              tooltip: 'Find',
              onPressed: () => menu('Find'),
              icon: const Icon(Icons.search),
            ),
          PopupMenuButton<String>(
            onSelected: menu,
            itemBuilder: (_) => [
              if (!widget.readOnly && !editing) 'Edit',
              if (!widget.readOnly && editing) 'Save as',
              'Find',
              if (!widget.readOnly) 'Replace',
              'Select all',
              'Encoding',
              if (!widget.readOnly && editing) 'Line terminator',
              'Font size',
              'Share',
              if (!widget.readOnly) 'Delete',
            ].map((a) => PopupMenuItem(value: a, child: Text(a))).toList(),
          ),
        ],
      ),
      body: ExplorerProgressOverlay(
        active: saving,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              if (searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: find,
                              onChanged: (_) {
                                match = -1;
                                findNext();
                              },
                              decoration: const InputDecoration(
                                hintText: 'Find',
                              ),
                            ),
                          ),
                          Text(
                            '${matches.isEmpty ? 0 : match % matches.length + 1}/${matches.length}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          IconButton(
                            tooltip: 'Previous match',
                            onPressed: () => findNext(previous: true),
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          IconButton(
                            tooltip: 'Next match',
                            onPressed: findNext,
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          IconButton(
                            tooltip: 'Close find',
                            onPressed: () => setState(() => searching = false),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          FilterChip(
                            label: const Text('Match case'),
                            selected: matchCase,
                            onSelected: (v) => setState(() => matchCase = v),
                          ),
                          if (!widget.readOnly)
                            TextButton(
                              onPressed: () =>
                                  setState(() => replacing = !replacing),
                              child: const Text('Replace'),
                            ),
                        ],
                      ),
                      if (replacing)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: replacement,
                                decoration: const InputDecoration(
                                  hintText: 'Replace with',
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => replace(),
                              child: const Text('Replace'),
                            ),
                            TextButton(
                              onPressed: () => replace(all: true),
                              child: const Text('All'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? EmptyState(
                        title: 'Cannot read text',
                        message: error!,
                        action: TextButton(
                          onPressed: () => menu('Encoding'),
                          child: const Text('Choose encoding'),
                        ),
                      )
                    : TextField(
                        controller: controller,
                        focusNode: focus,
                        undoController: undo,
                        scrollController: scroll,
                        readOnly: !editing,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        style: TextStyle(
                          fontFamily: editing ? 'monospace' : null,
                          fontSize: fontSize,
                          height: 1.5,
                        ),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.all(14),
                          border: InputBorder.none,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Text(
                  '$encoding · $lineEnding',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                Expanded(
                  child: Slider(
                    value: percent,
                    onChanged: (v) {
                      if (scroll.hasClients) {
                        scroll.jumpTo(scroll.position.maxScrollExtent * v);
                      }
                    },
                  ),
                ),
                Text(
                  '${(percent * 100).round()}%',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
