import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/historical_api.dart';

void main() {
  group('HistoricalCoverage.fromJson', () {
    test('parses a real-shaped /historical/available entry (verified live)',
        () {
      final coverage = HistoricalCoverage.fromJson({
        'location_name': 'Pune',
        'latitude': 18.52,
        'longitude': 73.86,
        'dates': ['2024-07-15', '2024-01-15', '2023-07-15'],
      });

      expect(coverage.locationName, 'Pune');
      expect(coverage.latitude, 18.52);
      expect(coverage.longitude, 73.86);
      expect(coverage.dates, ['2024-07-15', '2024-01-15', '2023-07-15']);
    });

    test('an empty dates list parses cleanly (a location with no readings '
        'left after the seed table was truncated)', () {
      final coverage = HistoricalCoverage.fromJson({
        'location_name': 'Bhagalpur',
        'latitude': 25.27,
        'longitude': 87.23,
        'dates': <String>[],
      });

      expect(coverage.dates, isEmpty);
    });
  });

  group('HistoricalReading.fromJson', () {
    test('parses a real-shaped /historical response (Pune, verified live)',
        () {
      final reading = HistoricalReading.fromJson({
        'location_name': 'Pune',
        'latitude': 18.52,
        'longitude': 73.86,
        'observation_date': '2024-07-15',
        'temp_2m_c': 25.378503417968773,
        'dewpoint_2m_c': 22.637597656250023,
        'precip_mm': 0.18262863159179688,
        'wind_speed_10m_kmh': 8.732189204079713,
        'wind_direction_10m_deg': 262.86885893510464,
        'mslp_hpa': 1001.87625,
      });

      expect(reading.locationName, 'Pune');
      expect(reading.observationDate, '2024-07-15');
      expect(reading.temp2mC, closeTo(25.3785, 0.0001));
      expect(reading.dewpoint2mC, closeTo(22.6376, 0.0001));
      expect(reading.precipMm, closeTo(0.1826, 0.0001));
      expect(reading.windSpeed10mKmh, closeTo(8.7322, 0.0001));
      expect(reading.windDirection10mDeg, closeTo(262.8689, 0.0001));
      expect(reading.mslpHpa, 1001.87625);
    });

    test('accepts a whole-number field sent as an int-shaped JSON number',
        () {
      // Mirrors the same caveat metar_api_test.dart/nwp_api_test.dart pin:
      // a Float column can arrive as a JSON integer literal.
      final reading = HistoricalReading.fromJson({
        'location_name': 'Pune',
        'latitude': 18.52,
        'longitude': 73.86,
        'observation_date': '2024-01-15',
        'temp_2m_c': 20,
        'mslp_hpa': 1005,
      });

      expect(reading.temp2mC, 20.0);
      expect(reading.mslpHpa, 1005.0);
    });

    test(
        'every reading field stays null when absent — never becomes 0, '
        'which would assert a real measurement', () {
      final reading = HistoricalReading.fromJson({
        'location_name': 'Pune',
        'latitude': 18.52,
        'longitude': 73.86,
        'observation_date': '2024-07-15',
        'temp_2m_c': null,
        'dewpoint_2m_c': null,
        'precip_mm': null,
        'wind_speed_10m_kmh': null,
        'wind_direction_10m_deg': null,
        'mslp_hpa': null,
      });

      expect(reading.temp2mC, isNull);
      expect(reading.dewpoint2mC, isNull);
      expect(reading.precipMm, isNull);
      expect(reading.windSpeed10mKmh, isNull);
      expect(reading.windDirection10mDeg, isNull);
      expect(reading.mslpHpa, isNull);
    });
  });
}
