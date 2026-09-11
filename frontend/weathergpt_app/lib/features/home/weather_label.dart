import '../../l10n/app_strings.dart';

/// Human-readable condition text for an Open-Meteo WMO `weather_code`.
///
/// Lives here rather than beside [weatherIconFor] because
/// `lib/shared/widgets/weather_icon.dart` is a preserved integration file
/// this redesign must not modify. The code ranges below intentionally
/// mirror that file's and `skyConditionFor`'s — all three must move
/// together if the WMO buckets are ever changed.
///
/// Codes come from the WMO 4677 table as Open-Meteo publishes it; the
/// backend passes them through untouched (see backend/app/weather.py).
String weatherLabelFor(int weatherCode, [AppStrings? s]) {
  if (s != null) return s.weatherLabel(weatherCode);
  switch (weatherCode) {
    case 0:
      return 'Clear sky';
    case 1:
      return 'Mainly clear';
    case 2:
      return 'Partly cloudy';
    case 3:
      return 'Overcast';
    case 45:
    case 48:
      return 'Fog';
    case 51:
    case 53:
    case 55:
      return 'Drizzle';
    case 56:
    case 57:
      return 'Freezing drizzle';
    case 61:
      return 'Light rain';
    case 63:
      return 'Moderate rain';
    case 65:
      return 'Heavy rain';
    case 66:
    case 67:
      return 'Freezing rain';
    case 71:
      return 'Light snow';
    case 73:
      return 'Moderate snow';
    case 75:
      return 'Heavy snow';
    case 77:
      return 'Snow grains';
    case 80:
      return 'Rain showers';
    case 81:
      return 'Heavy showers';
    case 82:
      return 'Violent showers';
    case 85:
    case 86:
      return 'Snow showers';
    case 95:
      return 'Thunderstorm';
    case 96:
    case 99:
      return 'Thunderstorm with hail';
    default:
      // Unknown codes are reported honestly rather than guessed at.
      return 'Unknown conditions';
  }
}

/// 16-point compass abbreviation for a meteorological wind direction in
/// degrees (0 = from the north, increasing clockwise).
///
/// Normalises out-of-range and negative values rather than asserting: the
/// upstream feed is a third party, and a wind arrow is not worth crashing
/// a disaster-alert screen over.
String windDirectionLabel(double degrees) {
  const points = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', //
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  final normalised = ((degrees % 360) + 360) % 360;
  final index = ((normalised / 22.5).round()) % 16;
  return points[index];
}
