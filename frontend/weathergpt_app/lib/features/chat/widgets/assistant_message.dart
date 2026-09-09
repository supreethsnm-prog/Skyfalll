import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// An assistant turn in the chat transcript. Per spec §4.2 this is
/// deliberately **not** boxed: plain white prose directly on the
/// background, full width, with a small row of outline action icons
/// beneath it (copy, read-aloud, share, overflow). This is the asymmetric
/// counterpart to [UserBubble] (a boxed, right-aligned bubble) — do not
/// wrap anything here in a decorated `Container`, even for spacing; that
/// would defeat the whole point of the design.
class AssistantMessage extends StatelessWidget {
  const AssistantMessage({
    super.key,
    required this.text,
    this.onCopy,
    this.onReadAloud,
    this.onShare,
    this.onMore,
  });

  final String text;
  final VoidCallback? onCopy;
  final VoidCallback? onReadAloud;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  bool get _hasActions =>
      onCopy != null || onReadAloud != null || onShare != null || onMore != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: AppTypography.body(AppColors.textPrimary),
        ),
        if (_hasActions) ...[
          const SizedBox(height: AppSpacing.sm),
          _ActionRow(
            onCopy: onCopy,
            onReadAloud: onReadAloud,
            onShare: onShare,
            onMore: onMore,
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onCopy,
    required this.onReadAloud,
    required this.onShare,
    required this.onMore,
  });

  final VoidCallback? onCopy;
  final VoidCallback? onReadAloud;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onCopy != null) _ActionIcon(icon: Icons.copy_outlined, onPressed: onCopy!),
        if (onReadAloud != null)
          _ActionIcon(icon: Icons.volume_up_outlined, onPressed: onReadAloud!),
        if (onShare != null) _ActionIcon(icon: Icons.share_outlined, onPressed: onShare!),
        if (onMore != null) _ActionIcon(icon: Icons.more_vert, onPressed: onMore!),
      ],
    );
  }
}

/// A single small outline action icon in the assistant action row.
/// Deliberately not a [RoundIconButton] — those are filled chrome
/// affordances; these are bare outline icons directly on the background.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      splashRadius: 18,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(),
    );
  }
}
