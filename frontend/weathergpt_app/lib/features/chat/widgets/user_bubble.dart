import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// A user turn in the chat transcript. Per spec §4.2 this IS boxed: a
/// right-aligned [AppColors.userBubble] bubble at [AppRadius.bubble],
/// capped at [AppRadius.bubbleMaxWidthFactor] of the available width. This
/// is the asymmetric counterpart to [AssistantMessage] (unboxed prose) —
/// do not make them match.
class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                MediaQuery.of(context).size.width * AppRadius.bubbleMaxWidthFactor,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.userBubble,
              borderRadius: BorderRadius.circular(AppRadius.bubble),
            ),
            child: Text(
              text,
              style: AppTypography.body(AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
