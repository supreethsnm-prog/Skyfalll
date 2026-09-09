import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';

/// The app's single CTA button style: solid Marigold fill with Monsoon
/// Ink text/icon, in both light and dark theme. Explicitly forced via
/// [ElevatedButton.styleFrom] rather than left to Material 3's default
/// [ColorScheme] resolution, because that default washes the button out
/// (pale fill+text in light, near-black fill in dark) instead of
/// reading as a CTA.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.marigold,
      foregroundColor: AppColors.monsoonInk,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.surface),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    );

    if (icon != null) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label),
    );
  }
}
