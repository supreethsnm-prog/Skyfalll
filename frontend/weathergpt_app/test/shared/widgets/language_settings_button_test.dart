import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/data/voice_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/chat/audio_playback_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/l10n/app_strings.dart';
import 'package:weathergpt_app/shared/widgets/language_settings_button.dart';

import '../../support/fake_apis.dart';

class _SilentChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(
    String message,
    List<dynamic>? history, {
    double? latitude,
    double? longitude,
    String? placeName,
  }) async {
    return ChatResult(
      reply: 'ok',
      history: [
        {'role': 'user', 'content': message},
        {'role': 'assistant', 'content': 'ok'},
      ],
    );
  }
}

void main() {
  testWidgets('language settings button opens sheet with all sections in Hindi',
      (tester) async {
    final prefs = FakeLanguageSettingsPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceApiProvider.overrideWithValue(
            FakeVoiceApi(languages: const [
              VoiceLanguage(code: 'en', name: 'English'),
              VoiceLanguage(code: 'hi', name: 'Hindi'),
            ]),
          ),
          voiceLanguagePrefsProvider
              .overrideWithValue(FakeVoiceLanguagePrefs('hi')),
          languageSettingsPrefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LanguageSettingsButton()),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.translate));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final s = AppStrings('hi');
    expect(find.text(s.languageSettings), findsOneWidget);
    expect(find.text(s.autoDetectLabel), findsOneWidget);
    expect(find.text(s.globalVoiceLanguage), findsOneWidget);
    expect(find.text(s.messageLanguage), findsOneWidget);
    expect(find.text(s.globalLanguage), findsOneWidget);
  });

  testWidgets('language settings button opens sheet in English',
      (tester) async {
    final prefs = FakeLanguageSettingsPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          voiceApiProvider.overrideWithValue(
            FakeVoiceApi(languages: const [
              VoiceLanguage(code: 'en', name: 'English'),
              VoiceLanguage(code: 'hi', name: 'Hindi'),
            ]),
          ),
          voiceLanguagePrefsProvider
              .overrideWithValue(FakeVoiceLanguagePrefs('en')),
          languageSettingsPrefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LanguageSettingsButton()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Language settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Language settings'), findsOneWidget);
    expect(find.text('Auto-detect (all 23 languages)'), findsOneWidget);
    expect(find.text('Global voice language'), findsOneWidget);
    expect(find.text('Message language'), findsOneWidget);
    expect(find.text('Global language'), findsOneWidget);
  });

  testWidgets('message mode reads an English reply in English even when '
      'global is Marathi', (tester) async {
    final voiceApi = FakeVoiceApi(
      synthesizeResult:
          const SynthesizedSpeech(audioBase64: 'ZmFrZQ==', audioFormat: 'wav'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(_SilentChatApi()),
          conversationStoreProvider.overrideWithValue(FakeConversationStore()),
          voiceApiProvider.overrideWithValue(voiceApi),
          voiceLanguagePrefsProvider
              .overrideWithValue(FakeVoiceLanguagePrefs('mr')),
          languageSettingsPrefsProvider.overrideWithValue(
            FakeLanguageSettingsPrefs(readAloudMode: ReadAloudMode.message),
          ),
          audioPlaybackDeviceProvider
              .overrideWithValue(FakeAudioPlaybackDevice()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Weather?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Typed turn has no stored lang; Latin script guesses English — NOT mr.
    expect(voiceApi.synthLanguages, ['en']);
  });

  testWidgets('global mode reads the same English reply in Marathi',
      (tester) async {
    final voiceApi = FakeVoiceApi(
      synthesizeResult:
          const SynthesizedSpeech(audioBase64: 'ZmFrZQ==', audioFormat: 'wav'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(_SilentChatApi()),
          conversationStoreProvider.overrideWithValue(FakeConversationStore()),
          voiceApiProvider.overrideWithValue(voiceApi),
          voiceLanguagePrefsProvider
              .overrideWithValue(FakeVoiceLanguagePrefs('mr')),
          languageSettingsPrefsProvider.overrideWithValue(
            FakeLanguageSettingsPrefs(readAloudMode: ReadAloudMode.global),
          ),
          audioPlaybackDeviceProvider
              .overrideWithValue(FakeAudioPlaybackDevice()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Weather?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(voiceApi.synthLanguages, ['mr']);
  });
}
