import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/geocoding_api.dart';

void main() {
  group('GeocodeResult.fromJson', () {
    test('parses a real-shaped geocode response', () {
      final result = GeocodeResult.fromJson({
        'query': 'mumbai',
        'display_name': 'Mumbai, Maharashtra, India',
        'latitude': 19.0760,
        'longitude': 72.8777,
        'country': 'India',
        'state': 'Maharashtra',
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(result.displayName, 'Mumbai, Maharashtra, India');
      expect(result.latitude, 19.0760);
      expect(result.longitude, 72.8777);
      expect(result.country, 'India');
      expect(result.state, 'Maharashtra');
    });
  });
}
