import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_theme.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/conversation_store.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/features/shell/app_drawer.dart';

Future<void> _loadFont(String family, String assetPath) async {
  final bytes = await File(assetPath).readAsBytes();
  final loader = FontLoader(family)
    ..addFont(Future.value(bytes.buffer.asByteData()));
  await loader.load();
}

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

void _sizeView(WidgetTester tester) {
  const dpr = 2.0;
  tester.view.physicalSize = const Size(400 * dpr, 880 * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

/// A chat API that never returns, so the screen can be pumped with a
/// pre-seeded transcript without a live backend.
/// No stored history, so the drawer and chat screen never reach for the
/// shared_preferences plugin, which has no widget-test implementation.
class _EmptyConversationStore implements ConversationStore {
  @override
  Future<List<Conversation>> load() async => const [];

  @override
  Future<void> save(List<Conversation> next) async {}
}

class _InertChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) {
    return Completer<ChatResult>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Returns one canned assistant reply, so a populated transcript can be
/// rendered without a live backend. The `history` it returns is the
/// backend's own opaque shape, which the controller stores verbatim.
class _ReplyingChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    const reply =
        'Yes — heavy rain is likely across Pune district from about 6 pm '
        'this evening, easing after midnight. Expect around 12 mm of '
        'rainfall and gusts near 30 km/h.\n\nThe IMD has a Severe '
        'rainfall warning in force for the district, so avoid low-lying '
        'roads near the Mutha river tonight.';

    return const ChatResult(
      reply: reply,
      history: [
        {'role': 'user', 'content': 'Will it rain in Pune this evening?'},
        {'role': 'assistant', 'content': reply},
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Roboto', 'assets/fonts/Roboto-Variable.ttf');
    await _loadFont('RobotoMono', 'assets/fonts/RobotoMono-Variable.ttf');
    await _loadMaterialIconsFontBestEffort();
  });

  testWidgets('sidebar — empty recents', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationStoreProvider.overrideWithValue(
            _EmptyConversationStore(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          home: const Scaffold(drawer: AppDrawer(), body: SizedBox.expand()),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/sidebar_empty.png'),
    );
  });

  testWidgets('sidebar — with conversation history', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          conversationStoreProvider.overrideWithValue(
            _EmptyConversationStore(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          home: const Scaffold(
            drawer: AppDrawer(
              activeRoute: '/chat',
              recents: [
                'Rain forecast for Pune this week',
                'Cyclone risk on the Odisha coast',
                'Is it safe to sow now?',
                'Air quality in Delhi tomorrow',
              ],
            ),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppDrawer),
      matchesGoldenFile('goldens/sidebar_recents.png'),
    );
  });

  testWidgets('chat — empty state', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(_InertChatApi()),
          conversationStoreProvider.overrideWithValue(
            _EmptyConversationStore(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_empty.png'),
    );
  });

  testWidgets('chat — populated conversation', (tester) async {
    _sizeView(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(_ReplyingChatApi()),
          conversationStoreProvider.overrideWithValue(
            _EmptyConversationStore(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          debugShowCheckedModeBanner: false,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pump();

    // Drive a real send through the controller rather than seeding state
    // directly, so the golden reflects the actual code path.
    await tester.enterText(
      find.byType(TextField),
      'Will it rain in Pune this evening?',
    );
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send message'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_conversation.png'),
    );
  });
}
