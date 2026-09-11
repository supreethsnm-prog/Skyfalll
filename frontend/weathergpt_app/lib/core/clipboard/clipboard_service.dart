import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Copies text to the OS clipboard. Thin wrapper around [Clipboard] so
/// widget tests can fake it — real clipboard needs a platform channel,
/// mirroring why `VoiceRecorder`/`AudioPlaybackDevice` are wrapped.
abstract class ClipboardService {
  Future<void> copy(String text);
}

class SystemClipboardService implements ClipboardService {
  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final clipboardServiceProvider =
    Provider<ClipboardService>((ref) => SystemClipboardService());
