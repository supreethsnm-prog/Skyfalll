import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/shared/widgets/app_primary_button.dart';

void main() {
  testWidgets('invokes onPressed when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(label: 'Go', onPressed: () => tapped = true),
      ),
    );

    await tester.tap(find.text('Go'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('renders solid Marigold fill with Monsoon Ink text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(label: 'Go', onPressed: () {}),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final resolvedBackground = button.style!.backgroundColor!.resolve({});
    final resolvedForeground = button.style!.foregroundColor!.resolve({});

    expect(resolvedBackground, AppColors.marigold);
    expect(resolvedForeground, AppColors.monsoonInk);
  });

  testWidgets('renders an icon before the label when icon is provided, and still fires onPressed',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(
          label: 'Send',
          icon: Icons.send,
          onPressed: () => tapped = true,
        ),
      ),
    );

    expect(find.byIcon(Icons.send), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('omits the icon when icon is not provided (backward compatible)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppPrimaryButton(label: 'Go', onPressed: () {}),
      ),
    );

    expect(find.byType(Icon), findsNothing);
  });
}
