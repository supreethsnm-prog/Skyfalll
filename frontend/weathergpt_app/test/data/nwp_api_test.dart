import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/nwp_api.dart';

void main() {
  group('NwpPoint.fromJson', () {
    test('parses a real-shaped NWP response', () {
      final point = NwpPoint.fromJson({
        'run_date': '20260909',
        'run_hour': '18',
        'forecast_hour': 0,
        'valid_time': '2026-09-09T18:00:00Z',
        'temp_2m_c': 32.09,
        'relative_humidity_2m_pct': 40.9,
        'wind_speed_10m_kmh': 5.8,
        'wind_direction_10m_deg': 233.67,
        'wind_gust_kmh': 9.42,
        'precip_rate_mmh': 0.0,
        'cape_j_per_kg': 0.0,
        'cin_j_per_kg': -0.29,
        'cloud_cover_pct': 0.0,
        'mslp_hpa': 1005.99,
      });

      expect(point.runDate, '20260909');
      expect(point.runHour, '18');
      expect(point.forecastHour, 0);
      expect(point.validTime, '2026-09-09T18:00:00Z');
      expect(point.temp2mC, 32.09);
      expect(point.relativeHumidity2mPct, 40.9);
      expect(point.windSpeed10mKmh, 5.8);
      expect(point.windDirection10mDeg, 233.67);
      expect(point.windGustKmh, 9.42);
      expect(point.precipRateMmh, 0.0);
      expect(point.capeJPerKg, 0.0);
      expect(point.cinJPerKg, -0.29);
      expect(point.cloudCoverPct, 0.0);
      expect(point.mslpHpa, 1005.99);
    });

    test(
        'every meteorological field stays null when the model omitted it — '
        'never becomes 0, which would assert a real measurement', () {
      final point = NwpPoint.fromJson({
        'run_date': '20260909',
        'run_hour': '18',
        'forecast_hour': 120,
        'valid_time': '2026-09-14T18:00:00Z',
        'temp_2m_c': null,
        'relative_humidity_2m_pct': null,
        'wind_speed_10m_kmh': null,
        'wind_direction_10m_deg': null,
        'wind_gust_kmh': null,
        'precip_rate_mmh': null,
        'cape_j_per_kg': null,
        'cin_j_per_kg': null,
        'cloud_cover_pct': null,
        'mslp_hpa': null,
      });

      expect(point.temp2mC, isNull);
      expect(point.relativeHumidity2mPct, isNull);
      expect(point.windSpeed10mKmh, isNull);
      expect(point.windDirection10mDeg, isNull);
      expect(point.windGustKmh, isNull);
      expect(point.precipRateMmh, isNull);
      expect(point.capeJPerKg, isNull);
      expect(point.cinJPerKg, isNull);
      expect(point.cloudCoverPct, isNull);
      expect(point.mslpHpa, isNull);
    });

    test(
        'accepts a whole-number CAPE/gust/pressure sent as an int-shaped '
        'JSON number', () {
      // These are Float columns in the backend but a whole-number value
      // can arrive as a JSON integer literal depending on serialization —
      // the same caveat weather_api_test.dart pins for humidity/wind
      // direction.
      final point = NwpPoint.fromJson({
        'run_date': '20260909',
        'run_hour': '18',
        'forecast_hour': 24,
        'valid_time': '2026-09-10T18:00:00Z',
        'cape_j_per_kg': 1500,
        'wind_gust_kmh': 70,
        'mslp_hpa': 1008,
      });

      expect(point.capeJPerKg, 1500.0);
      expect(point.windGustKmh, 70.0);
      expect(point.mslpHpa, 1008.0);
    });
  });
}
