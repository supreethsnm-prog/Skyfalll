import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Converts a JSON number to double regardless of whether it arrived
/// as an int-shaped or double-shaped literal — `humidity_pct` and
/// `wind_direction_deg` are Float columns in the backend
/// (backend/app/models.py) but a whole-number value can arrive as a
/// JSON integer depending on serialization.
double _asDouble(dynamic value) => (value as num).toDouble();

/// Nullable numeric field. Every rich weather field is optional upstream —
/// Open-Meteo omits them for some points — and a missing reading must stay
/// null rather than becoming 0, which would render as a real measurement.
double? _asDoubleOrNull(dynamic value) =>
    value == null ? null : (value as num).toDouble();

class CurrentWeather {
  final double temperatureC;
  final double humidityPct;
  final int weatherCode;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final String observedAt;
  final String timezone;

  /// All nullable — see [_asDoubleOrNull].
  final double? apparentTemperatureC;
  final double? pressureHpa;
  final double? dewPointC;
  final double? visibilityKm;

  /// The next 24 hours, already trimmed by the backend. Null when the
  /// cached reading predates the field.
  final List<HourlyPoint>? hourly;

  const CurrentWeather({
    required this.temperatureC,
    required this.humidityPct,
    required this.weatherCode,
    required this.windSpeedKmh,
    required this.windDirectionDeg,
    required this.observedAt,
    required this.timezone,
    this.apparentTemperatureC,
    this.pressureHpa,
    this.dewPointC,
    this.visibilityKm,
    this.hourly,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      temperatureC: _asDouble(json['temperature_c']),
      humidityPct: _asDouble(json['humidity_pct']),
      weatherCode: json['weather_code'] as int,
      windSpeedKmh: _asDouble(json['wind_speed_kmh']),
      windDirectionDeg: _asDouble(json['wind_direction_deg']),
      observedAt: json['observed_at'] as String,
      timezone: json['timezone'] as String,
      apparentTemperatureC: _asDoubleOrNull(json['apparent_temperature_c']),
      pressureHpa: _asDoubleOrNull(json['pressure_hpa']),
      dewPointC: _asDoubleOrNull(json['dew_point_c']),
      visibilityKm: _asDoubleOrNull(json['visibility_km']),
      hourly: (json['hourly'] as List<dynamic>?)
          ?.map((e) => HourlyPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ForecastDay {
  final String forecastDate;
  final int weatherCode;
  final double tempMaxC;
  final double tempMinC;

  /// Nullable, as on [CurrentWeather]. Sun times are the upstream ISO
  /// strings; the UI formats them for display.
  final double? uvIndexMax;
  final String? sunrise;
  final String? sunset;

  const ForecastDay({
    required this.forecastDate,
    required this.weatherCode,
    required this.tempMaxC,
    required this.tempMinC,
    this.uvIndexMax,
    this.sunrise,
    this.sunset,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> json) {
    return ForecastDay(
      forecastDate: json['forecast_date'] as String,
      weatherCode: json['weather_code'] as int,
      tempMaxC: _asDouble(json['temp_max_c']),
      tempMinC: _asDouble(json['temp_min_c']),
      uvIndexMax: _asDoubleOrNull(json['uv_index_max']),
      sunrise: json['sunrise'] as String?,
      sunset: json['sunset'] as String?,
    );
  }
}

/// One hour of the forecast strip.
class HourlyPoint {
  final String time;
  final double temperatureC;
  final int weatherCode;

  const HourlyPoint({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
  });

  factory HourlyPoint.fromJson(Map<String, dynamic> json) {
    return HourlyPoint(
      time: json['time'] as String,
      temperatureC: _asDouble(json['temperature_c']),
      weatherCode: json['weather_code'] as int,
    );
  }
}

/// Wraps `GET /weather` and `GET /forecast`.
class WeatherApi {
  final Dio _dio;

  WeatherApi(this._dio);

  Future<CurrentWeather> fetchCurrent(double lat, double lon) {
    return guardApi(() async {
      final response = await _dio.get<Map<String, dynamic>>(
        '/weather',
        queryParameters: {'lat': lat, 'lon': lon},
      );
      return CurrentWeather.fromJson(response.data!);
    });
  }

  Future<List<ForecastDay>> fetchForecast(
    double lat,
    double lon, {
    int days = 5,
  }) {
    return guardApi(() async {
      final response = await _dio.get<List<dynamic>>(
        '/forecast',
        queryParameters: {'lat': lat, 'lon': lon, 'days': days},
      );
      return response.data!
          .map((entry) => ForecastDay.fromJson(entry as Map<String, dynamic>))
          .toList();
    });
  }
}
