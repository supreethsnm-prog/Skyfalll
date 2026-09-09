import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/alerts_api.dart';

void main() {
  group('AlertSummary.fromJson', () {
    test('parses a real-shaped alert with coordinates', () {
      final alert = AlertSummary.fromJson({
        'id': 1,
        'external_id': 'SACHET-123',
        'source': 'SACHET',
        'severity': 'Severe',
        'event_type': 'Flood',
        'area_description': 'Coastal Odisha',
        'effective_start_time': '2026-09-09T00:00:00Z',
        'effective_end_time': '2026-09-10T00:00:00Z',
        'warning_message': 'Heavy rainfall expected.',
        'latitude': 20.27,
        'longitude': 85.84,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(alert.id, 1);
      expect(alert.severity, 'Severe');
      expect(alert.eventType, 'Flood');
      expect(alert.areaDescription, 'Coastal Odisha');
      expect(alert.latitude, 20.27);
      expect(alert.longitude, 85.84);
    });

    test('parses an alert with null coordinates without throwing', () {
      final alert = AlertSummary.fromJson({
        'id': 2,
        'external_id': 'SACHET-124',
        'source': 'SACHET',
        'severity': 'Moderate',
        'event_type': 'Heatwave',
        'area_description': null,
        'effective_start_time': null,
        'effective_end_time': null,
        'warning_message': null,
        'latitude': null,
        'longitude': null,
        'fetched_at': '2026-09-09T10:05:00Z',
      });

      expect(alert.latitude, isNull);
      expect(alert.longitude, isNull);
    });
  });
}
