import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';

/// Registers a real bundled font under `family` so golden renders use the
/// actual Sora/Inter/IBMPlexMono glyphs rather than the test environment's
/// placeholder font. `flutter test` runs with the package root as the
/// working directory, so `assetPath` is relative to
/// `frontend/weathergpt_app/`, matching the `assets:` paths in pubspec.yaml.
/// These three are required app assets — a missing file here is a real
/// setup problem, so this throws (via `readAsBytes`) rather than swallowing
/// it.
Future<void> _loadFont(String family, String assetPath) async {
  final file = File(assetPath);
  final Uint8List bytes = await file.readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

/// Best-effort registration of the "MaterialIcons" font so `Icon(...)`
/// widgets (the app-bar icon, error/empty-state icons) render as real
/// glyphs instead of tofu boxes in the golden. Unlike the three app fonts
/// above, this file lives inside the Flutter SDK install, not this repo,
/// so its location is derived from the `FLUTTER_ROOT` environment variable
/// (set by `frontend/dev-env.ps1`, and by `flutter test` itself) rather
/// than hardcoded — and if it can't be found, the screen still renders
/// correctly, just with icon glyphs missing, so this is allowed to fail
/// silently rather than break the whole suite over a cosmetic detail
/// outside the app's own asset set.
Future<void> _loadMaterialIconsFontBestEffort() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;

  final file = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) return;

  final bytes = await file.readAsBytes();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

class _FakeChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    throw UnsupportedError('not used — this golden seeds state directly');
  }
}

// `chatControllerProvider` is a `NotifierProvider<ChatController, ChatUiState>`,
// so `overrideWith` requires a factory that returns a `ChatController`
// specifically (not just any `Notifier<ChatUiState>`) — extend it rather
// than `Notifier<ChatUiState>` directly.
class _SeededChatController extends ChatController {
  final ChatUiState seed;
  _SeededChatController(this.seed);

  @override
  ChatUiState build() => seed;
}

Widget _buildApp(ThemeData theme) {
  const seeded = ChatIdle([
    ChatTurn(role: 'user', content: 'Will it rain in Pune tomorrow?'),
    ChatTurn(
      role: 'assistant',
      content:
          'Yes — Pune is expecting moderate rainfall tomorrow afternoon, with a high of 27°C.',
    ),
  ]);

  return ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(_FakeChatApi()),
      chatControllerProvider.overrideWith(() => _SeededChatController(seeded)),
    ],
    child: MaterialApp(theme: theme, home: const ChatScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Sora', 'assets/fonts/Sora-Variable.ttf');
    await _loadFont('Inter', 'assets/fonts/Inter-Variable.ttf');
    await _loadFont('IBMPlexMono', 'assets/fonts/IBMPlexMono-Regular.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('chat screen — light theme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2430);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp(AppTheme.light));
    // ChatTurnTile fades in over 250ms (see chat_turn_tile.dart) — pump
    // past that or the golden captures a partially-transparent frame.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_light.png'),
    );
  });

  testWidgets('chat screen — dark theme', (tester) async {
    tester.view.physicalSize = const Size(1080, 2430);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_buildApp(AppTheme.dark));
    // Same fade-in consideration as the light-theme test above.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_dark.png'),
    );
  });
}
