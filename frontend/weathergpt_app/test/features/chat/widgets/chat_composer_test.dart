import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/permissions/mic_permission.dart';
import 'package:weathergpt_app/features/chat/voice_recording_controller.dart';
import 'package:weathergpt_app/features/chat/widgets/chat_composer.dart';
import 'package:weathergpt_app/features/chat/widgets/voice_waveform.dart';

import '../../../support/fake_apis.dart';

/// `ChatComposer` opens a modal bottom sheet (the language picker) on
/// long-press, and shows a `SnackBar` on permission denial — both need a
/// real `Scaffold`/`Navigator`, which a bare `ChatComposer` has neither
/// of, so every test wraps it in a minimal `MaterialApp` + `Scaffold`.
Future<void> _pumpComposer(
  WidgetTester tester, {
  required FakeMicPermission micPermission,
  required FakeVoiceRecorder recorder,
  ValueChanged<String>? onSend,
  ValueChanged<String>? onSendVoice,
  bool enabled = true,
  bool sending = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        micPermissionProvider.overrideWithValue(micPermission),
        voiceRecorderProvider.overrideWithValue(recorder),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            enabled: enabled,
            sending: sending,
            onSend: onSend ?? (_) {},
            onSendVoice: onSendVoice ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('idle composer shows a mic icon, not a send button',
      (tester) async {
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(),
      recorder: FakeVoiceRecorder(),
    );

    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });

  testWidgets('typing text swaps the mic for a send button', (tester) async {
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(),
      recorder: FakeVoiceRecorder(),
    );

    await tester.enterText(find.byType(TextField), 'Weather in Pune?');
    await tester.pump();

    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets(
      'tapping the mic with permission granted starts recording and '
      'switches to the waveform row, hiding the text field', (tester) async {
    final recorder = FakeVoiceRecorder();
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(MicPermissionResult.granted),
      recorder: recorder,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(recorder.startCalls, hasLength(1));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(VoiceWaveform), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget); // cancel
    expect(find.byIcon(Icons.stop), findsOneWidget); // stop-and-send
  });

  testWidgets(
      'tapping the mic with permission denied shows an explanation and '
      'never starts recording', (tester) async {
    final recorder = FakeVoiceRecorder();
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(MicPermissionResult.denied),
      recorder: recorder,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(recorder.startCalls, isEmpty);
    expect(find.byType(TextField), findsOneWidget); // still the idle input
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.text('Microphone access is needed for voice input.'),
      findsOneWidget,
    );
  });

  testWidgets('cancel (X) during recording discards without sending',
      (tester) async {
    final recorder = FakeVoiceRecorder();
    var sendVoiceCalls = 0;
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(MicPermissionResult.granted),
      recorder: recorder,
      onSendVoice: (_) => sendVoiceCalls++,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(recorder.cancelCalls, 1);
    expect(recorder.stopCalls, 0);
    expect(sendVoiceCalls, 0);
    expect(find.byType(TextField), findsOneWidget); // back to idle input
  });

  testWidgets(
      'stop-and-send during recording stops the recorder and hands the '
      'file path to onSendVoice', (tester) async {
    final recorder = FakeVoiceRecorder(fixedStopPath: '/tmp/message_42.wav');
    String? sentPath;
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(MicPermissionResult.granted),
      recorder: recorder,
      onSendVoice: (path) => sentPath = path,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    expect(recorder.stopCalls, 1);
    expect(sentPath, '/tmp/message_42.wav');
    expect(find.byType(TextField), findsOneWidget); // back to idle input
  });

  testWidgets('while sending, a spinner replaces mic/send at the bar end',
      (tester) async {
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(),
      recorder: FakeVoiceRecorder(),
      sending: true,
    );

    expect(find.bySemanticsLabel('Sending'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });

  testWidgets('a disabled composer ignores taps on the attach and mic buttons',
      (tester) async {
    final recorder = FakeVoiceRecorder();
    await _pumpComposer(
      tester,
      micPermission: FakeMicPermission(MicPermissionResult.granted),
      recorder: recorder,
      enabled: false,
    );

    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump();

    expect(recorder.startCalls, isEmpty);
  });
}
