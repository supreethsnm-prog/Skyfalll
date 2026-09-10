import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/voice_recorder.dart';
import '../../core/permissions/mic_permission.dart';

final micPermissionProvider =
    Provider<MicPermission>((ref) => const RecordMicPermission());

/// One recorder for the app's lifetime — creating a fresh one per
/// recording is unnecessary overhead, and the underlying package is
/// explicitly designed to be reused across start/stop/cancel cycles.
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final recorder = RecordVoiceRecorder();
  ref.onDispose(() => recorder.dispose());
  return recorder;
});

/// Speech-to-text recording. Everything downstream of a finished
/// recording (uploading, transcribing, the reply) is `ChatController`'s
/// job via `sendVoice` — this controller's only concern is the
/// microphone: permission, start, stop, cancel.
sealed class VoiceRecordingUiState {
  const VoiceRecordingUiState();
}

class VoiceRecordingIdle extends VoiceRecordingUiState {
  const VoiceRecordingIdle();
}

class VoiceRecordingActive extends VoiceRecordingUiState {
  /// The live amplitude stream for exactly this recording session — a
  /// fixed reference captured once at `start()`, not recomputed on every
  /// read.
  final Stream<double> amplitude;
  const VoiceRecordingActive(this.amplitude);
}

final voiceRecordingControllerProvider =
    NotifierProvider<VoiceRecordingController, VoiceRecordingUiState>(
  VoiceRecordingController.new,
);

class VoiceRecordingController extends Notifier<VoiceRecordingUiState> {
  @override
  VoiceRecordingUiState build() => const VoiceRecordingIdle();

  /// Requests microphone permission and, if granted, starts recording a
  /// fresh WAV file. Returns `false` without changing state if permission
  /// is refused — the composer decides how to explain that to the user;
  /// this controller only reports the outcome.
  Future<bool> start() async {
    final permission = await ref.read(micPermissionProvider).request();
    if (permission != MicPermissionResult.granted) return false;

    final recorder = ref.read(voiceRecorderProvider);
    await recorder.start();
    state = VoiceRecordingActive(recorder.amplitude);
    return true;
  }

  /// Stops recording and returns the finished file's path — null if there
  /// was nothing to stop (already idle).
  Future<String?> stop() async {
    if (state is! VoiceRecordingActive) return null;
    final path = await ref.read(voiceRecorderProvider).stop();
    state = const VoiceRecordingIdle();
    return path;
  }

  /// Stops and discards the recording without producing a file — the
  /// composer's cancel (X) action.
  Future<void> cancel() async {
    if (state is! VoiceRecordingActive) return;
    await ref.read(voiceRecorderProvider).cancel();
    state = const VoiceRecordingIdle();
  }
}
