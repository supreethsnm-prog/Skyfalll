import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../weather_label.dart';

/// The Home screen's headline block, per `Home1.jpeg`: place name, a very
/// large temperature, and the condition beneath it — all sitting directly
/// on the sky with no card behind them.
///
/// [foreground] comes from `skyForeground(...)` and must be passed in
/// rather than read here: the caller is the only thing that knows which
/// sky is behind this, and the whole WCAG contract depends on that one
/// decision being made in one place.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.place,
    required this.weather,
    required this.foreground,
    this.high,
    this.low,
  });

  final String place;
  final CurrentWeather weather;
  final Color foreground;

  /// Today's high/low, when a forecast is available. Omitted rather than
  /// faked when it is not — the backend's `/weather` has no such field.
  final double? high;
  final double? low;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(place, style: AppTypography.title(foreground)),
        const SizedBox(height: AppSpacing.sm),
        // The degree sign rides with the number so they scale together.
        Text(
          '${weather.temperatureC.round()}°',
          style: AppTypography.hero(foreground),
        ),
        Text(
          weatherLabelFor(weather.weatherCode),
          style: AppTypography.body(foreground),
        ),
        if (high != null && low != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${high!.round()}° / ${low!.round()}°',
            style: AppTypography.label(foreground),
          ),
        ],
      ],
    );
  }
}
