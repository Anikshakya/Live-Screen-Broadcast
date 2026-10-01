import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mirror/websocket/websocket_protocol.dart';

void main() {

  group('WebSocketGesturePacket', () {

    test('survives a JSON round trip', () {

      final original = WebSocketGesturePacket(

        action: 'move', pointerId: 3, normalizedX: 0.25, normalizedY: 0.75,

      );

      final decoded = WebSocketGesturePacket.fromJson(

        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,

      );

      expect(decoded.action, 'move');

      expect(decoded.pointerId, 3);

      expect(decoded.normalizedX, 0.25);

      expect(decoded.normalizedY, 0.75);

    });

    test('missing fields fall back to safe defaults', () {

      final decoded = WebSocketGesturePacket.fromJson({});

      expect(decoded.action, 'unknown');

      expect(decoded.pointerId, 0);

    });

  });

}
