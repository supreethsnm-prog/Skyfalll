import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/assistant_message.dart';

void main() {
  testWidgets('renders prose with no bubble container behind it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'It is sunny.'))),
    );

    expect(find.text('It is sunny.'), findsOneWidget);

    final decoratedContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration != null);
    expect(decoratedContainers, isEmpty,
        reason: 'assistant turns are flat prose, never boxed');
  });

  testWidgets('shows the action row and fires each callback', (tester) async {
    var copied = false, readAloud = false, shared = false, more = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMessage(
            text: 'reply',
            onCopy: () => copied = true,
            onReadAloud: () => readAloud = true,
            onShare: () => shared = true,
            onMore: () => more = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();

    expect([copied, readAloud, shared, more], everyElement(isTrue));
  });

  testWidgets('hides the action row when no callbacks are supplied', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssistantMessage(text: 'reply'))),
    );

    expect(find.byIcon(Icons.copy_outlined), findsNothing);
  });

  testWidgets('each action icon announces a button with a label and a 40dp '
      'tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMessage(
            text: 'reply',
            onCopy: () {},
            onReadAloud: () {},
            onShare: () {},
            onMore: () {},
          ),
        ),
      ),
    );

    final expected = <MapEntry<IconData, String>>[
      const MapEntry(Icons.copy_outlined, 'Copy'),
      const MapEntry(Icons.volume_up_outlined, 'Read aloud'),
      const MapEntry(Icons.share_outlined, 'Share'),
      const MapEntry(Icons.more_vert, 'More options'),
    ];

    for (final entry in expected) {
      final iconFinder = find.byIcon(entry.key);
      final buttonFinder = find.ancestor(
        of: iconFinder,
        matching: find.byType(IconButton),
      );

      final semantics = tester.getSemantics(buttonFinder);
      expect(semantics.flagsCollection.isButton, isTrue,
          reason: '${entry.value} icon has no button semantics');
      expect(semantics.label, entry.value);

      final size = tester.getSize(buttonFinder);
      expect(size.width, greaterThanOrEqualTo(40),
          reason: '${entry.value} tap target width is ${size.width}');
      expect(size.height, greaterThanOrEqualTo(40),
          reason: '${entry.value} tap target height is ${size.height}');
    }
  });
}
