import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/shared/widgets/app_chip.dart';

void main() {
  testWidgets('builds with selected: false', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppChip(label: 'Rain')),
      ),
    );

    expect(find.text('Rain'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.selected, isFalse);
  });

  testWidgets('builds with selected: true and uses an on-brand Marigold tint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppChip(label: 'Selected', selected: true)),
      ),
    );

    expect(find.text('Selected'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
    expect(chip.selected, isTrue);
    expect(chip.selectedColor, AppColors.marigold.withValues(alpha: 0.24));
  });

  testWidgets('invokes onTap when tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppChip(label: 'Rain', onTap: () => tapped = true),
        ),
      ),
    );

    await tester.tap(find.byType(ChoiceChip));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
