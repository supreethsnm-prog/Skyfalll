import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/aviation/airports.dart';

void main() {
  group('indianAirports', () {
    test('has 14 bundled airports with distinct ICAO codes', () {
      expect(indianAirports, hasLength(14));
      expect(indianAirports.map((a) => a.icao).toSet(), hasLength(14));
    });
  });

  group('nearestAirport', () {
    test('Pune resolves to VABB Mumbai, not VOHS Hyderabad or VOGO Goa '
        '(verified by great-circle distance: Mumbai ~122km vs Hyderabad '
        '~502km, Goa ~349km)', () {
      final airport = nearestAirport(18.5204, 73.8567);
      expect(airport.icao, 'VABB');
    });

    test('Bhagalpur resolves to VEPT Patna, not VECC Kolkata '
        '(verified by great-circle distance: Patna ~194km vs Kolkata '
        '~322km)', () {
      final airport = nearestAirport(25.2425, 86.9842);
      expect(airport.icao, 'VEPT');
    });

    test('a coordinate exactly on an airport resolves to that airport', () {
      final airport = nearestAirport(28.5665, 77.1031);
      expect(airport.icao, 'VIDP');
    });
  });

  group('distanceToAirportKm', () {
    test('is zero for the airport\'s own coordinates', () {
      final vidp = indianAirports.firstWhere((a) => a.icao == 'VIDP');
      final distance =
          distanceToAirportKm(vidp.latitude, vidp.longitude, vidp);
      expect(distance, closeTo(0, 0.001));
    });

    test('Pune to Mumbai is roughly 120km, not e.g. 300+km', () {
      final vabb = indianAirports.firstWhere((a) => a.icao == 'VABB');
      final distance = distanceToAirportKm(18.5204, 73.8567, vabb);
      expect(distance, greaterThan(100));
      expect(distance, lessThan(150));
    });
  });
}
