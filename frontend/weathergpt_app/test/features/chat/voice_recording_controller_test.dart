import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/audio/voice_recorder.dart';
import 'package:weathergpt_app/core/permissions/mic_permission.dart';
import 'package:weathergpt_app/features/chat/voice_recording_controller.dart';

class _FakeMicPermission implements MicPermission {
  _FakeMicPermission(this.result);
  final MicPermissionResult result;

  @override
  Future<MicPermissionResult> request() async => result;
}

class _FakeVoiceRecorder implements VoiceRecorder {
  final List<String> startedPaths = [];
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;
  String? stopReturnPath;

  @override
  Future<void> start() async {
    startedPaths.add('fake_path_${startedPaths.length}.wav');
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    return stopReturnPath;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Stream<double> get amplitude => const Stream<double>.empty();

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

ProviderContainer _containerWith({
  required MicPermissionResult permission,
  required _FakeVoiceRecorder recorder,
}) {
  return ProviderContainer(
    overrides: [
      micPermissionProvider.overrideWithValue(_FakeMicPermission(permission)),
      voiceRecorderProvider.overrideWithValue(recorder),
    ],
  );
}

void main() {
  test('starts idle', () {
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: _FakeVoiceRecorder(),
    );
    addTearDown(container.dispose);

    expect(container.read(voiceRecordingControllerProvider), isA<VoiceRecordingIdle>());
  });

  test('start() returns false and stays idle when permission is denied', () async {
    final recorder = _FakeVoiceRecorder();
    final container = _containerWith(
      permission: MicPermissionResult.denied,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    final started =
        await container.read(voiceRecordingControllerProvider.notifier).start();

    expect(started, isFalse);
    expect(container.read(voiceRecordingControllerProvider), isA<VoiceRecordingIdle>());
    expect(recorder.startedPaths, isEmpty);
  });

  test('start() begins recording and transitions to active when granted', () async {
    final recorder = _FakeVoiceRecorder();
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    final started =
        await container.read(voiceRecordingControllerProvider.notifier).start();

    expect(started, isTrue);
    expect(recorder.startedPaths, hasLength(1));
    expect(recorder.startedPaths.single, endsWith('.wav'));
    final state = container.read(voiceRecordingControllerProvider);
    expect(state, isA<VoiceRecordingActive>());
  });

  test('stop() while active returns the file path and returns to idle', () async {
    final recorder = _FakeVoiceRecorder()..stopReturnPath = '/tmp/voice_message_1.wav';
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    await container.read(voiceRecordingControllerProvider.notifier).start();
    final path = await container.read(voiceRecordingControllerProvider.notifier).stop();

    expect(path, '/tmp/voice_message_1.wav');
    expect(recorder.stopCalls, 1);
    expect(container.read(voiceRecordingControllerProvider), isA<VoiceRecordingIdle>());
  });

  test('stop() while already idle is a no-op and returns null', () async {
    final recorder = _FakeVoiceRecorder();
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    final path = await container.read(voiceRecordingControllerProvider.notifier).stop();

    expect(path, isNull);
    expect(recorder.stopCalls, 0);
  });

  test('cancel() while active discards and returns to idle', () async {
    final recorder = _FakeVoiceRecorder();
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    await container.read(voiceRecordingControllerProvider.notifier).start();
    await container.read(voiceRecordingControllerProvider.notifier).cancel();

    expect(recorder.cancelCalls, 1);
    expect(container.read(voiceRecordingControllerProvider), isA<VoiceRecordingIdle>());
  });

  test('cancel() while already idle is a no-op', () async {
    final recorder = _FakeVoiceRecorder();
    final container = _containerWith(
      permission: MicPermissionResult.granted,
      recorder: recorder,
    );
    addTearDown(container.dispose);

    await container.read(voiceRecordingControllerProvider.notifier).cancel();

    expect(recorder.cancelCalls, 0);
  });
}
