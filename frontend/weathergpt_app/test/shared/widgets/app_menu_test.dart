import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/theme/app_colors.dart';
import 'package:weathergpt_app/shared/widgets/app_menu.dart';

void main() {
  Widget harness(List<AppMenuItem> items, {String? header}) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showAppMenu(context: context, items: items, header: header),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows each item and fires its callback', (tester) async {
    var shared = false;
    await tester.pumpWidget(harness([
      AppMenuItem(icon: Icons.share_outlined, label: 'Share', onTap: () => shared = true),
      AppMenuItem(icon: Icons.push_pin_outlined, label: 'Pin', onTap: () {}),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);

    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    expect(shared, isTrue);
  });

  testWidgets('renders a destructive item in the destructive colour', (tester) async {
    await tester.pumpWidget(harness([
      AppMenuItem(
        icon: Icons.delete_outline,
        label: 'Delete',
        onTap: () {},
        destructive: true,
      ),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Delete'));
    expect(label.style?.color, AppColors.destructive);
  });

  testWidgets('renders an optional header above the items', (tester) async {
    await tester.pumpWidget(harness(
      [AppMenuItem(icon: Icons.share_outlined, label: 'Share', onTap: () {})],
      header: 'Model Selection Strategy',
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Model Selection Strategy'), findsOneWidget);
  });

  testWidgets('iconWell items wrap their icon in a filled circle', (tester) async {
    await tester.pumpWidget(harness([
      AppMenuItem(
        icon: Icons.photo_camera_outlined,
        label: 'Camera',
        onTap: () {},
        iconWell: true,
      ),
    ]));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final well = tester.widgetList<Container>(find.byType(Container)).firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == AppColors.surfaceIconWell);
    expect((well.decoration as BoxDecoration).shape, BoxShape.circle);
  });
}
