import 'package:flutter/material.dart';

/// Maps Open-Meteo's numeric WMO weather code — returned verbatim as
/// `weather_code` by the backend's `/weather` and `/forecast` endpoints
/// (see backend/app/weather/service.py and backend/app/forecast/service.py)
/// — to a representative Material icon. Codes follow the WMO 4677 table;
/// see https://open-meteo.com/en/docs for the full list.
IconData weatherIconFor(int weatherCode) {
  if (weatherCode == 0) return Icons.wb_sunny_outlined;
  if (weatherCode >= 1 && weatherCode <= 2) return Icons.wb_cloudy_outlined;
  if (weatherCode == 3) return Icons.cloud_outlined;
  if (weatherCode == 45 || weatherCode == 48) return Icons.foggy;
  if (weatherCode >= 51 && weatherCode <= 57) return Icons.grain;
  if (weatherCode >= 61 && weatherCode <= 67) return Icons.water_drop_outlined;
  if (weatherCode >= 71 && weatherCode <= 77) return Icons.ac_unit;
  if (weatherCode >= 80 && weatherCode <= 82) return Icons.water_drop;
  if (weatherCode >= 85 && weatherCode <= 86) return Icons.ac_unit;
  if (weatherCode >= 95 && weatherCode <= 99) return Icons.thunderstorm_outlined;
  return Icons.help_outline;
}
