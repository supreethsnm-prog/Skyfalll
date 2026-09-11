import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/alerts_api.dart';
import '../../../l10n/app_strings.dart';

/// A severe-weather warning for the current location.
///
/// Deliberately **not** a [GlassPanel]: everything else on Home is
/// translucent and recessive, and an alert must not be. It is opaque, in
/// its own severity colour, so it reads as an interruption rather than
/// another data tile. This is the one place on the screen where the sky
/// does not show through.
///
/// Colours come from `AppColors.alertSeverity` / `onAlertSeverity` — the
/// app's own contrast-checked pair — not from the feed's `severity_color`
/// field, which is unvalidated upstream data.
class AlertBanner extends ConsumerWidget {
  const AlertBanner({super.key, required this.alert, this.strings});

  final AlertSummary alert;
  final AppStrings? strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings ?? ref.watch(uiStringsProvider);
    final background = AppColors.alertSeverity(alert.severity);
    final onBackground = AppColors.onAlertSeverity(alert.severity);
    final localizedEvent = (s ?? AppStrings('en')).alertEventLabel(alert.eventType);

    return Semantics(
      liveRegion: true,
      label: '${alert.severity} weather alert: $localizedEvent',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: AppRadius.iconSize,
              color: onBackground,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (localizedEvent != alert.eventType)
                    Text(
                      localizedEvent,
                      style: AppTypography.bodyBold(onBackground),
                    )
                  else
                    DynamicText(
                      alert.eventType,
                      style: AppTypography.bodyBold(onBackground),
                    ),
                  if (alert.areaDescription != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    DynamicText(
                      alert.areaDescription!,
                      style: AppTypography.label(onBackground),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
