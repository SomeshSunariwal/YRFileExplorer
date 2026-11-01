import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/file_categories.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  const EmptyState({
    super.key,
    this.icon = Icons.folder_open,
    required this.title,
    required this.message,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: primaryBlue.withValues(alpha: .6)),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 20), child: action),
        ],
      ),
    ),
  );
}
