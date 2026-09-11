import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/weather_api.dart';
import '../../../l10n/app_strings.dart';
import '../weather_label.dart';

/// The Home screen's headline block, per `Home1.jpeg`: place name, a very
/// large temperature, and the condition beneath it — all sitting directly
/// on the sky with no card behind them.
///
/// [foreground] comes from `skyForeground(...)` and must be passed in
/// rather than read here: the caller is the only thing that knows which
/// sky is behind this, and the whole WCAG contract depends on that one
/// decision being made in one place.
class HomeHero extends ConsumerWidget {
  const HomeHero({
    super.key,
    required this.place,
    required this.weather,
    required this.foreground,
    this.high,
    this.low,
    this.onTapPlace,
  });

  final String place;
  final CurrentWeather weather;
  final Color foreground;

  /// Today's high/low, when a forecast is available. Omitted rather than
  /// faked when it is not — the backend's `/weather` has no such field.
  final double? high;
  final double? low;

  /// Opens location search. Null leaves the name as a plain label, which
  /// is what golden tests and any read-only use want.
  final VoidCallback? onTapPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(uiStringsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The place name doubles as the way to change it — the most
        // discoverable spot for "somewhere else", and where Google
        // Weather puts it too. The caret says it is tappable; a bare
        // label would not.
        Semantics(
          button: onTapPlace != null,
          label: '${s.changeLocation}. Currently $place',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onTapPlace,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      place,
                      style: AppTypography.title(foreground),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onTapPlace != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.expand_more,
                      size: AppRadius.iconSize,
                      color: foreground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // The degree sign rides with the number so they scale together.
        Text(
          '${weather.temperatureC.round()}°',
          style: AppTypography.hero(foreground),
        ),
        Text(
          weatherLabelFor(weather.weatherCode, s),
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
