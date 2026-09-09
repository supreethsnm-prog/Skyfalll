import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A fenced code block within an assistant message. Per spec §4.2:
/// [AppColors.surfaceInset] fill at [AppRadius.codeBlock], monospace text
/// via [AppTypography.code], with a copy affordance in the top-right
/// corner (see backend/FrontendReference/Convo2.jpeg).
class CodeBlock extends StatelessWidget {
  const CodeBlock({super.key, required this.code, this.onCopy});

  final String code;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceInset,
        borderRadius: BorderRadius.circular(AppRadius.codeBlock),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              code,
              style: AppTypography.code(AppColors.textPrimary),
            ),
          ),
          if (onCopy != null)
            IconButton(
              onPressed: onCopy,
              icon: const Icon(Icons.copy_outlined, size: 18),
              color: AppColors.textSecondary,
              splashRadius: 16,
              padding: const EdgeInsets.all(AppSpacing.xs),
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
