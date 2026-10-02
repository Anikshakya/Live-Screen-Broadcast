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

    test('serializes the Firestore frame fields', () {
      final packet = FirebaseFramePacket(
        base64: 'aGVsbG8=',
        width: 640,
        height: 480,
        timestamp: 12345,
      );

      expect(packet.toJson(), {
        'base64': 'aGVsbG8=',
        'width': 640,
        'height': 480,
        'timestamp': 12345,
      });
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

    test('decodes integer coordinates as doubles', () {
      final decoded = FirebaseGesturePacket.fromJson({
        'action': 'up',
        'normalizedX': 1,
        'normalizedY': 0,
        'timestamp': 12345,
      });

      expect(decoded.action, 'up');
      expect(decoded.normalizedX, 1.0);
      expect(decoded.normalizedY, 0.0);
      expect(decoded.timestamp, 12345);
    });

    test('serializes the Firestore gesture fields', () {
      final packet = FirebaseGesturePacket(
        action: 'down',
        normalizedX: 0.25,
        normalizedY: 0.75,
        timestamp: 12345,
      );

      expect(packet.toJson(), {
        'action': 'down',
        'normalizedX': 0.25,
        'normalizedY': 0.75,
        'timestamp': 12345,
      });
    });
  });
}
