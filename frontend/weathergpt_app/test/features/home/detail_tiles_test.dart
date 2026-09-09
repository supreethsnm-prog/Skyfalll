import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/air_quality_api.dart';
import 'package:weathergpt_app/data/weather_api.dart';
import 'package:weathergpt_app/features/home/widgets/detail_tiles.dart';

/// The rule these tests protect: a value the backend did not supply is
/// ABSENT from the screen, never rendered as 0 or "--".
///
/// Open-Meteo omits fields for some points, so this is a real runtime
/// state rather than a hypothetical. On a disaster-advisory app, a "0"
/// AQI or UV index reads as a measurement and gets believed.

const _bare = CurrentWeather(
  temperatureC: 24.4,
  humidityPct: 78,
  weatherCode: 61,
  windSpeedKmh: 18.2,
  windDirectionDeg: 247,
  observedAt: '2026-09-09T14:00',
  timezone: 'Asia/Kolkata',
  // Every optional field deliberately absent.
);

const _rich = CurrentWeather(
  temperatureC: 24.4,
  humidityPct: 78,
  weatherCode: 61,
  windSpeedKmh: 18.2,
  windDirectionDeg: 247,
  observedAt: '2026-09-09T14:00',
  timezone: 'Asia/Kolkata',
  apparentTemperatureC: 27.6,
  pressureHpa: 1004.2,
  dewPointC: 21.3,
  visibilityKm: 6.4,
);

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  group('DetailGrid', () {
    testWidgets('omits tiles whose values are absent', (tester) async {
      await _pump(
        tester,
        const DetailGrid(weather: _bare, foreground: AppColors.textPrimary),
      );

      expect(find.text('Feels like'), findsNothing);
      expect(find.text('Pressure'), findsNothing);
      expect(find.text('Visibility'), findsNothing);
      expect(find.text('UV index'), findsNothing);
      expect(find.text('PM2.5'), findsNothing);

      // Humidity and wind are always served, so they always render.
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('Wind'), findsOneWidget);
    });

    testWidgets('never renders a zero for an absent value', (tester) async {
      await _pump(
        tester,
        const DetailGrid(weather: _bare, foreground: AppColors.textPrimary),
      );

      // The failure mode this whole design guards against.
      expect(find.text('0'), findsNothing);
      expect(find.text('0°'), findsNothing);
      expect(find.text('--'), findsNothing);
    });

    testWidgets('renders each tile once its value arrives', (tester) async {
      await _pump(
        tester,
        const DetailGrid(
          weather: _rich,
          foreground: AppColors.textPrimary,
          uvIndexMax: 7.35,
          airQuality: AirQuality(observedAt: 'x', usAqi: 156, pm25: 64.8),
        ),
      );

      expect(find.text('Feels like'), findsOneWidget);
      expect(find.text('28°'), findsOneWidget); // 27.6 rounded
      expect(find.text('UV index'), findsOneWidget);
      expect(find.text('High'), findsOneWidget); // WHO band for 7.35
      expect(find.text('Pressure'), findsOneWidget);
      expect(find.text('Visibility'), findsOneWidget);
      expect(find.text('PM2.5'), findsOneWidget);
    });

    testWidgets('drops the dew-point subtitle when dew point is absent',
        (tester) async {
      await _pump(
        tester,
        const DetailGrid(weather: _bare, foreground: AppColors.textPrimary),
      );

      expect(find.textContaining('Dew pt'), findsNothing);
      expect(find.text('Humidity'), findsOneWidget);
    });
  });

  group('AqiPill', () {
    testWidgets('renders nothing without a reading', (tester) async {
      await _pump(
        tester,
        const AqiPill(airQuality: null, foreground: AppColors.textPrimary),
      );

      expect(find.textContaining('AQI'), findsNothing);
    });

    testWidgets('renders nothing when the reading has no AQI value',
        (tester) async {
      await _pump(
        tester,
        const AqiPill(
          airQuality: AirQuality(observedAt: 'x'),
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.textContaining('AQI'), findsNothing);
    });

    testWidgets('shows the value with its US EPA band', (tester) async {
      await _pump(
        tester,
        const AqiPill(
          airQuality: AirQuality(observedAt: 'x', usAqi: 156),
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('AQI 156 · Unhealthy'), findsOneWidget);
    });
  });

  group('SunPanel', () {
    testWidgets('renders nothing without both sun times', (tester) async {
      await _pump(
        tester,
        const SunPanel(
          foreground: AppColors.textPrimary,
          sunrise: '2026-09-09T06:12',
          // sunset absent
        ),
      );

      expect(find.text('Sun'), findsNothing);
    });

    testWidgets('formats upstream ISO strings as clock times', (tester) async {
      await _pump(
        tester,
        const SunPanel(
          foreground: AppColors.textPrimary,
          sunrise: '2026-09-09T06:12',
          sunset: '2026-09-09T18:42',
        ),
      );

      expect(find.text('06:12'), findsOneWidget);
      expect(find.text('18:42'), findsOneWidget);
      // The raw ISO string must never reach the screen.
      expect(find.textContaining('2026-09-09T'), findsNothing);
    });
  });

  group('HourlyPanel', () {
    testWidgets('labels the first column "Now" and the rest by clock time',
        (tester) async {
      await _pump(
        tester,
        const HourlyPanel(
          foreground: AppColors.textPrimary,
          hours: [
            HourlyPoint(
                time: '2026-09-09T14:00', temperatureC: 24.4, weatherCode: 3),
            HourlyPoint(
                time: '2026-09-09T15:00', temperatureC: 25.1, weatherCode: 3),
          ],
        ),
      );

      expect(find.text('Now'), findsOneWidget);
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('14:00'), findsNothing); // replaced by "Now"
    });

    testWidgets('renders nothing for an empty series', (tester) async {
      await _pump(
        tester,
        const HourlyPanel(foreground: AppColors.textPrimary, hours: []),
      );

      expect(find.text('Hourly forecast'), findsNothing);
    });
  });
}
