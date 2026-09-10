import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/voice_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/widgets/language_picker_sheet.dart';

import '../../../support/fake_apis.dart';

const _languages = [
  VoiceLanguage(code: 'hi', name: 'Hindi'),
  VoiceLanguage(code: 'ta', name: 'Tamil'),
  VoiceLanguage(code: 'bn', name: 'Bengali'),
];

Future<void> _openSheet(
  WidgetTester tester, {
  required FakeVoiceApi voiceApi,
  FakeVoiceLanguagePrefs? prefs,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        voiceApiProvider.overrideWithValue(voiceApi),
        voiceLanguagePrefsProvider.overrideWithValue(prefs ?? FakeVoiceLanguagePrefs()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLanguagePicker(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  // No pumpAndSettle: the sheet's own load starts a CircularProgressIndicator
  // while fetching; fixed pumps against the test's virtual clock instead.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('shows every language returned by the API', (tester) async {
    await _openSheet(tester, voiceApi: FakeVoiceApi(languages: _languages));

    expect(find.text('Hindi'), findsOneWidget);
    expect(find.text('Tamil'), findsOneWidget);
    expect(find.text('Bengali'), findsOneWidget);
  });

  testWidgets('marks the currently selected language with a check',
      (tester) async {
    await _openSheet(
      tester,
      voiceApi: FakeVoiceApi(languages: _languages),
      prefs: FakeVoiceLanguagePrefs('ta'),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final tamilRow = find.ancestor(
      of: find.text('Tamil'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: tamilRow, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    final hindiRow = find.ancestor(
      of: find.text('Hindi'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: hindiRow, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
  });

  testWidgets('tapping a language persists it and closes the sheet',
      (tester) async {
    final prefs = FakeVoiceLanguagePrefs('hi');
    await _openSheet(
      tester,
      voiceApi: FakeVoiceApi(languages: _languages),
      prefs: prefs,
    );

    await tester.tap(find.text('Tamil'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Voice language'), findsNothing); // sheet closed
    expect(prefs.languageCode, 'ta');
  });

  testWidgets('a fetch failure shows an error with a retry, not a crash',
      (tester) async {
    await _openSheet(
      tester,
      voiceApi: FakeVoiceApi(languagesError: const NetworkConnectionError()),
    );

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Hindi'), findsNothing);
  });
}
