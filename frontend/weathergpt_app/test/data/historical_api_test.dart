import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/historical_api.dart';

void main() {
  group('ArchiveReading.fromJson', () {
    test('parses a real-shaped Open-Meteo Archive daily entry (verified '
        'live against archive-api.open-meteo.com)', () {
      final reading = ArchiveReading.fromJson({
        'date': '2024-07-15',
        'temp_max_c': 24.0,
        'temp_min_c': 21.4,
        'temp_mean_c': 22.3,
        'precip_sum_mm': 20.5,
        'wind_speed_max_kmh': 25.8,
        'wind_direction_dominant_deg': 247,
      });

      expect(reading.date, '2024-07-15');
      expect(reading.tempMaxC, 24.0);
      expect(reading.tempMinC, 21.4);
      expect(reading.tempMeanC, 22.3);
      expect(reading.precipSumMm, 20.5);
      expect(reading.windSpeedMaxKmh, 25.8);
      expect(reading.windDirectionDominantDeg, 247);
    });

    test('accepts a whole-number field sent as an int-shaped JSON number',
        () {
      final reading = ArchiveReading.fromJson({
        'date': '2024-07-15',
        'temp_max_c': 24,
        'wind_direction_dominant_deg': 247,
      });

      expect(reading.tempMaxC, 24.0);
      expect(reading.windDirectionDominantDeg, 247.0);
    });

    test(
        'every field stays null when absent — never becomes 0, which would '
        'assert a real measurement', () {
      final reading = ArchiveReading.fromJson({
        'date': '1940-01-01',
        'temp_max_c': null,
        'temp_min_c': null,
        'temp_mean_c': null,
        'precip_sum_mm': null,
        'wind_speed_max_kmh': null,
        'wind_direction_dominant_deg': null,
      });

      expect(reading.tempMaxC, isNull);
      expect(reading.tempMinC, isNull);
      expect(reading.tempMeanC, isNull);
      expect(reading.precipSumMm, isNull);
      expect(reading.windSpeedMaxKmh, isNull);
      expect(reading.windDirectionDominantDeg, isNull);
    });
  });

  group('HistoricalArchive.fromJson', () {
    test('parses the reading plus the previous-year comparison reading', () {
      final archive = HistoricalArchive.fromJson({
        'latitude': 15.36,
        'longitude': 75.12,
        'location_name': 'Hubballi',
        'reading': {
          'date': '2024-07-15',
          'temp_max_c': 24.0,
          'temp_min_c': 21.4,
          'temp_mean_c': 22.3,
          'precip_sum_mm': 20.5,
          'wind_speed_max_kmh': 25.8,
          'wind_direction_dominant_deg': 247,
        },
        'previous_year_reading': {
          'date': '2023-07-15',
          'temp_max_c': 23.1,
          'temp_min_c': 20.0,
          'temp_mean_c': 21.5,
          'precip_sum_mm': 5.0,
          'wind_speed_max_kmh': 18.0,
          'wind_direction_dominant_deg': 200,
        },
      });

      expect(archive.locationName, 'Hubballi');
      expect(archive.reading.date, '2024-07-15');
      expect(archive.previousYearReading?.date, '2023-07-15');
      expect(archive.previousYearReading?.tempMaxC, 23.1);
    });

    test('previousYearReading is null when the backend has no data for '
        'that earlier date', () {
      final archive = HistoricalArchive.fromJson({
        'latitude': 15.36,
        'longitude': 75.12,
        'location_name': null,
        'reading': {'date': '1940-01-01'},
        'previous_year_reading': null,
      });

      expect(archive.previousYearReading, isNull);
      expect(archive.locationName, isNull);
    });
  });
}
