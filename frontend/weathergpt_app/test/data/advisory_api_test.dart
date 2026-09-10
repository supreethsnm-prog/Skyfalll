import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/advisory_api.dart';

void main() {
  group('AgricultureAdvisory.fromJson', () {
    test('parses a real-shaped agriculture advisory response', () {
      final advisory = AgricultureAdvisory.fromJson({
        'latitude': 18.52,
        'longitude': 73.86,
        'crop': null,
        'generated_at': '2026-09-10T08:18:02.435422+05:30',
        'advisories': [
          'Heavy rain forecast (>=64.5mm/day) — avoid irrigation and hold '
              'off fertilizer/pesticide application until after the rain.',
        ],
        'active_alerts': [
          {
            'id': 1,
            'severity': 'Orange',
            'event_type': 'Heavy Rain',
            'area_description': 'Pune district',
            'latitude': 18.5,
            'longitude': 73.8,
          },
        ],
        'forecast_basis': [
          {
            'forecast_date': '2026-09-10',
            'weather_code': 61,
            'temp_max_c': 30.0,
            'temp_min_c': 22.5,
          },
        ],
      });

      expect(advisory.latitude, 18.52);
      expect(advisory.longitude, 73.86);
      expect(advisory.crop, isNull);
      expect(advisory.advisories, hasLength(1));
      expect(advisory.advisories.single, contains('Heavy rain forecast'));
      // Reuses AlertSummary.fromJson rather than a second parser.
      expect(advisory.activeAlerts.single.eventType, 'Heavy Rain');
      // Reuses ForecastDay.fromJson rather than a second parser.
      expect(advisory.forecastBasis.single.tempMaxC, 30.0);
    });

    test('parses a real crop value through unchanged', () {
      final advisory = AgricultureAdvisory.fromJson({
        'latitude': 18.52,
        'longitude': 73.86,
        'crop': 'rice',
        'generated_at': '2026-09-10T08:18:02.435422+05:30',
        'advisories': const [],
        'active_alerts': const [],
        'forecast_basis': const [],
      });

      expect(advisory.crop, 'rice');
      expect(advisory.advisories, isEmpty);
    });

    test('an empty advisories list parses cleanly — a normal, common outcome',
        () {
      final advisory = AgricultureAdvisory.fromJson({
        'latitude': 18.52,
        'longitude': 73.86,
        'crop': null,
        'generated_at': '2026-09-10T08:18:02.435422+05:30',
        'advisories': const [],
        'active_alerts': const [],
        'forecast_basis': const [],
      });

      expect(advisory.advisories, isEmpty);
    });
  });

  group('UrbanRiskSummary.fromJson', () {
    test('parses the three risk bands', () {
      final summary = UrbanRiskSummary.fromJson({
        'waterlogging_risk': 'LOW',
        'heat_risk': 'MODERATE',
        'wind_risk': 'HIGH',
      });

      expect(summary.waterloggingRisk, 'LOW');
      expect(summary.heatRisk, 'MODERATE');
      expect(summary.windRisk, 'HIGH');
    });

    test('passes through a value outside the four documented bands rather '
        'than rejecting it — the UI, not the parser, decides how to render '
        'an unrecognised band', () {
      final summary = UrbanRiskSummary.fromJson({
        'waterlogging_risk': 'UNKNOWN',
        'heat_risk': 'LOW',
        'wind_risk': 'LOW',
      });

      expect(summary.waterloggingRisk, 'UNKNOWN');
    });
  });

  group('UrbanAdvisory.fromJson', () {
    test('parses a real-shaped urban advisory response', () {
      final advisory = UrbanAdvisory.fromJson({
        'latitude': 28.61,
        'longitude': 77.21,
        'generated_at': '2026-09-10T08:18:02.435422+05:30',
        'risk_summary': {
          'waterlogging_risk': 'LOW',
          'heat_risk': 'LOW',
          'wind_risk': 'LOW',
        },
        'advisories': const [],
        'active_alerts': const [],
        'forecast_basis': const [],
      });

      expect(advisory.latitude, 28.61);
      expect(advisory.longitude, 77.21);
      expect(advisory.riskSummary.waterloggingRisk, 'LOW');
      expect(advisory.advisories, isEmpty);
    });
  });
}
