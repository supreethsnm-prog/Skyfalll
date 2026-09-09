import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/weather_api.dart';

void main() {
  group('CurrentWeather.fromJson', () {
    test('parses a real-shaped weather response', () {
      final weather = CurrentWeather.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'temperature_c': 32.5,
        'humidity_pct': 41.0,
        'weather_code': 3,
        'wind_speed_kmh': 12.4,
        'wind_direction_deg': 270.0,
        'observed_at': '2026-09-09T10:00:00Z',
        'timezone': 'Asia/Kolkata',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(weather.temperatureC, 32.5);
      expect(weather.humidityPct, 41.0);
      expect(weather.weatherCode, 3);
      expect(weather.windSpeedKmh, 12.4);
      expect(weather.windDirectionDeg, 270.0);
      expect(weather.observedAt, '2026-09-09T10:00:00Z');
      expect(weather.timezone, 'Asia/Kolkata');
    });

    test('accepts a whole-number humidity/wind-direction sent as an int-shaped JSON number', () {
      // humidity_pct and wind_direction_deg are Float columns in the
      // backend (backend/app/models.py) — a whole-number value like
      // 40 may arrive as a JSON integer literal depending on the
      // serializer. fromJson must not assume `is double` fails on
      // an int-shaped number.
      final weather = CurrentWeather.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'temperature_c': 32,
        'humidity_pct': 40,
        'weather_code': 0,
        'wind_speed_kmh': 10,
        'wind_direction_deg': 90,
        'observed_at': '2026-09-09T10:00:00Z',
        'timezone': 'Asia/Kolkata',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(weather.humidityPct, 40.0);
      expect(weather.windDirectionDeg, 90.0);
    });
  });

  group('ForecastDay.fromJson', () {
    test('parses a real-shaped forecast day', () {
      final day = ForecastDay.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'forecast_date': '2026-09-10',
        'weather_code': 61,
        'temp_max_c': 30.0,
        'temp_min_c': 22.5,
        'precip_probability_pct': 60.0,
        'precip_sum_mm': 5.2,
        'wind_speed_max_kmh': 18.0,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(day.forecastDate, '2026-09-10');
      expect(day.weatherCode, 61);
      expect(day.tempMaxC, 30.0);
      expect(day.tempMinC, 22.5);
    });
  });
}
