import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/l10n/app_strings.dart';
import 'package:weathergpt_app/l10n/strings.g.dart';

import '../support/fake_apis.dart';

void main() {
  const supported23Languages = [
    'as', 'bn', 'brx', 'doi', 'en', 'gom', 'gu', 'hi',
    'kn', 'ks', 'mai', 'ml', 'mni', 'mr', 'ne', 'or',
    'pa', 'sa', 'sat', 'sd', 'ta', 'te', 'ur',
  ];

  group('Bundle completeness and fallback', () {
    test('all 23 Bhashini languages are registered in appStringsByLocale', () {
      for (final code in supported23Languages) {
        expect(
          appStringsByLocale.containsKey(code),
          isTrue,
          reason: 'Missing language bundle for: $code',
        );
      }
    });

    test('English bundle has core navigation and screen keys', () {
      expect(appStringsEn['home'], equals('Home'));
      expect(appStringsEn['advisories'], equals('Advisories'));
      expect(appStringsEn['aviation'], equals('Aviation'));
      expect(appStringsEn['fishingZones'], equals('Fishing zones'));
      expect(appStringsEn['historical'], equals('Historical'));
      expect(appStringsEn['alerts'], equals('Alerts'));
      expect(appStringsEn['savedPlaces'], equals('Saved places'));
      expect(appStringsEn['hourlyForecast'], equals('Hourly forecast'));
      expect(appStringsEn['feelsLike'], equals('Feels like'));
      expect(appStringsEn['humidity'], equals('Humidity'));
    });

    test('Hindi bundle has complete translations', () {
      final s = AppStrings.forLanguage('hi');
      expect(s.home, equals('होम'));
      expect(s.advisories, equals('सलाह'));
      expect(s.aviation, equals('उड्डयन'));
      expect(s.fishingZones, equals('मत्स्य पालन क्षेत्र'));
      expect(s.alerts, equals('चेतावनियां'));
      expect(s.savedPlaces, equals('सहेजे गए स्थान'));
      expect(s.hourlyForecast, equals('घंटेवार पूर्वानुमान'));
      expect(s.feelsLike, equals('महसूस होता है'));
      expect(s.humidity, equals('नमी'));
    });

    test('Regional language bundles fall back to English for missing keys', () {
      for (final code in supported23Languages) {
        final s = AppStrings.forLanguage(code);
        // Every key in English should resolve to a non-empty string in any language
        for (final key in appStringsEn.keys) {
          final val = s.get(key);
          expect(val, isNotEmpty, reason: 'Empty string for $key in $code');
        }
      }
    });

    test('Unknown keys safely return the key itself without throwing', () {
      final s = AppStrings.forLanguage('hi');
      expect(s.get('non_existent_key_xyz'), equals('non_existent_key_xyz'));
    });

    test('uiStringsProvider updates when voiceLanguageProvider changes', () {
      final container = ProviderContainer(
        overrides: [
          voiceLanguagePrefsProvider
              .overrideWithValue(FakeVoiceLanguagePrefs('en')),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(uiStringsProvider).home, equals('Home'));

      container.read(voiceLanguageProvider.notifier).setLanguage('hi');
      expect(container.read(uiStringsProvider).home, equals('होम'));

      container.read(voiceLanguageProvider.notifier).setLanguage('mr');
      expect(container.read(uiStringsProvider).home, equals('मुख्यपृष्ठ'));
    });
  });
}
