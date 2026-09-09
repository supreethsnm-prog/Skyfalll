import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/features/chat/widgets/code_block.dart';

void main() {
  testWidgets('renders code on a surfaceInset fill in a monospace face', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CodeBlock(code: 'flutter test'))),
    );

    expect(find.text('flutter test'), findsOneWidget);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    expect((decorated.decoration as BoxDecoration).color, AppColors.surfaceInset);

    final text = tester.widget<Text>(find.text('flutter test'));
    expect(text.style?.fontFamily, 'RobotoMono');
  });

  testWidgets('fires onCopy when the copy affordance is tapped', (tester) async {
    var copied = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeBlock(code: 'x', onCopy: () => copied = true)),
      ),
    );

    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump();

    expect(copied, isTrue);
  });

  testWidgets('the copy affordance announces as a labelled button with a '
      '40dp tap target', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CodeBlock(code: 'x', onCopy: () {})),
      ),
    );

    final buttonFinder = find.ancestor(
      of: find.byIcon(Icons.copy_outlined),
      matching: find.byType(IconButton),
    );

    final semantics = tester.getSemantics(buttonFinder);
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.label, 'Copy');

    final size = tester.getSize(buttonFinder);
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
  });
}
