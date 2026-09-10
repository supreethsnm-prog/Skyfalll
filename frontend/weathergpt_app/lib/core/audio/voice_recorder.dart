import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as record_pkg;

/// Wraps the `record` package so the rest of the app never imports it
/// directly, and so tests can substitute a fake without a plugin —
/// mirrors `DeviceLocation`'s role for `geolocator`.
///
/// `amplitude` reports raw dBFS (roughly -50 silence to 0 full-scale on
/// mobile mics — see `VoiceWaveform`, the one place that interprets this
/// number), not a pre-normalized level: normalization is a presentation
/// concern, and keeping it out of this interface is what lets a fake
/// emit whatever fixed values a test wants without reverse-engineering
/// the real normalization curve.
abstract class VoiceRecorder {
  /// Starts recording to a location this recorder owns and picks itself
  /// — never a caller-supplied path. Keeping temp-file/platform-channel
  /// concerns (`path_provider`) inside the implementation, rather than
  /// threaded in from outside, is what lets `VoiceRecordingController` be
  /// unit-tested with a plain fake and no Flutter test binding at all.
  Future<void> start();

  /// Stops recording and returns the finished file's path, or null if
  /// nothing was being recorded.
  Future<String?> stop();

  /// Stops and discards without producing a file.
  Future<void> cancel();

  Stream<double> get amplitude;

  Future<void> dispose();
}

/// 16kHz mono WAV — matches BHASHINI's own ASR default sample rate (see
/// `bhashini.py`), and the backend reads the REAL rate out of the WAV
/// header itself rather than trusting a client-supplied value, so
/// whatever is configured here is what a transcript is actually produced
/// from — it must not silently drift from what the app believes it sent.
const voiceRecordingConfig = record_pkg.RecordConfig(
  encoder: record_pkg.AudioEncoder.wav,
  sampleRate: 16000,
  numChannels: 1,
);

/// How often the amplitude stream ticks. Short enough for `VoiceWaveform`
/// to read as continuous motion, long enough not to flood the UI thread.
const voiceAmplitudeInterval = Duration(milliseconds: 80);

class RecordVoiceRecorder implements VoiceRecorder {
  RecordVoiceRecorder() : _recorder = record_pkg.AudioRecorder();

  final record_pkg.AudioRecorder _recorder;

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_message_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(voiceRecordingConfig, path: path);
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Stream<double> get amplitude =>
      _recorder.onAmplitudeChanged(voiceAmplitudeInterval).map((a) => a.current);

  @override
  Future<void> dispose() => _recorder.dispose();
}
