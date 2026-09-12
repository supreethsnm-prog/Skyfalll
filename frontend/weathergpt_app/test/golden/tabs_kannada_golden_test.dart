import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/advisory/advisory_screen.dart';
import 'package:weathergpt_app/features/aviation/aviation_screen.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/features/historical/historical_screen.dart';
import 'package:weathergpt_app/features/home/home_screen.dart';
import 'package:weathergpt_app/features/marine/marine_screen.dart';
import 'package:weathergpt_app/features/saved/saved_places_screen.dart';
import 'package:weathergpt_app/features/shell/app_drawer.dart';

import '../support/fake_apis.dart';

Future<void> _loadFont(String family, List<String> assetPaths) async {
  final loader = FontLoader(family);
  for (final path in assetPaths) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = await file.readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
  }
  await loader.load();
}

Future<void> _loadMaterialIconsFontBestEffort() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final file = File('/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

void _sizeView(WidgetTester tester, {double height = 880}) {
  const dpr = 2.0;
  tester.view.physicalSize = Size(400 * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

class _TransparentTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(TileProvider.transparentImage);
}

class _InertChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(
    String message,
    List<dynamic>? history, {
    double? latitude,
    double? longitude,
    String? placeName,
  }) {
    return Completer<ChatResult>().future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', ['assets/fonts/Roboto-Variable.ttf']);
    await _loadFont('NotoSansKannada', ['assets/fonts/NotoSansKannada-Regular.ttf']);
    await _loadFont('NotoSansDevanagari', ['assets/fonts/NotoSansDevanagari-Regular.ttf']);
    await _loadFont('RobotoMono', ['assets/fonts/RobotoMono-Variable.ttf']);
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('kannada — sidebar drawer', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const Scaffold(
            drawer: AppDrawer(
              activeRoute: '/home',
              recents: [
                'ಬೆಂಗಳೂರಿನ ಹವಾಮಾನ ವರದಿ',
                'ಮೈಸೂರಿನಲ್ಲಿ ನಾಳೆ ಮಳೆ ಬರುತ್ತಾ?',
                'ಕರಾವಳಿ ಮೀನುಗಾರಿಕೆ ಎಚ್ಚರಿಕೆ',
              ],
            ),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/sidebar_kannada.png'),
    );
  });

  testWidgets('kannada — home screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: HomeScreen(now: DateTime(2026, 9, 12, 14)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_kannada.png'),
    );
  });

  testWidgets('kannada — advisories screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const AdvisoryScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(AdvisoryScreen),
      matchesGoldenFile('goldens/advisories_kannada.png'),
    );
  });

  testWidgets('kannada — aviation screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: AviationScreen(now: DateTime.utc(2026, 9, 10, 3, 10)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(AviationScreen),
      matchesGoldenFile('goldens/aviation_kannada.png'),
    );
  });

  testWidgets('kannada — historical screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const HistoricalScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(HistoricalScreen),
      matchesGoldenFile('goldens/historical_kannada.png'),
    );
  });

  testWidgets('kannada — saved places screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const SavedPlacesScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(SavedPlacesScreen),
      matchesGoldenFile('goldens/saved_places_kannada.png'),
    );
  });

  testWidgets('kannada — marine screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          marineTileProviderProvider.overrideWithValue(_TransparentTileProvider()),
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const MarineScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await expectLater(
      find.byType(MarineScreen),
      matchesGoldenFile('goldens/marine_kannada.png'),
    );
  });

  testWidgets('kannada — chat empty screen', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...fakeApiOverrides,
          chatApiProvider.overrideWithValue(_InertChatApi()),
          voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('kn')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark.copyWith(
            textTheme: AppTheme.dark.textTheme.apply(
              fontFamily: 'NotoSansKannada',
              fontFamilyFallback: ['NotoSansKannada', 'Roboto'],
            ),
          ),
          debugShowCheckedModeBanner: false,
          home: const ChatScreen(),
        ),
      ),
    );

    await tester.pump();

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_kannada.png'),
    );
  });
}
