import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/websocket/websocket_protocol.dart';
import 'package:mirror/websocket/websocket_service.dart';

void main() {
  group('WebSocket services', () {
    test('host and client exchange frames and gestures', () async {
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portProbe.port;
      await portProbe.close();

      final server = WebSocketServerService();
      final client = WebSocketClientService();
      final connectedClientCount = Completer<int>();
      final disconnectedClientCount = Completer<int>();
      final receivedFrame = Completer<WebSocketFramePacket>();
      final receivedGesture = Completer<WebSocketGesturePacket>();

      server.onClientCountChanged = (count) {
        if (count == 1 && !connectedClientCount.isCompleted) {
          connectedClientCount.complete(count);
        }
        if (count == 0 && !disconnectedClientCount.isCompleted) {
          disconnectedClientCount.complete(count);
        }
      };
      server.onGestureReceived = (gesture) {
        if (!receivedGesture.isCompleted) receivedGesture.complete(gesture);
      };
      client.onFrameReceived = (frame) {
        if (!receivedFrame.isCompleted) receivedFrame.complete(frame);
      };

      addTearDown(() async {
        await client.disconnect();
        await server.stopServer();
      });

      expect(await server.startServer(port: port), isTrue);
      expect(server.isHosting, isTrue);
      expect(await client.connect('127.0.0.1', port: port), isTrue);
      expect(
        await connectedClientCount.future.timeout(const Duration(seconds: 5)),
        1,
      );

      server.broadcast(
        jsonEncode(
          WebSocketFramePacket(
            base64: 'aGVsbG8=',
            width: 640,
            height: 480,
            timestamp: 12345,
          ).toJson(),
        ),
      );
      final frame = await receivedFrame.future.timeout(
        const Duration(seconds: 5),
      );
      expect(frame.base64, 'aGVsbG8=');
      expect(frame.width, 640);
      expect(frame.height, 480);

      client.sendGesture(
        WebSocketGesturePacket(
          action: 'down',
          pointerId: 7,
          normalizedX: 0.25,
          normalizedY: 0.75,
        ),
      );
      final gesture = await receivedGesture.future.timeout(
        const Duration(seconds: 5),
      );
      expect(gesture.action, 'down');
      expect(gesture.pointerId, 7);
      expect(gesture.normalizedX, 0.25);
      expect(gesture.normalizedY, 0.75);

      await client.disconnect();
      expect(
        await disconnectedClientCount.future.timeout(
          const Duration(seconds: 5),
        ),
        0,
      );
      expect(client.isConnected, isFalse);
      expect(server.clientCount, 0);
    });

    test('reports a busy port and leaves the host stopped', () async {
      final occupiedPort = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final server = WebSocketServerService();
      String? log;
      server.onLog = (message) => log = message;

      addTearDown(occupiedPort.close);
      addTearDown(server.stopServer);

      expect(await server.startServer(port: occupiedPort.port), isFalse);
      expect(server.isHosting, isFalse);
      expect(log, contains('Failed to start server'));
    });
  });
}
