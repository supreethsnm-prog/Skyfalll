import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/nwp_api.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../nwp_bands.dart';

/// The severe-weather panel: NOAA GFS numerical weather prediction data,
/// presented as the fields a meteorologist actually forecasts severe
/// weather from (CAPE, gust, MSLP, cloud cover) rather than more
/// temperature tiles.
///
/// Follows the same "absent data is absent, never zero" rule as
/// `detail_tiles.dart`: every field here is nullable upstream, and a null
/// CAPE or gust is omitted from its row rather than rendered as 0 or a
/// real band's colour. The whole panel hides itself when [nwp] is null OR
/// empty — an empty array is `/nwp`'s honest answer when scheduled GFS
/// ingestion has not populated the table yet, and must read as "not
/// available", never as a panel implying calm conditions.
class SevereWeatherPanel extends StatelessWidget {
  const SevereWeatherPanel({
    super.key,
    required this.nwp,
    required this.foreground,
    this.strings,
  });

  final List<NwpPoint>? nwp;
  final Color foreground;
  final AppStrings? strings;

  @override
  Widget build(BuildContext context) {
    final points = nwp;
    if (points == null || points.isEmpty) return const SizedBox.shrink();
    final s = strings ?? AppStrings('en');

    final sorted = [...points]
      ..sort((a, b) => a.forecastHour.compareTo(b.forecastHour));
    final nearest = sorted.first;

    // Highest CAPE across the window, ignoring points where it was not
    // modelled. A null CAPE contributes nothing to "highest" — it is not
    // the same as a real reading of 0.
    NwpPoint? peakCapePoint;
    for (final p in sorted) {
      final cape = p.capeJPerKg;
      if (cape == null) continue;
      if (peakCapePoint == null || cape > peakCapePoint.capeJPerKg!) {
        peakCapePoint = p;
      }
    }

    // Peak gust in the window.
    double? peakGustKmh;
    for (final p in sorted) {
      final gust = p.windGustKmh;
      if (gust == null) continue;
      if (peakGustKmh == null || gust > peakGustKmh) {
        peakGustKmh = gust;
      }
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.severeWeather, style: AppTypography.label(foreground)),
          const SizedBox(height: AppSpacing.md),
          if (peakCapePoint != null) ...[
            _CapeRow(point: peakCapePoint, foreground: foreground, s: s),
            const SizedBox(height: AppSpacing.md),
          ],
          if (peakGustKmh != null) ...[
            _GustRow(gustKmh: peakGustKmh, foreground: foreground, s: s),
            const SizedBox(height: AppSpacing.md),
          ],
          _NearestConditionsRow(point: nearest, foreground: foreground),
          const SizedBox(height: AppSpacing.lg),
          _DayStrip(points: sorted, foreground: foreground),
          const SizedBox(height: AppSpacing.sm),
          // Provenance: which model cycle this came from. Unobtrusive, but
          // present — it is part of the credibility of this screen.
          Text(
            'GFS ${nearest.runDate} ${nearest.runHour}Z',
            style: AppTypography.caption(foreground.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// The headline convective-risk row: the CAPE band for the highest CAPE in
/// the window, with the raw value, plus CIN alongside it when modelled.
///
/// CIN is shown but never combined with CAPE into a computed index — that
/// is real forecasting judgement, and inventing one here would be
/// dishonest. It is surfaced only as a supporting fact: large negative CIN
/// next to high CAPE means stored energy that has not been released.
class _CapeRow extends StatelessWidget {
  const _CapeRow({
    required this.point,
    required this.foreground,
    required this.s,
  });

  final NwpPoint point;
  final Color foreground;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final cape = point.capeJPerKg!;
    final band = capeBand(cape)!;
    final capSeverity = capSeverityForCapeBand(band);

    // A band with no CAP mapping ("Minimal" — negligible energy) renders
    // on the panel's own neutral fill. Never call
    // AppColors.alertSeverity(null) directly: its own default falls back
    // to the moderate colour, which would misrepresent "no severity" as
    // "moderate severity" — the one mistake this product cannot make.
    final chipColor = capSeverity == null
        ? foreground.withValues(alpha: 0.12)
        : AppColors.alertSeverity(capSeverity);
    final chipForeground = capSeverity == null
        ? foreground
        : AppColors.onAlertSeverity(capSeverity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.thunderstorm_outlined,
            size: AppRadius.iconSize, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.convectiveRisk, style: AppTypography.caption(foreground)),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: chipColor,
                      borderRadius: BorderRadius.circular(AppRadius.panel / 2),
                    ),
                    child: Text(band, style: AppTypography.label(chipForeground)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${cape.round()} J/kg CAPE',
                      style: AppTypography.body(foreground)),
                ],
              ),
              if (point.cinJPerKg != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'CIN ${point.cinJPerKg!.round()} J/kg',
                  style: AppTypography.caption(foreground.withValues(alpha: 0.8)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Peak wind gust in the window, flagged when it reaches IMD's gale
/// threshold — independent of sustained wind speed, which the detail grid
/// already shows.
class _GustRow extends StatelessWidget {
  const _GustRow({
    required this.gustKmh,
    required this.foreground,
    required this.s,
  });

  final double gustKmh;
  final Color foreground;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final gale = isGaleForceGust(gustKmh) ?? false;

    return Row(
      children: [
        Icon(Icons.air, size: AppRadius.iconSize, color: foreground),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Peak gust ${gustKmh.round()} km/h',
            style: AppTypography.body(foreground),
          ),
        ),
        if (gale)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.alertSeverity('severe'),
              borderRadius: BorderRadius.circular(AppRadius.panel / 2),
            ),
            child: Text(
              s.gale,
              style: AppTypography.label(AppColors.onAlertSeverity('severe')),
            ),
          ),
      ],
    );
  }
}

/// Pressure and cloud cover for the nearest forecast hour. Renders nothing
/// when neither is modelled, and drops either half on its own when only
/// one of the two is present.
class _NearestConditionsRow extends StatelessWidget {
  const _NearestConditionsRow({required this.point, required this.foreground});

  final NwpPoint point;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final mslp = point.mslpHpa;
    final cloud = point.cloudCoverPct;
    if (mslp == null && cloud == null) return const SizedBox.shrink();

    return Row(
      children: [
        if (mslp != null) ...[
          Icon(Icons.speed, size: AppRadius.iconSize, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text('${mslp.round()} hPa', style: AppTypography.body(foreground)),
        ],
        if (mslp != null && cloud != null) const SizedBox(width: AppSpacing.lg),
        if (cloud != null) ...[
          Icon(Icons.cloud_outlined, size: AppRadius.iconSize, color: foreground),
          const SizedBox(width: AppSpacing.xs),
          Text('${cloud.round()}% cloud', style: AppTypography.body(foreground)),
        ],
      ],
    );
  }
}

/// The compact per-day strip across the forecast window: local valid time
/// plus a dot coloured by that hour's own CAPE band, so the trend across
/// the five days is visible at a glance.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.points, required this.foreground});

  final List<NwpPoint> points;
  final Color foreground;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// `validTime` arrives as UTC with a `Z` suffix; `DateTime.parse` reads
  /// that as UTC, and `.toLocal()` converts for display — never a raw UTC
  /// string next to the local times shown elsewhere on Home.
  static String _shortLocal(String validTimeUtc) {
    final parsed = DateTime.tryParse(validTimeUtc);
    if (parsed == null) return validTimeUtc;
    final local = parsed.toLocal();
    final weekday = _weekdays[local.weekday - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    // Minutes are formatted, not assumed to be :00. GFS cycles are on the
    // hour in UTC, but India is UTC+5:30 — so every one of these converts
    // to a :30 local time, and hardcoding ":00" mislabels every forecast
    // time in the app's primary market by half an hour.
    final minute = local.minute.toString().padLeft(2, '0');
    return '$weekday $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_shortLocal(p.validTime), style: AppTypography.caption(foreground)),
                  const SizedBox(height: AppSpacing.xs),
                  _CapeDot(cape: p.capeJPerKg, foreground: foreground),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A dot coloured by one hour's CAPE band. Grey — never a real band's
/// colour — when that hour's CAPE was not modelled.
class _CapeDot extends StatelessWidget {
  const _CapeDot({required this.cape, required this.foreground});

  final double? cape;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final capSeverity = capSeverityForCapeBand(capeBand(cape));
    final color = capSeverity == null
        ? foreground.withValues(alpha: 0.25)
        : AppColors.alertSeverity(capSeverity);

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
