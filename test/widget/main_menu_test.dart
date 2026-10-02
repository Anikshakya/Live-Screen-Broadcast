import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:mirror/main.dart';

void main() {

  testWidgets('menu shows all four role cards', (tester) async {

    await tester.pumpWidget(const MaterialApp(home: MainMenu()));

    for (final title in [

      'WebSocket Host', 'WebSocket Client', 'Firebase Host', 'Firebase Client',

    ]) {

      expect(find.text(title), findsOneWidget);

    }

  });

  testWidgets('WebSocket Client card opens its screen', (tester) async {

    await tester.pumpWidget(const MaterialApp(home: MainMenu()));

    await tester.ensureVisible(find.text('WebSocket Client'));

    await tester.tap(find.text('WebSocket Client'));

    await tester.pumpAndSettle();

    expect(find.text('WEBSOCKET CLIENT'), findsOneWidget);

  });

  testWidgets('menu lays out at a narrow phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: MainMenu()));

    expect(find.text('Real-Time Screen Mirror'), findsOneWidget);
    expect(find.text('WebSocket Host'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

}
