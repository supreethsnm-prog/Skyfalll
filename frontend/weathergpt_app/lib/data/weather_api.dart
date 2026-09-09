import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// Converts a JSON number to double regardless of whether it arrived
/// as an int-shaped or double-shaped literal — `humidity_pct` and
/// `wind_direction_deg` are Float columns in the backend
/// (backend/app/models.py) but a whole-number value can arrive as a
/// JSON integer depending on serialization.
double _asDouble(dynamic value) => (value as num).toDouble();

class CurrentWeather {
  final double temperatureC;
  final double humidityPct;
  final int weatherCode;
  final double windSpeedKmh;
  final double windDirectionDeg;
  final String observedAt;
  final String timezone;

  const CurrentWeather({
    required this.temperatureC,
    required this.humidityPct,
    required this.weatherCode,
    required this.windSpeedKmh,
    required this.windDirectionDeg,
    required this.observedAt,
    required this.timezone,
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
    );
  }
}

class ForecastDay {
  final String forecastDate;
  final int weatherCode;
  final double tempMaxC;
  final double tempMinC;

  const ForecastDay({
    required this.forecastDate,
    required this.weatherCode,
    required this.tempMaxC,
    required this.tempMinC,
  });

  factory ForecastDay.fromJson(Map<String, dynamic> json) {
    return ForecastDay(
      forecastDate: json['forecast_date'] as String,
      weatherCode: json['weather_code'] as int,
      tempMaxC: _asDouble(json['temp_max_c']),
      tempMinC: _asDouble(json['temp_min_c']),
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
