import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// The single uniform round chrome affordance used throughout the app:
/// hamburger, new-chat, search, overflow, avatar. Per spec §3, every
/// instance is exactly 40dp and filled with [AppColors.surfaceRaised] —
/// do not vary the size or add per-use variants.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    Widget button = SizedBox(
      width: AppRadius.iconButton,
      height: AppRadius.iconButton,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? AppColors.surfaceRaised,
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textPrimary.withValues(alpha: 0.38),
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    // IconButton (which this widget replaces to hit the exact 40x40 circle)
    // supplies button semantics automatically; Material+InkWell does not, so
    // it must be added explicitly. This is the single uniform chrome
    // affordance used on every screen, so a screen-reader gap here would
    // propagate everywhere. ExcludeSemantics on the visual subtree stops
    // InkWell/Tooltip from contributing their own separate (and here,
    // redundant or unlabelled) semantics nodes underneath this one.
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      onTap: onPressed,
      child: ExcludeSemantics(child: button),
    );
  }
}
