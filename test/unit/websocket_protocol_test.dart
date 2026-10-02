import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mirror/websocket/websocket_protocol.dart';

void main() {
  group('WebSocketFramePacket', () {
    test('survives a JSON round trip', () {
      final original = WebSocketFramePacket(
        base64: 'aGVsbG8=',
        width: 640,
        height: 480,
        timestamp: 12345,
      );
      final json =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final decoded = WebSocketFramePacket.fromBase64Json(json);

      expect(json['type'], 'frame');
      expect(decoded.base64, 'aGVsbG8=');
      expect(decoded.width, 640);
      expect(decoded.height, 480);
      expect(decoded.timestamp, 12345);
    });

    test('missing fields use safe defaults', () {
      final decoded = WebSocketFramePacket.fromBase64Json({});

      expect(decoded.base64, isEmpty);
      expect(decoded.width, 0);
      expect(decoded.height, 0);
      expect(decoded.timestamp, greaterThan(0));
    });
  });

  group('WebSocketGesturePacket', () {
    test('survives a JSON round trip', () {
      final original = WebSocketGesturePacket(
        action: 'move',
        pointerId: 3,
        normalizedX: 0.25,
        normalizedY: 0.75,
      );
      final json =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      final decoded = WebSocketGesturePacket.fromJson(json);

      expect(json['type'], 'gesture');
      expect(decoded.action, 'move');
      expect(decoded.pointerId, 3);
      expect(decoded.normalizedX, 0.25);
      expect(decoded.normalizedY, 0.75);
    });

    test('missing fields fall back to safe defaults', () {
      final decoded = WebSocketGesturePacket.fromJson({});

      expect(decoded.action, 'unknown');
      expect(decoded.pointerId, 0);
      expect(decoded.normalizedX, 0);
      expect(decoded.normalizedY, 0);
    });
  });
}
