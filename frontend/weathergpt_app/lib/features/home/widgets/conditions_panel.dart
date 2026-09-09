import 'package:flutter/material.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../weather_label.dart';

/// Current-conditions detail, grouped into a [GlassPanel].
///
/// Shows humidity and wind, and nothing else, because those are the only
/// remaining fields `GET /weather` returns. Google Weather's home screen
/// also carries AQI, UV, pressure, "feels like", and sunrise/sunset — the
/// backend serves none of them, so they are absent rather than stubbed.
/// Do not add a tile here without an endpoint behind it.
class ConditionsPanel extends StatelessWidget {
  const ConditionsPanel({
    super.key,
    required this.weather,
    required this.foreground,
  });

  final CurrentWeather weather;

  /// From `skyForeground(...)` — see [HomeHero] for why this is injected.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.water_drop_outlined,
              label: 'Humidity',
              value: '${weather.humidityPct.round()}%',
              foreground: foreground,
            ),
          ),
          Expanded(
            child: _Stat(
              icon: Icons.air,
              label: 'Wind',
              value: '${weather.windSpeedKmh.round()} km/h '
                  '${windDirectionLabel(weather.windDirectionDeg)}',
              foreground: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: AppRadius.iconSize, color: foreground),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTypography.label(foreground)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTypography.body(foreground)),
      ],
    );
  }
}
