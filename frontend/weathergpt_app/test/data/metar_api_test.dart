import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/metar_api.dart';

void main() {
  group('MetarReading.fromJson', () {
    test('parses a real-shaped METAR response (VIDP, verified live)', () {
      final reading = MetarReading.fromJson({
        'icao_id': 'VIDP',
        'raw_metar':
            'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
        'observed_at': '2026-09-10T02:30:00.000Z',
        'temperature_c': 29.0,
        'dewpoint_c': 22.0,
        'wind_dir_deg': 260.0,
        'wind_speed_kt': 9.0,
        'visibility_sm': 2.49,
        'flight_category': 'MVFR',
        'station_name': 'New Delhi/Gandhi Intl, DL, IN',
        'latitude': 28.567,
        'longitude': 77.117,
        'fetched_at': '2026-09-10T02:35:00.000Z',
      });

      expect(reading.icaoId, 'VIDP');
      expect(reading.rawMetar, contains('METAR VIDP'));
      expect(reading.observedAt, '2026-09-10T02:30:00.000Z');
      expect(reading.temperatureC, 29.0);
      expect(reading.dewpointC, 22.0);
      expect(reading.windDirDeg, 260.0);
      expect(reading.windSpeedKt, 9.0);
      expect(reading.visibilitySm, 2.49);
      expect(reading.flightCategory, 'MVFR');
      expect(reading.stationName, 'New Delhi/Gandhi Intl, DL, IN');
    });

    test(
        'every derived field stays null when the station under-reported — '
        'never becomes 0, which would assert a real measurement', () {
      final reading = MetarReading.fromJson({
        'icao_id': 'VOGO',
        'raw_metar': 'METAR VOGO 100230Z /////KT //// // ////// ////// NOSIG',
        'observed_at': '2026-09-10T02:30:00.000Z',
        'temperature_c': null,
        'dewpoint_c': null,
        'wind_dir_deg': null,
        'wind_speed_kt': null,
        'visibility_sm': null,
        'flight_category': null,
        'station_name': null,
      });

      expect(reading.temperatureC, isNull);
      expect(reading.dewpointC, isNull);
      expect(reading.windDirDeg, isNull);
      expect(reading.windSpeedKt, isNull);
      expect(reading.visibilitySm, isNull);
      expect(reading.flightCategory, isNull);
      expect(reading.stationName, isNull);
      expect(reading.visibilityKm, isNull);
    });

    test(
        'accepts a whole-number field sent as an int-shaped JSON number',
        () {
      // Mirrors the same caveat weather_api_test.dart/nwp_api_test.dart
      // pin: a Float column can arrive as a JSON integer literal.
      final reading = MetarReading.fromJson({
        'icao_id': 'VABB',
        'raw_metar': 'METAR VABB 100230Z 27010KT CAVOK 30/20 Q1010 NOSIG',
        'observed_at': '2026-09-10T02:30:00.000Z',
        'temperature_c': 30,
        'wind_dir_deg': 270,
        'wind_speed_kt': 10,
      });

      expect(reading.temperatureC, 30.0);
      expect(reading.windDirDeg, 270.0);
      expect(reading.windSpeedKt, 10.0);
    });
  });

  group('MetarReading.visibilityKm', () {
    test('converts statute miles to km (×1.609344)', () {
      const reading = MetarReading(
        icaoId: 'VIDP',
        rawMetar: 'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
        observedAt: '2026-09-10T02:30:00.000Z',
        visibilitySm: 2.49,
      );

      expect(reading.visibilityKm, closeTo(4.007, 0.001));
    });

    test('stays null when visibilitySm is null', () {
      const reading = MetarReading(
        icaoId: 'VIDP',
        rawMetar: 'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
        observedAt: '2026-09-10T02:30:00.000Z',
      );

      expect(reading.visibilityKm, isNull);
    });
  });
}
