import 'package:flutter/material.dart';
import 'package:yr_file_explorer/shared/widgets/explorer_progress_bar.dart';

/// Shared fixed text slots keep all processing dialogs steady while updating.
class OperationProgressContent extends StatelessWidget {
  final String filename, summary;
  final double? value;
  final TextAlign summaryAlignment;
  const OperationProgressContent({
    super.key,
    required this.filename,
    required this.summary,
    this.value,
    this.summaryAlignment = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(12) * 1.25 + 2;
    final pathHeight = scaler.scale(12) * 1.35 * 2 + 2;
    final totalsHeight = scaler.scale(13) * 1.3 + 2;
    return SizedBox(
      width: 320,
      height: labelHeight + pathHeight + totalsHeight + 50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: labelHeight,
            child: const Text(
              'File name:',
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: pathHeight,
            width: double.infinity,
            child: Text(
              filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ExplorerProgressBar(value: value),
          const SizedBox(height: 12),
          SizedBox(
            height: totalsHeight,
            width: double.infinity,
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: summaryAlignment,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
