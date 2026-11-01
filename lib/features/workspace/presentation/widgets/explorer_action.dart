import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';
import 'package:yr_file_explorer/features/workspace/application/workspace_session.dart';

class ExplorerAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const ExplorerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: ExplorerWorkspaceSession.instance,
                builder: (_, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 24,
                      color: explorerForeground(context)
                          .withValues(alpha: enabled ? .92 : .35),
                    ),
                    if (label == 'Windows')
                      Positioned(
                        right: -8,
                        top: -5,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 15),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: primaryBlue,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '${ExplorerWorkspaceSession.instance.count}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: explorerForeground(context)
                        .withValues(alpha: enabled ? .95 : .38),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
