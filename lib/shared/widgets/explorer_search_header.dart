import 'package:flutter/material.dart';
import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

class ExplorerSearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onClose;
  final ValueChanged<String>? onChanged, onSubmitted;
  final Widget? leading;
  const ExplorerSearchHeader({
    super.key,
    required this.controller,
    required this.onClose,
    this.hint = 'Search files',
    this.onChanged,
    this.onSubmitted,
    this.leading,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      leading ??
          const SizedBox(
            width: 44,
            child: Icon(Icons.search, color: primaryBlue, size: 22),
          ),
      Expanded(
        child: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(color: explorerForeground(context), fontSize: 14),
          onChanged: onChanged,
          onSubmitted: (value) => submit(context, value),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: false,
            hintStyle: TextStyle(
              color: explorerForeground(context).withValues(alpha: .5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: IconButton(
              tooltip: 'Close search',
              onPressed: () {
                FocusScope.of(context).unfocus();
                onClose();
              },
              icon: Icon(
                Icons.close,
                size: 18,
                color: explorerForeground(context).withValues(alpha: .6),
              ),
            ),
          ),
        ),
      ),
      Container(
        width: 1,
        height: explorerHeaderHeight - 16,
        color: explorerLine(context),
      ),
      IconButton(
        tooltip: 'Run search',
        onPressed: () => submit(context, controller.text),
        icon: const Icon(Icons.arrow_forward, color: primaryBlue, size: 21),
      ),
    ],
  );
  void submit(BuildContext context, String value) {
    FocusScope.of(context).unfocus();
    if (onSubmitted != null) {
      onSubmitted!(value);
    } else {
      onChanged?.call(value);
    }
  }
}
