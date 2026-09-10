import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/core/voice_language_prefs.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/data/voice_api.dart';
import 'package:weathergpt_app/features/chat/audio_playback_controller.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';

import '../../support/fake_apis.dart';

/// "Read aloud" wiring: tapping the icon under an assistant reply should
/// synthesize that exact text via `/voice/synthesize` and play it back —
/// this used to be a no-op stub (`onReadAloud: () {}`).

class _RepliedChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    return ChatResult(
      reply: 'Sunny today',
      history: [
        {'role': 'user', 'content': message},
        {'role': 'assistant', 'content': 'Sunny today'},
      ],
    );
  }
}

Future<void> _pumpPopulatedChat(
  WidgetTester tester, {
  required FakeVoiceApi voiceApi,
  required FakeAudioPlaybackDevice playbackDevice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(_RepliedChatApi()),
        conversationStoreProvider.overrideWithValue(FakeConversationStore()),
        voiceApiProvider.overrideWithValue(voiceApi),
        voiceLanguagePrefsProvider.overrideWithValue(FakeVoiceLanguagePrefs('hi')),
        audioPlaybackDeviceProvider.overrideWithValue(playbackDevice),
      ],
      child: const MaterialApp(home: ChatScreen()),
    ),
  );
  await tester.pump();

  // Drive one real turn through so an assistant reply exists on screen.
  await tester.enterText(find.byType(TextField), 'Weather?');
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
      'tapping read aloud synthesizes the exact reply text in the '
      "user's chosen language and plays it", (tester) async {
    final voiceApi = FakeVoiceApi(
      synthesizeResult: const SynthesizedSpeech(audioBase64: 'ZmFrZQ==', audioFormat: 'wav'),
    );
    final playbackDevice = FakeAudioPlaybackDevice();

    await _pumpPopulatedChat(tester, voiceApi: voiceApi, playbackDevice: playbackDevice);
    expect(find.text('Sunny today'), findsOneWidget);

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(voiceApi.textsRequestedForSynthesis, ['Sunny today']);
    expect(playbackDevice.playedBytes, hasLength(1));
  });

  testWidgets('tapping read aloud again while it is active stops playback '
      'instead of re-synthesizing', (tester) async {
    final voiceApi = FakeVoiceApi(
      synthesizeResult: const SynthesizedSpeech(audioBase64: 'ZmFrZQ==', audioFormat: 'wav'),
    );
    // Playback that does not auto-complete, so it is still "active" when
    // the second tap lands.
    final playbackDevice = FakeAudioPlaybackDevice(autoComplete: false);

    await _pumpPopulatedChat(tester, voiceApi: voiceApi, playbackDevice: playbackDevice);

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(voiceApi.textsRequestedForSynthesis, hasLength(1));

    await tester.tap(find.byTooltip('Stop reading aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Stopped, not synthesized a second time.
    expect(voiceApi.textsRequestedForSynthesis, hasLength(1));
    expect(playbackDevice.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('a synthesis failure surfaces a snackbar rather than crashing',
      (tester) async {
    final voiceApi = FakeVoiceApi(synthesizeError: const NetworkConnectionError());
    final playbackDevice = FakeAudioPlaybackDevice();

    await _pumpPopulatedChat(tester, voiceApi: voiceApi, playbackDevice: playbackDevice);

    await tester.tap(find.byTooltip('Read aloud'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(playbackDevice.playedBytes, isEmpty);
  });
}
