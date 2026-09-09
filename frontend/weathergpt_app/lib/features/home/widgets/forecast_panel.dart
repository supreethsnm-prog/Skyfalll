import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/weather_icon.dart';

/// The multi-day forecast, grouped into a [GlassPanel] over the sky as in
/// `Home1.jpeg`.
///
/// Deliberately a list, not a chart: `/forecast` returns one row per day
/// with no hourly series, so there is nothing to plot. Google Weather's
/// hourly graph has no equivalent here and is not faked.
class ForecastPanel extends StatelessWidget {
  const ForecastPanel({
    super.key,
    required this.days,
    required this.foreground,
  });

  final List<ForecastDay> days;

  /// From `skyForeground(...)` — see [HomeHero] for why this is injected.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${days.length}-day forecast',
            style: AppTypography.label(foreground),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final day in days)
            _ForecastRow(day: day, foreground: foreground),
        ],
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day, required this.foreground});

  final ForecastDay day;
  final Color foreground;

  /// `forecast_date` arrives as an ISO date string. A malformed value
  /// falls back to the raw string rather than throwing — a bad date from
  /// the feed should degrade one row, not take down the screen.
  String get _weekday {
    final parsed = DateTime.tryParse(day.forecastDate);
    if (parsed == null) return day.forecastDate;

    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[parsed.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(_weekday, style: AppTypography.body(foreground)),
          ),
          Icon(
            weatherIconFor(day.weatherCode),
            size: AppRadius.iconSize,
            color: foreground,
          ),
          const Spacer(),
          Text(
            '${day.tempMaxC.round()}° / ${day.tempMinC.round()}°',
            style: AppTypography.body(foreground),
          ),
        ],
      ),
    );
  }
}
