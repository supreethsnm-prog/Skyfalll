import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/air_quality_api.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/weather_icon.dart';
import '../weather_label.dart';

/// Home's supplementary panels, all bound to real backend data.
///
/// Every value here is nullable upstream. The rule throughout this file:
/// **a tile with no value is not rendered at all.** It is never a dash,
/// never a zero, never "--". Google Weather omits tiles it has no data
/// for, and a "0" UV index or "0 hPa" reads as a real measurement rather
/// than as absent data — which on a disaster-advisory app is the kind of
/// thing that gets believed.

/// The air-quality pill under the temperature. Returns an empty box when
/// there is no reading, so the caller needs no null check of its own.
class AqiPill extends StatelessWidget {
  const AqiPill({super.key, required this.airQuality, required this.foreground});

  final AirQuality? airQuality;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final aqi = airQuality?.usAqi;
    final band = airQuality?.bandLabel;
    if (aqi == null || band == null) return const SizedBox.shrink();

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
            'AQI ${aqi.round()} · $band',
            style: AppTypography.label(foreground),
          ),
        ],
      ),
    );
  }
}

/// The hourly strip. Horizontally scrollable, one column per hour, with a
/// bar under each temperature standing in for Google Weather's line graph
/// — a line through this few points reads as noise at phone width.
class HourlyPanel extends StatelessWidget {
  const HourlyPanel({super.key, required this.hours, required this.foreground});

  final List<HourlyPoint> hours;
  final Color foreground;

  /// Clock time from an Open-Meteo ISO local timestamp, e.g. "15:00".
  /// Falls back to the raw string rather than throwing — one odd label
  /// beats a crashed screen.
  static String _label(String time, bool isFirst) {
    if (isFirst) return 'Now';
    final t = DateTime.tryParse(time);
    if (t == null) return time;
    return '${t.hour.toString().padLeft(2, '0')}:00';
  }

  @override
  Widget build(BuildContext context) {
    if (hours.isEmpty) return const SizedBox.shrink();

    final temps = hours.map((h) => h.temperatureC);
    final min = temps.reduce((a, b) => a < b ? a : b);
    final max = temps.reduce((a, b) => a > b ? a : b);
    // Guard a flat series: every bar the same height beats a divide by ~0.
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
                for (var i = 0; i < hours.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${hours[i].temperatureC.round()}°',
                          style: AppTypography.label(foreground),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Bar height encodes the temperature within this
                        // window's own range, so the shape of the day is
                        // readable at a glance.
                        Container(
                          width: 3,
                          height: 12 +
                              28 * ((hours[i].temperatureC - min) / span),
                          decoration: BoxDecoration(
                            color: foreground.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Icon(
                          weatherIconFor(hours[i].weatherCode),
                          size: AppRadius.iconSize,
                          color: foreground,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _label(hours[i].time, i == 0),
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

/// The grid of current-conditions detail. Tiles without a value are
/// dropped before layout, so the grid closes up rather than showing gaps.
class DetailGrid extends StatelessWidget {
  const DetailGrid({
    super.key,
    required this.weather,
    required this.foreground,
    this.uvIndexMax,
    this.airQuality,
  });

  final CurrentWeather weather;
  final Color foreground;
  final double? uvIndexMax;
  final AirQuality? airQuality;

  /// WHO/WMO UV exposure bands.
  static String _uvBand(double uv) {
    if (uv < 3) return 'Low';
    if (uv < 6) return 'Moderate';
    if (uv < 8) return 'High';
    if (uv < 11) return 'Very high';
    return 'Extreme';
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <({IconData icon, String label, String value, String? sub})>[
      if (weather.apparentTemperatureC != null)
        (
          icon: Icons.thermostat,
          label: 'Feels like',
          value: '${weather.apparentTemperatureC!.round()}°',
          sub: null,
        ),
      // UV comes from the CURRENT hour, never from the day's peak. Showing
      // the peak here told a user in Dharwad the UV index was 9 ("Very
      // high") at 21:09, after dark. The peak is still worth knowing, so
      // it rides along as the subtitle where it is labelled as a peak.
      if (weather.uvIndex != null)
        (
          icon: Icons.wb_sunny_outlined,
          label: 'UV index',
          value: weather.uvIndex!.round().toString(),
          sub: uvIndexMax == null
              ? _uvBand(weather.uvIndex!)
              : '${_uvBand(weather.uvIndex!)} · peak ${uvIndexMax!.round()}',
        ),
      (
        icon: Icons.water_drop_outlined,
        label: 'Humidity',
        value: '${weather.humidityPct.round()}%',
        sub: weather.dewPointC == null
            ? null
            : 'Dew pt ${weather.dewPointC!.round()}°',
      ),
      (
        icon: Icons.air,
        label: 'Wind',
        value: '${weather.windSpeedKmh.round()} km/h',
        sub: windDirectionLabel(weather.windDirectionDeg),
      ),
      if (weather.pressureHpa != null)
        (
          icon: Icons.speed,
          label: 'Pressure',
          value: weather.pressureHpa!.round().toString(),
          sub: 'hPa',
        ),
      if (weather.visibilityKm != null)
        (
          icon: Icons.visibility_outlined,
          label: 'Visibility',
          value: '${weather.visibilityKm!.toStringAsFixed(1)} km',
          sub: null,
        ),
      if (airQuality?.pm25 != null)
        (
          icon: Icons.blur_on,
          label: 'PM2.5',
          value: airQuality!.pm25!.round().toString(),
          sub: 'µg/m³',
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();

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
                Text(
                  tile.sub ?? '',
                  style: AppTypography.caption(foreground),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Sunrise and sunset for today. Renders nothing without both.
class SunPanel extends StatelessWidget {
  const SunPanel({
    super.key,
    required this.foreground,
    this.sunrise,
    this.sunset,
  });

  /// Upstream ISO strings, formatted here for display.
  final String? sunrise;
  final String? sunset;
  final Color foreground;

  static String? _clock(String? iso) {
    if (iso == null) return null;
    final t = DateTime.tryParse(iso);
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final rise = _clock(sunrise);
    final set = _clock(sunset);
    if (rise == null || set == null) return const SizedBox.shrink();

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
                time: rise,
                foreground: foreground,
              ),
              _SunEnd(
                icon: Icons.nightlight_outlined,
                label: 'Sunset',
                time: set,
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
