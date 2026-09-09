import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/core/theme/app_radius.dart';
import 'package:weathergpt_app/shared/widgets/round_icon_button.dart';

void main() {
  testWidgets('is a 40dp circle filled with surfaceRaised', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundIconButton(icon: Icons.menu, onPressed: () {}),
        ),
      ),
    );

    final size = tester.getSize(find.byType(RoundIconButton));
    expect(size.width, AppRadius.iconButton);
    expect(size.height, AppRadius.iconButton);

    final decorated = tester.widgetList<Container>(find.byType(Container))
        .firstWhere((c) => c.decoration is BoxDecoration);
    final decoration = decorated.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppColors.surfaceRaised);
  });

  testWidgets('invokes onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundIconButton(icon: Icons.menu, onPressed: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(RoundIconButton));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('renders disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RoundIconButton(icon: Icons.mic_none, onPressed: null)),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(RoundIconButton));
    await tester.pump();
    // No callback to assert; the test proves tapping a disabled button is inert.
  });

  testWidgets('announces as an enabled button with the tooltip as its label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoundIconButton(
            icon: Icons.menu,
            onPressed: () {},
            tooltip: 'Menu',
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(RoundIconButton));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, Tristate.isTrue);
    expect(semantics.label, 'Menu');
  });

  testWidgets('announces as a disabled button when onPressed is null',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoundIconButton(icon: Icons.mic_none, onPressed: null),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.byType(RoundIconButton));
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
  });
}
