import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';

/// A three-dot "assistant is responding" indicator. This is a UI
/// animation only — `POST /chat` is a single request/response, not a
/// token stream (see ChatApi/ChatController) — it does not reflect real
/// incremental progress, only that a request is in flight.
///
/// Uses a repeating AnimationController, not an indeterminate
/// CircularProgressIndicator — a lesson from Phase 0, where an
/// indeterminate spinner made `pumpAndSettle()` hang in a widget test.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.lg,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value - i * 0.2) % 1.0;
                final rampUp = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                final opacity = (0.3 + 0.7 * rampUp).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: CircleAvatar(radius: 3, backgroundColor: color),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
