import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/weather_icon.dart';
import '../demo_metrics.dart';
import '../weather_label.dart';

/// ⚠️ Every widget in this file renders [DemoMetrics] — invented values,
/// not backend readings. See `demo_metrics.dart` for what replaces them.

/// The air-quality pill that sits under the temperature on Google
/// Weather's home screen.
class AqiPill extends StatelessWidget {
  const AqiPill({super.key, required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: BorderRadius.circular(AppRadius.composerHeight / 2),
        border: Border.all(color: foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.masks_outlined, size: 16, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'AQI ${DemoMetrics.aqi} · ${DemoMetrics.aqiLabel}',
            style: AppTypography.label(foreground),
          ),
        ],
      ),
    );
  }
}

/// The hourly strip. Horizontally scrollable, one column per hour, with a
/// simple bar under each temperature standing in for Google Weather's
/// line graph — a line chart of eight points reads as noise at this size.
class HourlyPanel extends StatelessWidget {
  const HourlyPanel({super.key, required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    const hours = DemoMetrics.hourly;
    final temps = hours.map((h) => h.temperatureC);
    final min = temps.reduce((a, b) => a < b ? a : b);
    final max = temps.reduce((a, b) => a > b ? a : b);
    final span = (max - min).abs() < 0.1 ? 1.0 : max - min;

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Hourly forecast', style: AppTypography.label(foreground)),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final hour in hours)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${hour.temperatureC.round()}°',
                          style: AppTypography.label(foreground),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Bar height encodes the temperature within the
                        // window's own range, so the shape of the
                        // afternoon is readable at a glance.
                        Container(
                          width: 3,
                          height: 12 +
                              28 * ((hour.temperatureC - min) / span),
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Icon(
                          weatherIconFor(hour.weatherCode),
                          size: AppRadius.iconSize,
                          color: foreground,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          hour.label,
                          style: AppTypography.caption(foreground),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The grid of current-conditions detail. Humidity and wind are real
/// (`GET /weather` returns them); everything else is [DemoMetrics].
class DetailGrid extends StatelessWidget {
  const DetailGrid({
    super.key,
    required this.weather,
    required this.foreground,
  });

  final CurrentWeather weather;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final tiles = <({IconData icon, String label, String value, String sub})>[
      (
        icon: Icons.thermostat,
        label: 'Feels like',
        value: '${DemoMetrics.feelsLikeC.round()}°',
        sub: 'Humid',
      ),
      (
        icon: Icons.wb_sunny_outlined,
        label: 'UV index',
        value: DemoMetrics.uvIndex.round().toString(),
        sub: DemoMetrics.uvLabel,
      ),
      (
        icon: Icons.water_drop_outlined,
        label: 'Humidity',
        value: '${weather.humidityPct.round()}%',
        sub: 'Dew pt ${DemoMetrics.dewPointC.round()}°',
      ),
      (
        icon: Icons.air,
        label: 'Wind',
        value: '${weather.windSpeedKmh.round()} km/h',
        sub: windDirectionLabel(weather.windDirectionDeg),
      ),
      (
        icon: Icons.speed,
        label: 'Pressure',
        value: '${DemoMetrics.pressureHpa.round()}',
        sub: 'hPa',
      ),
      (
        icon: Icons.visibility_outlined,
        label: 'Visibility',
        value: '${DemoMetrics.visibilityKm.toStringAsFixed(1)} km',
        sub: 'Reduced',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: [
        for (final tile in tiles)
          GlassPanel(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(tile.icon, size: 16, color: foreground),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        tile.label,
                        style: AppTypography.caption(foreground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(tile.value, style: AppTypography.title(foreground)),
                Text(tile.sub, style: AppTypography.caption(foreground)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Sunrise and sunset, with a simple arc showing where the sun sits
/// between them.
class SunPanel extends StatelessWidget {
  const SunPanel({super.key, required this.foreground});

  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Sun', style: AppTypography.label(foreground)),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SunEnd(
                icon: Icons.wb_twilight,
                label: 'Sunrise',
                time: DemoMetrics.sunrise,
                foreground: foreground,
              ),
              _SunEnd(
                icon: Icons.nightlight_outlined,
                label: 'Sunset',
                time: DemoMetrics.sunset,
                foreground: foreground,
                alignEnd: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SunEnd extends StatelessWidget {
  const _SunEnd({
    required this.icon,
    required this.label,
    required this.time,
    required this.foreground,
    this.alignEnd = false,
  });

  final IconData icon;
  final String label;
  final String time;
  final Color foreground;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTypography.caption(foreground)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(time, style: AppTypography.title(foreground)),
      ],
    );
  }
}
