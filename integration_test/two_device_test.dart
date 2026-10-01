// integration_test/two_device_test.dart
//
// Two-device end-to-end test: one device plays HOST, the other plays CLIENT.
// The SAME file runs on both devices; the role is chosen with --dart-define.
//
//   --dart-define=ROLE=host|client      (required)
//   --dart-define=MODE=websocket|firebase   (default: websocket)
//   --dart-define=HOST_IP=192.168.x.x   (client + websocket only)
//   --dart-define=ROOM=some_room_id     (firebase only; must match on both)
//
// Easiest way to run it: ./run_two_devices.sh <host-id> <client-id> [mode]
//
// What is verified across the two devices
//   1. The client can reach the host and receives a valid PNG frame.
//   2. The host's screen changes are mirrored (new, different frames arrive).
//   3. Taps on the client's mirrored view appear on the host as a touch
//      indicator at the same normalised position (centre).
//   4. Switching the host to the Museum Map is mirrored to the client.
//   5. Disconnect / host-stop is noticed by the other side.

import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mirror/firebase_options.dart';
import 'package:mirror/main.dart';

// ---------------------------------------------------------------------------
// Configuration (compile-time, via --dart-define)
// ---------------------------------------------------------------------------

const String kRole = String.fromEnvironment('ROLE');
const String kMode = String.fromEnvironment('MODE', defaultValue: 'websocket');
const String kHostIp = String.fromEnvironment('HOST_IP');
const String kRoom = String.fromEnvironment(
  'ROOM',
  defaultValue: 'it_room_default',
);

/// How long a device waits for the OTHER device to build, install and start.
const Duration _startupTimeout = Duration(minutes: 6);

/// How long a device waits for a single step of the scenario.
const Duration _stepTimeout = Duration(minutes: 2);

const Timeout _testTimeout = Timeout(Duration(minutes: 20));

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void log(String message) {
  // ignore: avoid_print
  print('[$kRole/$kMode] $message');
}

/// Pumps frames in real time until [condition] is true.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after ${timeout.inSeconds}s waiting for: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

/// Pumps frames in real time for [duration].
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const MirrorApp());
  await tester.pumpAndSettle();
}

Future<void> openFromMenu(WidgetTester tester, String cardTitle) async {
  final card = find.text(cardTitle);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

Future<void> goBack(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  // Give sockets / Firestore deletes time to finish before the app exits.
  await Future<void>.delayed(const Duration(seconds: 1));
}

/// Bytes of the frame currently displayed by a client screen.
Uint8List currentFrame(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image).first);
  final provider = image.image;
  if (provider is MemoryImage) return provider.bytes;
  fail('Unexpected image provider: ${provider.runtimeType}');
}

Future<void> expectValidPng(Uint8List bytes) async {
  expect(bytes.length, greaterThan(8));
  expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'PNG magic');
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  expect(frame.image.width, greaterThan(0));
  expect(frame.image.height, greaterThan(0));
  frame.image.dispose();
  codec.dispose();
}

/// Waits until the client has displayed at least [count] different frames.
Future<void> waitForDistinctFrames(
  WidgetTester tester, {
  required int count,
  required Duration timeout,
  required String reason,
}) async {
  final seen = <int>{};
  await pumpUntil(
    tester,
    () {
      if (find.byType(Image).evaluate().isEmpty) return false;
      seen.add(Object.hashAll(currentFrame(tester)));
      return seen.length >= count;
    },
    timeout: timeout,
    reason: reason,
  );
}

/// The 40x40 circle both client screens draw where the user just tapped.
final Finder _clientTouchDot = find.byWidgetPredicate((w) {
  if (w is! Container) return false;
  final d = w.decoration;
  return d is BoxDecoration &&
      d.shape == BoxShape.circle &&
      w.constraints?.maxWidth == 40 &&
      w.constraints?.maxHeight == 40;
});

/// CLIENT: taps the centre of the mirrored view [count] times.
Future<void> tapCenterOfMirror(
  WidgetTester tester, {
  required int count,
  required Duration gap,
}) async {
  for (var i = 1; i <= count; i++) {
    final center = tester.getCenter(find.byType(Image).first);
    await tester.tapAt(center);
    await tester.pump();
    expect(
      _clientTouchDot,
      findsOneWidget,
      reason: 'client should show local tap feedback (tap $i)',
    );
    log('tap $i/$count sent');
    await pumpFor(tester, gap);
  }
}

/// HOST: flips the Switch every 1.5 s (so the mirrored picture keeps
/// changing) until [until] becomes true.
Future<void> toggleSwitchUntil(
  WidgetTester tester, {
  required bool Function() until,
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  var nextToggle = DateTime.now();
  while (!until()) {
    final now = DateTime.now();
    if (now.isAfter(deadline)) fail('Timed out waiting for: $reason');
    if (now.isAfter(nextToggle)) {
      await tester.tap(find.byType(Switch));
      nextToggle = now.add(const Duration(milliseconds: 1500));
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump();
  }
}

/// HOST: alternates between the dashboard and the Museum Map every 2 s
/// (selecting the ZOO pin on the map) until [done] is true. [done] is only
/// evaluated while the dashboard is showing.
Future<void> alternateTabsUntil(
  WidgetTester tester, {
  required String dashboardLabel,
  required bool Function() done,
  required Duration timeout,
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  var onMap = false;
  var nextSwitch = DateTime.now();
  while (true) {
    if (!onMap && done()) return;
    final now = DateTime.now();
    if (now.isAfter(deadline)) fail('Timed out waiting for: $reason');
    if (now.isAfter(nextSwitch)) {
      onMap = !onMap;
      await tester.tap(find.text(onMap ? 'Museum Map' : dashboardLabel));
      await tester.pump(const Duration(milliseconds: 300));
      if (onMap) {
        final zoo = find.widgetWithText(ActionChip, 'ZOO');
        if (zoo.evaluate().isNotEmpty) {
          await tester.ensureVisible(zoo);
          await tester.tap(zoo);
          await tester.pump(const Duration(milliseconds: 300));
        }
      }
      nextSwitch = DateTime.now().add(const Duration(seconds: 2));
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump();
  }
}

/// HOST: the remote-touch indicator must be at the horizontal centre because
/// the client always taps the centre of its mirrored view.
void expectTouchIndicatorCentered(WidgetTester tester, Finder indicator) {
  final center = tester.getCenter(indicator.first);
  final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
  expect(
    center.dx,
    closeTo(screenWidth / 2, 4.0),
    reason: 'touch indicator should be at the horizontal centre of the host',
  );
}

// ---------------------------------------------------------------------------
// WebSocket scenario
// ---------------------------------------------------------------------------

void _webSocketHost() {
  testWidgets('WebSocket HOST: streams its screen, receives remote touches',
      (tester) async {
    await launchApp(tester);
    await openFromMenu(tester, 'WebSocket Host');

    // 1. Server comes up and shows its Wi-Fi address.
    await pumpUntil(
      tester,
      () => find.textContaining(':8080').evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'server address (":8080") on screen',
    );
    expect(find.text('Failed to start server'), findsNothing);
    final addressText =
        tester.widget<Text>(find.textContaining(':8080').first).data ?? '';
    final ip = addressText.replaceAll(':8080', '').trim();
    expect(
      ip,
      isNot('127.0.0.1'),
      reason: 'Host has no Wi-Fi/LAN address. Connect it to the same Wi-Fi '
          'as the client device.',
    );
    expect(ip, matches(RegExp(r'^\d{1,3}(\.\d{1,3}){3}$')));
    log('HOST_READY ip=$ip'); // <- run_two_devices.sh waits for this line

    // 2. Wait for the client device.
    log('waiting for the client device to connect...');
    await pumpUntil(
      tester,
      () => find.text('Connected WebSocket Clients: 1').evaluate().isNotEmpty,
      timeout: _startupTimeout,
      reason: 'client device to connect',
    );
    log('client connected');

    // 3. Phase A - keep the screen changing until the client taps it.
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 300));
    final touch = find.byIcon(Icons.touch_app);
    await toggleSwitchUntil(
      tester,
      until: () => touch.evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'remote touch indicator from the client',
    );
    expectTouchIndicatorCentered(tester, touch);
    log('remote touch received at the expected position');

    // 4. Phase B - show the Museum Map etc. until the client leaves.
    await alternateTabsUntil(
      tester,
      dashboardLabel: 'Interactive UI',
      done: () =>
          find.text('Connected WebSocket Clients: 0').evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'client to disconnect',
    );
    log('client disconnected - host test finished');

    await goBack(tester);
  }, timeout: _testTimeout);
}

void _webSocketClient() {
  testWidgets('WebSocket CLIENT: mirrors the host and sends taps',
      (tester) async {
    expect(
      kHostIp,
      isNotEmpty,
      reason: 'Pass --dart-define=HOST_IP=<host device Wi-Fi IP>',
    );

    await launchApp(tester);
    await openFromMenu(tester, 'WebSocket Client');
    await tester.enterText(find.byType(TextField), kHostIp);
    await tester.pump();

    // 1. Connect (retry until the host is reachable and streaming).
    final connectButton = find.widgetWithText(ElevatedButton, 'Connect');
    final deadline = DateTime.now().add(_startupTimeout);
    var attempt = 0;
    while (find.byType(Image).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Could not receive a frame from ws://$kHostIp:8080 in time');
      }
      if (connectButton.evaluate().isNotEmpty) {
        attempt++;
        log('connect attempt $attempt to ws://$kHostIp:8080');
        await tester.tap(connectButton);
      }
      final until = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(until) &&
          find.byType(Image).evaluate().isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    }
    expect(find.text('Connected!'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Disconnect'), findsOneWidget);
    log('connected, first frame received');

    // 2. The frame is a real PNG of the host screen.
    await expectValidPng(currentFrame(tester));

    // 3. Host screen changes (switch toggling) show up as new frames.
    await waitForDistinctFrames(
      tester,
      count: 2,
      timeout: _stepTimeout,
      reason: 'a changed frame from the host',
    );
    log('host screen changes are mirrored');

    // 4. Tap the mirrored view -> host must show a touch indicator.
    await tapCenterOfMirror(
      tester,
      count: 6,
      gap: const Duration(milliseconds: 700),
    );

    // 5. Host switches to the Museum Map and back -> more distinct frames.
    await waitForDistinctFrames(
      tester,
      count: 3,
      timeout: _stepTimeout,
      reason: 'frames of the host switching tabs / opening the map',
    );
    log('museum map / tab changes are mirrored');

    // 6. Disconnect cleanly.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Disconnect'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    log('disconnected - client test finished');

    await goBack(tester);
  }, timeout: _testTimeout);
}

// ---------------------------------------------------------------------------
// Firebase scenario
// ---------------------------------------------------------------------------

void _firebaseHost() {
  testWidgets('Firebase HOST: publishes its screen, receives cloud touches',
      (tester) async {
    await launchApp(tester);
    await openFromMenu(tester, 'Firebase Host');

    // 1. Start hosting in the shared room.
    await tester.enterText(find.byType(TextField), kRoom);
    await tester.pump();
    final startButton = find.text('Start Host');
    await tester.ensureVisible(startButton);
    await tester.pumpAndSettle();
    await tester.tap(startButton);
    await tester.pump();

    await pumpUntil(
      tester,
      () => find.text('Stop').evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'Firebase hosting to start (check that Firestore exists, the '
          'rules allow access to mirror_rooms, and the device is online)',
    );
    expect(find.text('Cloud Room $kRoom Live'), findsOneWidget);
    log('HOST_READY room=$kRoom'); // <- run_two_devices.sh waits for this

    // 2. Phase A - keep the screen changing until a cloud touch arrives.
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 300));
    final touch = find.byIcon(Icons.touch_app_rounded);
    log('waiting for the client device...');
    await toggleSwitchUntil(
      tester,
      until: () => touch.evaluate().isNotEmpty,
      timeout: _startupTimeout,
      reason: 'cloud touch indicator from the client',
    );
    expectTouchIndicatorCentered(tester, touch);
    log('cloud touch received at the expected position');

    // 3. Phase B - show the Museum Map etc. for a while.
    final phaseBEnd = DateTime.now().add(const Duration(seconds: 12));
    await alternateTabsUntil(
      tester,
      dashboardLabel: 'Host Dashboard',
      done: () => DateTime.now().isAfter(phaseBEnd),
      timeout: _stepTimeout,
      reason: 'phase B to finish',
    );

    // 4. Stop hosting -> the client must notice the room is gone.
    await tester.ensureVisible(find.text('Stop'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Firebase Offline'), findsOneWidget);
    expect(find.text('Start Host'), findsOneWidget);
    log('hosting stopped - waiting for Firestore clean-up');
    await pumpFor(tester, const Duration(seconds: 6));

    await goBack(tester);
  }, timeout: _testTimeout);
}

void _firebaseClient() {
  testWidgets('Firebase CLIENT: mirrors the cloud room and sends taps',
      (tester) async {
    await launchApp(tester);
    await openFromMenu(tester, 'Firebase Client');

    // 1. Join the shared room (waits for the host if it is not there yet).
    await tester.enterText(find.byType(TextField), kRoom);
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Connect'));
    await tester.pump();

    await pumpUntil(
      tester,
      () => find.text('Disconnect').evaluate().isNotEmpty,
      timeout: _startupTimeout,
      reason: 'host to appear in room $kRoom',
    );
    expect(find.text('Connected to Room: $kRoom'), findsOneWidget);
    log('connected to room $kRoom');

    // 2. First frame arrives and is a real PNG.
    await pumpUntil(
      tester,
      () => find.byType(Image).evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'first cloud frame',
    );
    await expectValidPng(currentFrame(tester));
    log('first frame received');

    // 3. Host screen changes show up as new frames.
    await waitForDistinctFrames(
      tester,
      count: 2,
      timeout: _stepTimeout,
      reason: 'a changed frame from the host',
    );
    log('host screen changes are mirrored');

    // 4. Tap the mirrored view -> host must show a touch indicator.
    await tapCenterOfMirror(
      tester,
      count: 5,
      gap: const Duration(milliseconds: 1200),
    );

    // 5. Host switches tabs / opens the map -> more distinct frames.
    await waitForDistinctFrames(
      tester,
      count: 2,
      timeout: _stepTimeout,
      reason: 'frames of the host switching tabs / opening the map',
    );
    log('museum map / tab changes are mirrored');

    // 6. Host stops -> client notices the room is gone.
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Waiting for Host in Room').evaluate().isNotEmpty ||
          find.text('Host is offline').evaluate().isNotEmpty,
      timeout: _stepTimeout,
      reason: 'client to notice the host stopped',
    );
    expect(find.byType(Image), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
    log('host stop detected - client test finished');

    await goBack(tester);
  }, timeout: _testTimeout);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (kRole != 'host' && kRole != 'client') {
    test('configuration', () {
      fail('Missing --dart-define=ROLE=host  or  --dart-define=ROLE=client');
    });
    return;
  }
  if (kMode != 'websocket' && kMode != 'firebase') {
    test('configuration', () {
      fail('MODE must be "websocket" or "firebase" (got "$kMode")');
    });
    return;
  }

  if (kMode == 'firebase') {
    setUpAll(() async {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    });
  }

  if (kMode == 'websocket') {
    kRole == 'host' ? _webSocketHost() : _webSocketClient();
  } else {
    kRole == 'host' ? _firebaseHost() : _firebaseClient();
  }
}