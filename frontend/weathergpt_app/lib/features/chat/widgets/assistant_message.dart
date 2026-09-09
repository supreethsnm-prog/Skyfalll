import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
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
        if (onCopy != null)
          _ActionIcon(
            icon: Icons.copy_outlined,
            label: 'Copy',
            onPressed: onCopy!,
          ),
        if (onReadAloud != null)
          _ActionIcon(
            icon: Icons.volume_up_outlined,
            label: 'Read aloud',
            onPressed: onReadAloud!,
          ),
        if (onShare != null)
          _ActionIcon(
            icon: Icons.share_outlined,
            label: 'Share',
            onPressed: onShare!,
          ),
        if (onMore != null)
          _ActionIcon(
            icon: Icons.more_vert,
            label: 'More options',
            onPressed: onMore!,
          ),
      ],
    );
  }
}

/// A single small outline action icon in the assistant action row.
/// Deliberately not a [RoundIconButton] — those are filled chrome
/// affordances; these are bare outline icons directly on the background.
///
/// The glyph itself stays small (matching the reference), but the tap
/// target is held at [AppRadius.iconButton] (40dp) via `constraints` —
/// this is a disaster-alert app, so every actionable icon needs both a
/// screen-reader label and a tap target that clears the accessible
/// minimum, independent of how small its glyph reads visually. The
/// label is set via an explicit [Semantics] node (matching
/// [RoundIconButton]'s approach) rather than [IconButton.tooltip] alone
/// — that only populates the separate semantics `tooltip` field, not
/// `label`, which most screen readers announce far less prominently.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onPressed,
          tooltip: label,
          icon: Icon(icon, size: 20, color: AppColors.textSecondary),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: AppRadius.iconButton,
            minHeight: AppRadius.iconButton,
          ),
        ),
      ),
    );
  }
}
