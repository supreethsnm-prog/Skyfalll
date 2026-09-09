import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

/// A translucent, blurred panel grouping data over the sky background, as
/// on the Google Weather home screen (spec §2.2). Critically subtle: the
/// reference panels sample only 2-4% lighter than the sky behind them, so
/// the fill is a low-alpha white, not an opaque card.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  /// ~12% white, matching the reference's subtlety. Deliberately far
  /// below an "opaque card" alpha — see spec §2.2.
  static const _fillColor = Color(0x1FFFFFFF);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: _fillColor,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: child,
        ),
      ),
    );
  }
}
