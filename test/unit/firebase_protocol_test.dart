import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/firebase/firebase_protocol.dart';

void main() {
  group('FirebaseFramePacket', () {
    test('survives a JSON round trip', () {
      final original = FirebaseFramePacket(
        base64: 'aGVsbG8=',
        width: 640,
        height: 480,
        timestamp: 12345,
      );
      final decoded = FirebaseFramePacket.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.base64, 'aGVsbG8=');
      expect(decoded.width, 640);
      expect(decoded.height, 480);
      expect(decoded.timestamp, 12345);
    });

    test('missing fields use safe defaults', () {
      final decoded = FirebaseFramePacket.fromJson({});

      expect(decoded.base64, isEmpty);
      expect(decoded.width, 0);
      expect(decoded.height, 0);
      expect(decoded.timestamp, greaterThan(0));
    });
  });

  group('FirebaseGesturePacket', () {
    test('survives a JSON round trip', () {
      final original = FirebaseGesturePacket(
        action: 'move',
        normalizedX: 0.25,
        normalizedY: 0.75,
        timestamp: 12345,
      );
      final decoded = FirebaseGesturePacket.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.action, 'move');
      expect(decoded.normalizedX, 0.25);
      expect(decoded.normalizedY, 0.75);
      expect(decoded.timestamp, 12345);
    });

    test('missing fields use safe defaults', () {
      final decoded = FirebaseGesturePacket.fromJson({});

      expect(decoded.action, 'down');
      expect(decoded.normalizedX, 0);
      expect(decoded.normalizedY, 0);
      expect(decoded.timestamp, greaterThan(0));
    });
  });
}
