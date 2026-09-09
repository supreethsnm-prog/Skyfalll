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
            // Explicit Semantics (matching RoundIconButton's approach)
            // rather than relying on IconButton.tooltip alone: that only
            // populates the semantics `tooltip` field, not `label`, which
            // most screen readers announce far less prominently. The tap
            // target is held at the 40dp accessible minimum via
            // `constraints`; the glyph uses the shared AppRadius.iconSize
            // (previously 18dp here vs 20dp everywhere else — nothing
            // justified the difference).
            Semantics(
              button: true,
              enabled: true,
              label: 'Copy',
              onTap: onCopy,
              child: ExcludeSemantics(
                child: IconButton(
                  onPressed: onCopy,
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_outlined, size: AppRadius.iconSize),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppRadius.iconButton,
                    minHeight: AppRadius.iconButton,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
