import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/websocket/websocket_client_screen.dart';

void main() {
  testWidgets('client starts disconnected and ignores an empty host address', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: WebSocketClientScreen()));

    expect(find.text('WEBSOCKET CLIENT'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(
      find.text('Connect to Host IP Address to view stream.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
