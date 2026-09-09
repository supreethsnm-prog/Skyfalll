/// ⚠️ PLACEHOLDER DATA — NOT FROM THE BACKEND. REPLACE BEFORE THE DEMO.
///
/// Google Weather's home screen shows air quality, UV, pressure, feels-like,
/// visibility, sunrise/sunset and an hourly graph. The backend currently
/// requests none of those from Open-Meteo, so this file supplies stand-in
/// values so the screen can be laid out and screenshotted for the pitch
/// deck ahead of the real integration.
///
/// **Every value here is invented.** They are plausible for the Indian
/// monsoon rather than random, but they are not measurements, they do not
/// change with location, and they do not refresh. Nothing in this file may
/// be presented as a real reading.
///
/// ## Replacing this with real data
///
/// All of it is available from the provider already in use, on the same
/// free endpoint, with no API key:
///
/// | Field here        | Open-Meteo field                  | Where     |
/// |-------------------|-----------------------------------|-----------|
/// | [feelsLikeC]      | `apparent_temperature`            | `current` |
/// | [uvIndex]         | `uv_index` / `uv_index_max`       | `hourly`/`daily` |
/// | [pressureHpa]     | `pressure_msl`                    | `current` |
/// | [visibilityKm]    | `visibility`                      | `hourly`  |
/// | [dewPointC]       | `dew_point_2m`                    | `current` |
/// | [sunrise]/[sunset]| `sunrise`, `sunset`               | `daily`   |
/// | [hourly]          | `temperature_2m` + `weather_code` | `hourly`  |
/// | [aqi]             | `us_aqi`                          | Open-Meteo's separate air-quality endpoint |
///
/// The change is `backend/app/providers/open_meteo.py` (add the field names
/// to `_CURRENT_FIELDS` / `_DAILY_FIELDS`, plus one call to the air-quality
/// endpoint), then the model, schema and route. Delete this file at that
/// point — do not leave it as a fallback, or a silent fetch failure will
/// quietly show invented numbers instead of an error.
library;

/// One point on the hourly strip.
class DemoHour {
  const DemoHour({
    required this.label,
    required this.temperatureC,
    required this.weatherCode,
  });

  final String label;
  final double temperatureC;
  final int weatherCode;
}

/// Stand-in current-conditions detail. See the file-level warning.
class DemoMetrics {
  const DemoMetrics._();

  /// Humid monsoon air reads warmer than the thermometer.
  static const double feelsLikeC = 27.6;

  /// 0-11+. 7 is "High" — typical for an Indian afternoon under broken cloud.
  static const double uvIndex = 7;

  /// US AQI. 156 is "Unhealthy", a realistic post-monsoon Delhi figure.
  static const int aqi = 156;

  static const double pressureHpa = 1004;
  static const double visibilityKm = 6.4;
  static const double dewPointC = 21.3;

  static const String sunrise = '06:12';
  static const String sunset = '18:42';

  /// A monsoon afternoon: warm, clouding over, showers by evening.
  static const List<DemoHour> hourly = [
    DemoHour(label: 'Now', temperatureC: 24.4, weatherCode: 3),
    DemoHour(label: '3pm', temperatureC: 25.1, weatherCode: 3),
    DemoHour(label: '4pm', temperatureC: 25.4, weatherCode: 80),
    DemoHour(label: '5pm', temperatureC: 24.8, weatherCode: 61),
    DemoHour(label: '6pm', temperatureC: 23.9, weatherCode: 63),
    DemoHour(label: '7pm', temperatureC: 23.2, weatherCode: 63),
    DemoHour(label: '8pm', temperatureC: 22.8, weatherCode: 61),
    DemoHour(label: '9pm', temperatureC: 22.4, weatherCode: 80),
  ];

  /// US AQI band label. Boundaries follow the EPA's published scale.
  static String get aqiLabel {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    if (aqi <= 150) return 'Unhealthy for sensitive groups';
    if (aqi <= 200) return 'Unhealthy';
    if (aqi <= 300) return 'Very unhealthy';
    return 'Hazardous';
  }

  /// WHO/WMO UV exposure bands.
  static String get uvLabel {
    if (uvIndex < 3) return 'Low';
    if (uvIndex < 6) return 'Moderate';
    if (uvIndex < 8) return 'High';
    if (uvIndex < 11) return 'Very high';
    return 'Extreme';
  }
}
