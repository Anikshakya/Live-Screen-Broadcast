// integration_test/app_test.dart
//
// End-to-end tests for the "Real-Time Screen Mirror" app.
//
// Run (debug mode only - the host screens use RenderObject.debugNeedsPaint):
//   flutter test integration_test/app_test.dart -d <device-id>
//
// Notes
//  * WebSocket tests open real sockets on 127.0.0.1 (ports 8080 / 8081).
//    Make sure nothing else (e.g. server/server.js) is using port 8080.
//  * Firebase tests only exercise UI + local validation; they never write to
//    Firestore. They still need Firebase to initialise (android / iOS / macOS).

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mirror/firebase_options.dart';
import 'package:mirror/main.dart';
import 'package:mirror/shared/museum_map_view.dart';
import 'package:mirror/shared/museum_poi.dart';
import 'package:mirror/websocket/websocket_protocol.dart';
import 'package:mirror/websocket/websocket_service.dart';

// 1x1 PNG, used as a fake "host frame" for the client screen.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<void> realDelay(Duration d) => Future<void>.delayed(d);

/// Polls [condition] in real time until it is true or [timeout] expires.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for: $reason');
    }
    await realDelay(const Duration(milliseconds: 50));
  }
}

/// Pumps frames in real time until [finder] matches something.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for $finder');
    }
    await realDelay(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const MirrorApp());
  await tester.pumpAndSettle();
}

/// Scrolls a main-menu card into view and taps it.
Future<void> openFromMenu(WidgetTester tester, String cardTitle) async {
  final card = find.text(cardTitle);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

/// Pops the current screen and gives sockets / servers time to shut down.
Future<void> goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await realDelay(const Duration(milliseconds: 700));
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void clearSnackBars(WidgetTester tester) {
  ScaffoldMessenger.of(
    tester.element(find.byType(Scaffold).first),
  ).clearSnackBars();
}

Size appSize(WidgetTester tester) => tester.getSize(find.byType(MaterialApp));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;

  setUpAll(() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase init failed in test setup: $e');
    }
  });

  // =========================================================================
  group('Main menu', () {
    testWidgets('shows branding and all four role cards', (tester) async {
      await launchApp(tester);

      expect(find.text('Real-Time Screen Mirror'), findsOneWidget);
      expect(find.text('Interactive Device Mirror'), findsOneWidget);
      expect(find.text('WEBSOCKET (LOCAL WI-FI)'), findsOneWidget);
      expect(find.text('FIREBASE (GLOBAL CLOUD)'), findsOneWidget);

      for (final title in const [
        'WebSocket Host',
        'WebSocket Client',
        'Firebase Host',
        'Firebase Client',
      ]) {
        expect(find.text(title), findsOneWidget, reason: '$title card');
      }
    });

    testWidgets('WebSocket cards navigate to their screens and back',
        (tester) async {
      await launchApp(tester);

      await openFromMenu(tester, 'WebSocket Client');
      expect(find.text('WEBSOCKET CLIENT'), findsOneWidget);
      await goBack(tester);
      expect(find.text('Real-Time Screen Mirror'), findsOneWidget);

      await openFromMenu(tester, 'WebSocket Host');
      expect(find.text('WEBSOCKET HOST'), findsOneWidget);
      await goBack(tester);
      expect(find.text('Real-Time Screen Mirror'), findsOneWidget);
    });
  });

  // =========================================================================
  group('WebSocket protocol', () {
    test('gesture packet survives a JSON round trip', () {
      final original = WebSocketGesturePacket(
        action: 'move',
        pointerId: 3,
        normalizedX: 0.25,
        normalizedY: 0.75,
      );
      final decoded = WebSocketGesturePacket.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.action, 'move');
      expect(decoded.pointerId, 3);
      expect(decoded.normalizedX, 0.25);
      expect(decoded.normalizedY, 0.75);
    });

    test('frame packet survives a JSON round trip', () {
      final original = WebSocketFramePacket(
        base64: 'AAAA',
        width: 100,
        height: 200,
        timestamp: 42,
      );
      final json = jsonDecode(jsonEncode(original.toJson()))
          as Map<String, dynamic>;
      final decoded = WebSocketFramePacket.fromBase64Json(json);

      expect(json['type'], 'frame');
      expect(decoded.base64, 'AAAA');
      expect(decoded.width, 100);
      expect(decoded.height, 200);
      expect(decoded.timestamp, 42);
    });

    test('missing gesture fields fall back to safe defaults', () {
      final decoded = WebSocketGesturePacket.fromJson(<String, dynamic>{});
      expect(decoded.action, 'unknown');
      expect(decoded.pointerId, 0);
      expect(decoded.normalizedX, 0);
      expect(decoded.normalizedY, 0);
    });
  });

  // =========================================================================
  group('WebSocket services (real loopback sockets)', () {
    const port = 8081;
    late WebSocketServerService server;
    late WebSocketClientService client;

    setUp(() {
      server = WebSocketServerService();
      client = WebSocketClientService();
    });

    tearDown(() async {
      await client.disconnect();
      await server.stopServer();
      await realDelay(const Duration(milliseconds: 200));
    });

    test('server starts, accepts a client, and tracks client count', () async {
      final counts = <int>[];
      server.onClientCountChanged = counts.add;

      expect(await server.startServer(port: port), isTrue);
      expect(server.isHosting, isTrue);
      expect(server.port, port);
      expect(server.clientCount, 0);

      await client.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 1, reason: '1 client');

      await client.disconnect();
      await waitUntil(() => server.clientCount == 0, reason: '0 clients');
      expect(counts, containsAllInOrder([1, 0]));
    });

    test('binary frames broadcast by the server reach the client', () async {
      await server.startServer(port: port);

      final received = Completer<Uint8List>();
      client.onRawFrameReceived = (bytes) {
        if (!received.isCompleted) received.complete(bytes);
      };
      await client.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 1, reason: '1 client');

      server.broadcast(_tinyPng);

      final bytes = await received.future.timeout(const Duration(seconds: 5));
      expect(bytes, _tinyPng);
    });

    test('JSON frame packets are parsed on the client', () async {
      await server.startServer(port: port);

      final received = Completer<WebSocketFramePacket>();
      client.onFrameReceived = (f) {
        if (!received.isCompleted) received.complete(f);
      };
      await client.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 1, reason: '1 client');

      server.broadcast(jsonEncode(
        WebSocketFramePacket(
          base64: 'QUJD',
          width: 10,
          height: 20,
          timestamp: 99,
        ).toJson(),
      ));

      final frame = await received.future.timeout(const Duration(seconds: 5));
      expect(frame.base64, 'QUJD');
      expect(frame.width, 10);
      expect(frame.height, 20);
    });

    test('gestures sent by the client reach the server', () async {
      final received = Completer<WebSocketGesturePacket>();
      server.onGestureReceived = (g) {
        if (!received.isCompleted) received.complete(g);
      };
      await server.startServer(port: port);
      await client.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 1, reason: '1 client');

      client.sendGesture(WebSocketGesturePacket(
        action: 'down',
        pointerId: 1,
        normalizedX: 0.3,
        normalizedY: 0.6,
      ));

      final g = await received.future.timeout(const Duration(seconds: 5));
      expect(g.action, 'down');
      expect(g.pointerId, 1);
      expect(g.normalizedX, closeTo(0.3, 1e-9));
      expect(g.normalizedY, closeTo(0.6, 1e-9));
    });

    test('server broadcasts to every connected client', () async {
      await server.startServer(port: port);
      final second = WebSocketClientService();
      addTearDown(second.disconnect);

      final a = Completer<Uint8List>();
      final b = Completer<Uint8List>();
      client.onRawFrameReceived = (x) => a.isCompleted ? null : a.complete(x);
      second.onRawFrameReceived = (x) => b.isCompleted ? null : b.complete(x);

      await client.connect('127.0.0.1', port: port);
      await second.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 2, reason: '2 clients');

      server.broadcast(_tinyPng);

      expect(await a.future.timeout(const Duration(seconds: 5)), _tinyPng);
      expect(await b.future.timeout(const Duration(seconds: 5)), _tinyPng);
    });

    test('stopServer disconnects clients and frees the port', () async {
      await server.startServer(port: port);
      await client.connect('127.0.0.1', port: port);
      await waitUntil(() => server.clientCount == 1, reason: '1 client');

      await server.stopServer();
      expect(server.isHosting, isFalse);
      expect(server.clientCount, 0);

      // Port can be re-bound straight away.
      final again = WebSocketServerService();
      addTearDown(again.stopServer);
      expect(await again.startServer(port: port), isTrue);
    });
  });

  // =========================================================================
  group('WebSocket Client screen', () {
    testWidgets('renders the disconnected state', (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Client');

      expect(find.text('WEBSOCKET CLIENT'), findsOneWidget);
      expect(find.text('WebSocket Host IP Address'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(
        find.text('Connect to Host IP Address to view stream.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);

      await goBack(tester);
    });

    testWidgets('Connect with an empty IP does nothing', (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Client');

      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);

      await goBack(tester);
    });

    testWidgets(
        'connects to a host, displays a streamed frame, sends taps, disconnects',
        (tester) async {
      final server = WebSocketServerService();
      final gestures = <WebSocketGesturePacket>[];
      server.onGestureReceived = gestures.add;
      addTearDown(server.stopServer);
      expect(
        await server.startServer(port: 8080),
        isTrue,
        reason: 'Port 8080 must be free for this test',
      );

      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Client');

      // Connect
      await tester.enterText(find.byType(TextField), '127.0.0.1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await pumpUntilFound(tester, find.text('Connected!'));
      expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsOneWidget);
      expect(
        find.text('Waiting for host screen frames...'),
        findsOneWidget,
      );
      await waitUntil(() => server.clientCount == 1, reason: 'host sees client');

      // Receive a frame
      server.broadcast(_tinyPng);
      await pumpUntilFound(tester, find.byType(Image));
      expect(find.text('Waiting for host screen frames...'), findsNothing);

      // Tap on the mirrored screen -> down + up gestures reach the host
      await tester.tap(find.byType(Image));
      await waitUntil(
        () => gestures.length >= 2,
        reason: 'down + up gestures at host',
      );
      expect(gestures[0].action, 'down');
      expect(gestures[0].normalizedX, inInclusiveRange(0.0, 1.0));
      expect(gestures[0].normalizedY, inInclusiveRange(0.0, 1.0));
      expect(gestures[0].normalizedX, closeTo(0.5, 0.15));
      expect(gestures[0].normalizedY, closeTo(0.5, 0.15));
      expect(gestures[1].action, 'up');
      await tester.pump(const Duration(milliseconds: 100));

      // Disconnect
      await tester.tap(find.widgetWithText(ElevatedButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await waitUntil(() => server.clientCount == 0, reason: 'host sees leave');

      await goBack(tester);
    });
  });

  // =========================================================================
  group('WebSocket Host screen', () {
    testWidgets('starts a server and shows address + client count',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');

      expect(find.text('WEBSOCKET HOST'), findsOneWidget);
      expect(find.text('LOCAL WI-FI ADDRESS (WEBSOCKET)'), findsOneWidget);

      await pumpUntilFound(tester, find.textContaining(':8080'));
      expect(find.text('Connected WebSocket Clients: 0'), findsOneWidget);
      expect(find.text('Failed to start server'), findsNothing);

      await goBack(tester);
    });

    testWidgets('mirrors its screen to a client and shows remote touches',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');
      await pumpUntilFound(tester, find.textContaining(':8080'));

      final client = WebSocketClientService();
      addTearDown(client.disconnect);
      final frame = Completer<Uint8List>();
      client.onRawFrameReceived = (b) {
        if (!frame.isCompleted) frame.complete(b);
      };

      await client.connect('127.0.0.1', port: 8080);
      await pumpUntilFound(
        tester,
        find.text('Connected WebSocket Clients: 1'),
      );

      // Host captures its own screen and broadcasts PNG frames.
      late Uint8List bytes;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!frame.isCompleted) {
        if (DateTime.now().isAfter(deadline)) {
          fail('No frame received from host within 15s');
        }
        await realDelay(const Duration(milliseconds: 100));
        await tester.pump();
      }
      bytes = await frame.future;
      expect(bytes.length, greaterThan(8));
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]); // PNG magic

      // Remote touch shows an indicator on the host, 'up' removes it.
      expect(find.byIcon(Icons.touch_app), findsNothing);
      client.sendGesture(WebSocketGesturePacket(
        action: 'down',
        pointerId: 1,
        normalizedX: 0.5,
        normalizedY: 0.5,
      ));
      await pumpUntilFound(tester, find.byIcon(Icons.touch_app));

      client.sendGesture(WebSocketGesturePacket(
        action: 'up',
        pointerId: 1,
        normalizedX: 0.5,
        normalizedY: 0.5,
      ));
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (find.byIcon(Icons.touch_app).evaluate().isNotEmpty) {
        if (DateTime.now().isAfter(end)) fail('Touch indicator never cleared');
        await realDelay(const Duration(milliseconds: 100));
        await tester.pump();
      }

      // Client leaves -> counter returns to 0
      await client.disconnect();
      await pumpUntilFound(
        tester,
        find.text('Connected WebSocket Clients: 0'),
      );

      await goBack(tester);
    });

    testWidgets('interactive controls: switch, slider, POI tile, copy IP',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');
      await pumpUntilFound(tester, find.textContaining(':8080'));

      // Switch
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tapVisible(tester, find.byType(Switch));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // Slider
      expect(find.text('Sync Level: 65%'), findsOneWidget);
      await tester.ensureVisible(find.byType(Slider));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(find.text('Sync Level: 65%'), findsNothing);
      expect(find.textContaining('Sync Level:'), findsOneWidget);

      // POI tile -> snackbar
      await tapVisible(tester, find.text('T-Rex & Fossil Gallery'));
      expect(find.text('Selected T-Rex & Fossil Gallery'), findsOneWidget);
      clearSnackBars(tester);
      await tester.pumpAndSettle();

      // Copy IP -> snackbar
      await tapVisible(tester, find.byTooltip('Copy IP'));
      expect(find.text('IP Address copied to clipboard!'), findsOneWidget);
      clearSnackBars(tester);
      await tester.pumpAndSettle();

      await goBack(tester);
    });

    testWidgets('lists every sample museum highlight', (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');

      expect(find.text('Museum Highlights'), findsOneWidget);
      for (final poi in MuseumPoi.samplePois) {
        await tester.ensureVisible(find.text(poi.name));
        expect(find.text(poi.name), findsOneWidget, reason: poi.name);
      }

      await goBack(tester);
    });

    testWidgets('drawing pad records strokes and Clear wipes them',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');

      final pad = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_DrawingPainter',
      );
      int pointCount() =>
          (tester.widget<CustomPaint>(pad).painter as dynamic).points.length
              as int;

      await tester.ensureVisible(pad);
      await tester.pumpAndSettle();
      expect(pointCount(), 0);

      // Horizontal drag so the pan recogniser wins over the scroll view.
      await tester.drag(pad, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(pointCount(), greaterThan(0));

      await tapVisible(tester, find.text('Clear'));
      expect(pointCount(), 0);

      await goBack(tester);
    });

    testWidgets('bottom navigation switches between dashboard and map',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');

      expect(find.text('Interactive UI Controls'), findsOneWidget);
      expect(find.byType(MuseumMapView), findsNothing);

      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      expect(find.byType(MuseumMapView), findsOneWidget);
      expect(find.text('Interactive UI Controls'), findsNothing);

      await tester.tap(find.text('Interactive UI'));
      await tester.pumpAndSettle();
      expect(find.text('Interactive UI Controls'), findsOneWidget);
      expect(find.byType(MuseumMapView), findsNothing);

      await goBack(tester);
    });
  });

  // =========================================================================
  group('Museum map', () {
    Future<void> openMap(WidgetTester tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'WebSocket Host');
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      expect(find.byType(MuseumMapView), findsOneWidget);
    }

    Future<void> tapChip(WidgetTester tester, String label) async {
      final chip = find.widgetWithText(ActionChip, label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    testWidgets('shows a chip and a pin for every point of interest',
        (tester) async {
      await openMap(tester);

      expect(find.widgetWithText(ActionChip, 'All Places'), findsOneWidget);
      for (final poi in MuseumPoi.samplePois) {
        expect(
          find.widgetWithText(ActionChip, poi.tag),
          findsOneWidget,
          reason: '${poi.tag} chip',
        );
        expect(
          find.descendant(
            of: find.byType(InteractiveViewer),
            matching: find.text(poi.tag),
          ),
          findsOneWidget,
          reason: '${poi.tag} pin',
        );
      }
      expect(find.text('Read More'), findsNothing); // nothing selected yet

      await goBack(tester);
    });

    testWidgets('selecting a chip zooms in and opens the info callout',
        (tester) async {
      await openMap(tester);
      final before = tester.getRect(find.byType(Image)).width;

      await tapChip(tester, 'ZOO');

      expect(find.text('LIVE ANIMALS'), findsOneWidget); // callout category
      expect(find.text('Read More'), findsOneWidget);
      expect(find.text('Prehistoric Wildlife Zoo'), findsWidgets);
      expect(tester.getRect(find.byType(Image)).width,
          greaterThan(before * 1.5));

      await goBack(tester);
    });

    testWidgets('tapping a pin on the map selects it', (tester) async {
      await openMap(tester);

      await tester.tap(find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.text('ZOO'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Read More'), findsOneWidget);
      expect(find.text('LIVE ANIMALS'), findsOneWidget);

      await goBack(tester);
    });

    testWidgets('Read More slides in the detail panel; close brings back callout',
        (tester) async {
      await openMap(tester);
      final screenWidth = appSize(tester).width;
      await tapChip(tester, 'ZOO');

      // Panel is mounted but parked off-screen to the right.
      expect(
        tester.getTopLeft(find.text('Overview')).dx,
        greaterThanOrEqualTo(screenWidth - 1),
      );

      await tester.tap(find.text('Read More'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Overview')).dx, lessThan(screenWidth));
      expect(find.text('Read More'), findsNothing);
      expect(find.text('Key Highlights'), findsOneWidget);
      expect(find.text('Operating Hours'), findsOneWidget);
      expect(find.text('9:30 AM - 5:30 PM'), findsOneWidget);
      expect(find.textContaining('living biomes'), findsOneWidget);
      for (final h in MuseumPoi.samplePois
          .firstWhere((p) => p.id == 'zoo')
          .highlights) {
        expect(find.text(h), findsOneWidget, reason: h);
      }

      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(find.text('Read More'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Overview')).dx,
        greaterThanOrEqualTo(screenWidth - 1),
      );

      await goBack(tester);
    });

    testWidgets('detail panel actions show feedback snackbars', (tester) async {
      await openMap(tester);
      await tapChip(tester, 'ZOO');
      await tester.tap(find.text('Read More'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.text('Directions'));
      expect(
        find.text('Navigating to Prehistoric Wildlife Zoo...'),
        findsOneWidget,
      );
      clearSnackBars(tester);
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byIcon(Icons.bookmark_add_rounded));
      expect(
        find.text('Saved Prehistoric Wildlife Zoo to favorites!'),
        findsOneWidget,
      );
      clearSnackBars(tester);
      await tester.pumpAndSettle();

      await goBack(tester);
    });

    testWidgets('can switch between places and reset with All Places',
        (tester) async {
      await openMap(tester);

      await tapChip(tester, 'HOSPITAL');
      expect(find.text('HEALTH & SAFETY'), findsOneWidget);

      await tapChip(tester, 'PALEONTOLOGY');
      expect(find.text('HEALTH & SAFETY'), findsNothing);
      expect(find.text('Read More'), findsOneWidget);
      expect(find.text('T-Rex & Fossil Gallery'), findsWidgets);

      await tapChip(tester, 'All Places');
      expect(find.text('Read More'), findsNothing);

      await goBack(tester);
    });

    testWidgets('zoom-in and reset buttons change the map scale',
        (tester) async {
      await openMap(tester);
      final base = tester.getRect(find.byType(Image)).width;

      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      final zoomed = tester.getRect(find.byType(Image)).width;
      expect(zoomed, greaterThan(base * 1.3));

      await tester.tap(find.byTooltip('Reset Map View'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(Image)).width, closeTo(base, 2.0));

      await goBack(tester);
    });
  });

  // =========================================================================
  group('Firebase screens (UI only, no Firestore writes)', () {
    setUp(() {
      expect(
        firebaseReady,
        isTrue,
        reason: 'Firebase failed to initialise. Run on Android / iOS / macOS '
            'with a valid firebase_options.dart.',
      );
    });

    testWidgets('Firebase Client renders defaults', (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Client');

      expect(find.text('FIREBASE CLOUD CLIENT'), findsOneWidget);
      expect(find.text('Firebase Room ID'), findsOneWidget);
      expect(find.text('room_101'), findsOneWidget);
      expect(find.text('Firebase Offline'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
      expect(
        find.text('Connect to a Firebase Room ID to view stream.'),
        findsOneWidget,
      );

      await goBack(tester);
    });

    testWidgets('Firebase Client: empty room ID does not start connecting',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Client');

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Firebase Offline'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);

      await goBack(tester);
    });

    testWidgets('Firebase Client: connecting leaves the offline state',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Client');

      // Unique room so we never attach to someone's real session.
      final room = 'it_test_${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byType(TextField), room);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
      await tester.pump();
      await realDelay(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.text('Firebase Offline'), findsNothing);
      // No host exists in this room, so we must not look "connected".
      expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsNothing);

      await goBack(tester);
    });

    testWidgets('Firebase Host renders defaults and generates room IDs',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Host');

      expect(find.text('FIREBASE CLOUD HOST'), findsOneWidget);
      expect(find.text('Firebase Cloud Ready'), findsOneWidget);
      expect(find.text('Start Host'), findsOneWidget);

      String room() =>
          tester.widget<TextField>(find.byType(TextField)).controller!.text;
      expect(room(), 'room_101');

      await tapVisible(tester, find.text('New Room'));
      expect(room(), matches(RegExp(r'^room_\d{4}$')));

      // Leave with an empty ID so dispose doesn't touch Firestore.
      await tester.enterText(find.byType(TextField), '');
      await goBack(tester);
    });

    testWidgets('Firebase Host: Start with empty room ID shows validation',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Host');

      await tester.enterText(find.byType(TextField), '');
      await tapVisible(tester, find.text('Start Host'));

      expect(
        find.text('Please enter or generate a valid Room ID'),
        findsOneWidget,
      );
      expect(find.text('Stop'), findsNothing);

      await goBack(tester);
    });

    testWidgets('Firebase Host: bottom nav shows the museum map',
        (tester) async {
      await launchApp(tester);
      await openFromMenu(tester, 'Firebase Host');

      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      expect(find.byType(MuseumMapView), findsOneWidget);

      await tester.tap(find.text('Host Dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(MuseumMapView), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await goBack(tester);
    });
  });
}