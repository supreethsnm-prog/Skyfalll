import 'package:flutter/material.dart';

/// Broad time-of-day bucket used to pick a sky gradient for the Home
/// screen background. Derived from the device clock against the
/// location's `timezone` (see docs/superpowers/specs/
/// 2026-09-09-flutter-design-literal.md §6.1).
enum SkyTimeOfDay { dawn, day, dusk, night }

/// Weather condition bucket used to pick a sky gradient. Mirrors the WMO
/// code ranges already encoded in [weatherIconFor]
/// (lib/shared/widgets/weather_icon.dart) — the two mappings must not
/// drift apart, so any change to one's ranges should be mirrored in the
/// other.
enum SkyCondition { clear, cloudy, fog, rain, snow, thunderstorm }

/// Buckets the local wall-clock time into a [SkyTimeOfDay].
///
/// - dawn: 05:00-07:59
/// - day: 08:00-16:59
/// - dusk: 17:00-19:59
/// - night: 20:00-04:59
SkyTimeOfDay skyTimeOfDayFor(DateTime local) {
  final hour = local.hour;
  if (hour >= 5 && hour < 8) return SkyTimeOfDay.dawn;
  if (hour >= 8 && hour < 17) return SkyTimeOfDay.day;
  if (hour >= 17 && hour < 20) return SkyTimeOfDay.dusk;
  return SkyTimeOfDay.night;
}

/// Buckets an Open-Meteo WMO `weather_code` into a [SkyCondition].
///
/// These ranges are intentionally identical to [weatherIconFor]'s
/// (lib/shared/widgets/weather_icon.dart) — read that file before
/// changing either mapping:
///
/// | weather_icon.dart range | icon                  | SkyCondition     |
/// |--------------------------|------------------------|-----------------|
/// | 0                        | wb_sunny_outlined      | clear           |
/// | 1-2                      | wb_cloudy_outlined     | cloudy          |
/// | 3                        | cloud_outlined         | cloudy          |
/// | 45, 48                   | foggy                  | fog             |
/// | 51-57                    | grain                  | rain            |
/// | 61-67                    | water_drop_outlined    | rain            |
/// | 71-77                    | ac_unit                | snow            |
/// | 80-82                    | water_drop             | rain            |
/// | 85-86                    | ac_unit                | snow            |
/// | 95-99                    | thunderstorm_outlined  | thunderstorm    |
/// | anything else            | help_outline           | cloudy (fallback) |
SkyCondition skyConditionFor(int weatherCode) {
  if (weatherCode == 0) return SkyCondition.clear;
  if (weatherCode >= 1 && weatherCode <= 2) return SkyCondition.cloudy;
  if (weatherCode == 3) return SkyCondition.cloudy;
  if (weatherCode == 45 || weatherCode == 48) return SkyCondition.fog;
  if (weatherCode >= 51 && weatherCode <= 57) return SkyCondition.rain;
  if (weatherCode >= 61 && weatherCode <= 67) return SkyCondition.rain;
  if (weatherCode >= 71 && weatherCode <= 77) return SkyCondition.snow;
  if (weatherCode >= 80 && weatherCode <= 82) return SkyCondition.rain;
  if (weatherCode >= 85 && weatherCode <= 86) return SkyCondition.snow;
  if (weatherCode >= 95 && weatherCode <= 99) return SkyCondition.thunderstorm;
  return SkyCondition.cloudy;
}

/// Explicit (top, middle, base) colour triples for every
/// [SkyTimeOfDay] x [SkyCondition] combination.
///
/// `day/cloudy` is pinned to the values sampled directly from
/// `Home1.jpeg` (`#C8D3E9` -> `#7995C4` -> `#93A8C7`, see spec §6.1) and
/// must not be changed. Every other triple is designed work: it follows
/// the same structure the sample shows — a lighter top, a more
/// saturated/darker middle, and a lighter base — shifted in hue and
/// value per time-of-day and desaturated/darkened per condition. Night
/// triples are kept well below 0.35 luminance (typically under 0.05) so
/// white foreground text stays readable against every condition.
const Map<SkyTimeOfDay, Map<SkyCondition, List<Color>>> _skyGradients = {
  SkyTimeOfDay.dawn: {
    SkyCondition.clear: [
      Color(0xFFF7D9C4),
      Color(0xFFE8957B),
      Color(0xFFF0B99C),
    ],
    SkyCondition.cloudy: [
      Color(0xFFE4C9D6),
      Color(0xFFA87F97),
      Color(0xFFC7A8B8),
    ],
    SkyCondition.fog: [
      Color(0xFFDDD3D0),
      Color(0xFFB7A8A4),
      Color(0xFFCDBDB8),
    ],
    SkyCondition.rain: [
      Color(0xFFB9AFC0),
      Color(0xFF6E6580),
      Color(0xFF8D84A0),
    ],
    SkyCondition.snow: [
      Color(0xFFDCE0E8),
      Color(0xFFA9B3C9),
      Color(0xFFC4CBDA),
    ],
    SkyCondition.thunderstorm: [
      Color(0xFF7C6F84),
      Color(0xFF423653),
      Color(0xFF5C4F6E),
    ],
  },
  SkyTimeOfDay.day: {
    SkyCondition.clear: [
      Color(0xFFA9CBEE),
      Color(0xFF4C8FDD),
      Color(0xFF7FB2E4),
    ],
    // Pinned reference: sampled from Home1.jpeg. Do not change.
    SkyCondition.cloudy: [
      Color(0xFFC8D3E9),
      Color(0xFF7995C4),
      Color(0xFF93A8C7),
    ],
    SkyCondition.fog: [
      Color(0xFFD6D9DC),
      Color(0xFF9AA3AC),
      Color(0xFFB7BEC4),
    ],
    SkyCondition.rain: [
      Color(0xFFA9B2C4),
      Color(0xFF5A6B8C),
      Color(0xFF7C8CAA),
    ],
    SkyCondition.snow: [
      Color(0xFFD3E1EE),
      Color(0xFF8FAAC9),
      Color(0xFFAEC2D9),
    ],
    SkyCondition.thunderstorm: [
      Color(0xFF7E88A0),
      Color(0xFF3A4260),
      Color(0xFF5C6584),
    ],
  },
  SkyTimeOfDay.dusk: {
    SkyCondition.clear: [
      Color(0xFFF6B87E),
      Color(0xFFD8637A),
      Color(0xFF8F5C8C),
    ],
    SkyCondition.cloudy: [
      Color(0xFFD9A6A0),
      Color(0xFF8F5F76),
      Color(0xFF6E5A82),
    ],
    SkyCondition.fog: [
      Color(0xFFC9B7B2),
      Color(0xFF998D95),
      Color(0xFF7C7488),
    ],
    SkyCondition.rain: [
      Color(0xFF9E8BA0),
      Color(0xFF5C4E70),
      Color(0xFF453A5C),
    ],
    SkyCondition.snow: [
      Color(0xFFC7C3D6),
      Color(0xFF8288AC),
      Color(0xFF625E82),
    ],
    SkyCondition.thunderstorm: [
      Color(0xFF6E5A72),
      Color(0xFF362A46),
      Color(0xFF241C32),
    ],
  },
  SkyTimeOfDay.night: {
    SkyCondition.clear: [
      Color(0xFF2A3B66),
      Color(0xFF16213D),
      Color(0xFF1F2C4D),
    ],
    SkyCondition.cloudy: [
      Color(0xFF313A52),
      Color(0xFF1C2233),
      Color(0xFF262D42),
    ],
    SkyCondition.fog: [
      Color(0xFF3A3D45),
      Color(0xFF24262C),
      Color(0xFF2E3138),
    ],
    SkyCondition.rain: [
      Color(0xFF232B3D),
      Color(0xFF12161F),
      Color(0xFF1A2029),
    ],
    SkyCondition.snow: [
      Color(0xFF2E3750),
      Color(0xFF1A2036),
      Color(0xFF232B44),
    ],
    SkyCondition.thunderstorm: [
      Color(0xFF241B2E),
      Color(0xFF120D18),
      Color(0xFF1B1422),
    ],
  },
};

/// Returns the Home screen sky background gradient for a given
/// [SkyTimeOfDay] and [SkyCondition]. Always top-to-bottom with at least
/// three stops.
LinearGradient skyGradient(SkyTimeOfDay time, SkyCondition condition) {
  final colors = _skyGradients[time]![condition]!;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
  );
}
