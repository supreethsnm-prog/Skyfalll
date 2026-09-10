import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/data/nwp_api.dart';
import 'package:weathergpt_app/features/home/widgets/severe_weather_panel.dart';

/// The rule these tests protect, same as detail_tiles_test.dart: a value
/// the backend did not supply is ABSENT from the panel, never rendered as
/// 0 or a real severity band's colour. On a disaster-advisory app, that
/// kind of false positive/negative gets believed.

const _basePoint = NwpPoint(
  runDate: '20260909',
  runHour: '18',
  forecastHour: 0,
  validTime: '2026-09-09T18:00:00Z',
);

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
  );
}

void main() {
  group('SevereWeatherPanel', () {
    testWidgets('renders nothing when nwp is null', (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(nwp: null, foreground: AppColors.textPrimary),
      );

      expect(find.text('Severe weather'), findsNothing);
    });

    testWidgets(
        'renders nothing for an empty forecast array — ingestion has not '
        'run yet, and an empty panel must not imply calm conditions',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(nwp: [], foreground: AppColors.textPrimary),
      );

      expect(find.text('Severe weather'), findsNothing);
      expect(find.byType(SevereWeatherPanel), findsOneWidget);
    });

    testWidgets('shows the highest CAPE in the window with its band and value',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 0,
              validTime: '2026-09-09T18:00:00Z',
              capeJPerKg: 1500,
            ),
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 24,
              validTime: '2026-09-10T18:00:00Z',
              capeJPerKg: 3200,
            ),
          ],
          foreground: AppColors.textPrimary,
        ),
      );

      // 3200 (Strong) is the higher of the two, not the nearest-hour value.
      expect(find.text('Strong'), findsOneWidget);
      expect(find.textContaining('3200'), findsOneWidget);
      expect(find.text('Moderate'), findsNothing);
    });

    testWidgets('never renders a null CAPE as a band, a 0, or a dash',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [_basePoint],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('Convective risk'), findsNothing);
      expect(find.text('Minimal'), findsNothing);
      expect(find.textContaining('0 J/kg CAPE'), findsNothing);
    });

    testWidgets('flags a peak gust at or above the gale threshold',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 0,
              validTime: '2026-09-09T18:00:00Z',
              windGustKmh: 70,
            ),
          ],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('Peak gust 70 km/h'), findsOneWidget);
      expect(find.text('Gale'), findsOneWidget);
    });

    testWidgets('does not flag a gust below the gale threshold',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 0,
              validTime: '2026-09-09T18:00:00Z',
              windGustKmh: 40,
            ),
          ],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('Peak gust 40 km/h'), findsOneWidget);
      expect(find.text('Gale'), findsNothing);
    });

    testWidgets('omits gust and CAPE rows entirely when neither is modelled',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [_basePoint],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.textContaining('Peak gust'), findsNothing);
      expect(find.text('Convective risk'), findsNothing);
    });

    testWidgets('shows pressure and cloud cover for the nearest hour',
        (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 0,
              validTime: '2026-09-09T18:00:00Z',
              mslpHpa: 1006,
              cloudCoverPct: 40,
            ),
          ],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('1006 hPa'), findsOneWidget);
      expect(find.text('40% cloud'), findsOneWidget);
    });

    testWidgets('shows the run provenance line verbatim', (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [_basePoint],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('GFS 20260909 18Z'), findsOneWidget);
    });

    testWidgets('picks the lowest forecast_hour as "nearest", regardless of '
        'array order', (tester) async {
      await _pump(
        tester,
        const SevereWeatherPanel(
          nwp: [
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 48,
              validTime: '2026-09-11T18:00:00Z',
              mslpHpa: 1000,
            ),
            NwpPoint(
              runDate: '20260909',
              runHour: '18',
              forecastHour: 0,
              validTime: '2026-09-09T18:00:00Z',
              mslpHpa: 1010,
            ),
          ],
          foreground: AppColors.textPrimary,
        ),
      );

      expect(find.text('1010 hPa'), findsOneWidget);
      expect(find.text('1000 hPa'), findsNothing);
    });
  });
}
