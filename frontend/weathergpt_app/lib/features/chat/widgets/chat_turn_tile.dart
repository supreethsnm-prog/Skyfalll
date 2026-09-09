import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/chat_api.dart';

/// Renders one chat turn. Per the design spec (§6a): a user turn gets a
/// light Marigold-tinted rounded surface; an assistant turn is flat text
/// on the background — no bubble — so the assistant's reply reads as
/// direct prose rather than a boxed message. Every tile fades in over a
/// short duration on first build (§6a's "reveal" requirement — a real
/// per-token stream isn't available since `POST /chat` is a single
/// request/response, so this is the closest honest approximation: the
/// reply doesn't just snap into existence).
class ChatTurnTile extends StatelessWidget {
  final ChatTurn turn;

  const ChatTurnTile({super.key, required this.turn});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final content = Text(turn.content, style: AppTypography.body(onSurface));
    final isUser = turn.role == 'user';

    final Widget bubble = !isUser
        ? Align(alignment: Alignment.centerLeft, child: content)
        : Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.marigold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.surface),
                ),
                child: content,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.lg,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: bubble,
      ),
    );
  }
}
