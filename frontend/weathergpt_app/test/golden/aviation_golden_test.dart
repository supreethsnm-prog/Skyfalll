import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/metar_api.dart';
import 'package:weathergpt_app/features/aviation/aviation_controller.dart';
import 'package:weathergpt_app/features/aviation/aviation_screen.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/home/home_controller.dart';
import 'package:weathergpt_app/features/saved/saved_places_controller.dart';

import '../support/fake_apis.dart';

Future<void> _loadFont(String family, String assetPath) async {
  final bytes = await File(assetPath).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

Future<void> _loadMaterialIconsFontBestEffort() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final file = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// A real Delhi observation, verbatim from the live endpoint — including
/// the raw METAR string, which is the point of showing it at all.
class _FixedMetarApi implements MetarApi {
  @override
  Future<MetarReading?> fetch(String icao) async => const MetarReading(
        icaoId: 'VIDP',
        rawMetar:
            'METAR VIDP 100230Z 26009KT 4000 HZ NSC 29/22 Q1009 NOSIG',
        observedAt: '2026-09-10T02:30:00.000Z',
        stationName: 'New Delhi/Gandhi Intl, DL, IN',
        temperatureC: 29.0,
        dewpointC: 22.0,
        windDirDeg: 260.0,
        windSpeedKt: 9.0,
        visibilitySm: 2.49,
        flightCategory: 'IFR',
      );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester tester) async {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 900 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        weatherApiProvider.overrideWithValue(FakeWeatherApi()),
        alertsApiProvider.overrideWithValue(FakeAlertsApi()),
        airQualityApiProvider.overrideWithValue(FakeAirQualityApi()),
        deviceLocationProvider.overrideWithValue(const FakeDeviceLocation()),
        geocodingApiProvider.overrideWithValue(const FakeGeocodingApi()),
        alertsSocketProvider.overrideWithValue(FakeAlertsSocket()),
        savedPlacesStoreProvider.overrideWithValue(FakeSavedPlacesStore()),
        conversationStoreProvider.overrideWithValue(FakeConversationStore()),
        metarApiProvider.overrideWithValue(_FixedMetarApi()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        debugShowCheckedModeBanner: false,
        // Clock pinned so the observation age does not drift the golden.
        home: AviationScreen(now: DateTime.utc(2026, 9, 10, 3, 10)),
      ),
    ),
  );

  // Home resolves a location first, then the nearest station is fetched.
  // Fixed pumps: the loading spinner is indeterminate.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('aviation — populated', (tester) async {
    await _pump(tester);

    await expectLater(
      find.byType(AviationScreen),
      matchesGoldenFile('goldens/aviation.png'),
    );
  });
}
