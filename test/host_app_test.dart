// The liveness screen inside both kinds of host app.
// An app that has not moved to material_ui yet.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:liveness/liveness.dart';
import 'package:material_ui/material_ui.dart';

Widget _launcher() => Builder(
  builder: (context) => Center(
    child: GestureDetector(
      onTap: () => FaceLiveness.show(context),
      child: const Text('open'),
    ),
  ),
);

Future<void> _openLiveness(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  expect(find.byType(FaceLiveness), findsOneWidget);
}

void main() {
  testWidgets('opens in a material_ui app', (tester) async {
    await _openLiveness(tester, MaterialApp(home: Scaffold(body: _launcher())));
  });

  testWidgets('opens in an app still on flutter/material.dart', (tester) async {
    await _openLiveness(
      tester,
      legacy.MaterialApp(home: legacy.Scaffold(body: _launcher())),
    );
  });
}
