import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'firebase_protocol.dart';

class FirebaseMirrorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _sessionSubscription;
  StreamSubscription<QuerySnapshot>? _gestureSubscription;

  bool _isHosting = false;
  bool _isConnected = false;
  int? _lastFrameHash;

  bool get isHosting => _isHosting;
  bool get isConnected => _isConnected;

  // --- HOST METHODS ---

  Future<bool> startHostSession({
    required String roomId,
    required Function(FirebaseGesturePacket gesture) onGestureReceived,
    required Function(String status) onStatusChanged,
  }) async {
    _isHosting = false;
    _lastFrameHash = null;
    await _gestureSubscription?.cancel();
    _gestureSubscription = null;

    try {
      onStatusChanged("Publishing Room $roomId to Cloud...");
      final docRef = _firestore.collection('mirror_rooms').doc(roomId);

      // Verify Cloud Firestore server write
      await docRef.set({
        'active': true,
        'base64': '',
        'width': 0,
        'height': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException("Could not reach Cloud Firestore. Verify database is created in Firebase Console.");
        },
      );

      _isHosting = true;
      _lastFrameHash = null;
      onStatusChanged("Cloud Room $roomId Live");

      // Listen for incoming remote gestures in real-time
      final gestureCol = docRef.collection('gestures');
      _gestureSubscription = gestureCol
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final lastDoc = snapshot.docs.last.data();
          onGestureReceived(FirebaseGesturePacket.fromJson(lastDoc));
        }
      }, onError: (err) {
        debugPrint("Gesture listener notice: $err");
      });

      return true;
    } catch (e) {
      debugPrint("startHostSession Exception: $e");
      _isHosting = false;
      onStatusChanged("Host Connection Error: $e");
      return false;
    }
  }

  void broadcastFrame({
    required String roomId,
    required String base64Frame,
    required int width,
    required int height,
  }) {
    if (!_isHosting || base64Frame.isEmpty) return;

    // Safety guard against Firestore 1MB (1,048,487 bytes) document limit
    if (base64Frame.length > 950000) {
      debugPrint("Skipping frame: payload size (${base64Frame.length}) exceeds Firestore 1MB limit");
      return;
    }

    // Skip duplicate frame writes to save latency & network bandwidth
    final frameHash = base64Frame.hashCode;
    if (_lastFrameHash == frameHash) return;
    _lastFrameHash = frameHash;

    try {
      _firestore.collection('mirror_rooms').doc(roomId).set({
        'active': true,
        'base64': base64Frame,
        'width': width,
        'height': height,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Firebase Broadcast Error: $e");
    }
  }

  Future<void> stopHostSession({required String roomId}) async {
    _isHosting = false;
    _lastFrameHash = null;
    try {
      await _gestureSubscription?.cancel();
      _gestureSubscription = null;

      if (roomId.isNotEmpty) {
        final docRef = _firestore.collection('mirror_rooms').doc(roomId);
        final gestureCol = docRef.collection('gestures');
        final gestures = await gestureCol.get();
        for (var doc in gestures.docs) {
          doc.reference.delete().catchError((_) {});
        }
        await docRef.delete();
      }
    } catch (e) {
      debugPrint("Error deleting host session document: $e");
    }
  }

  // --- CLIENT METHODS ---

  Future<bool> connectToSession({
    required String roomId,
    required Function(FirebaseFramePacket frame) onFrameReceived,
    required Function(bool connected, String status) onStatusChanged,
  }) async {
    await disconnectClient();

    try {
      onStatusChanged(false, "Connecting to Room $roomId...");
      final docRef = _firestore.collection('mirror_rooms').doc(roomId);

      _sessionSubscription = docRef.snapshots().listen(
        (snapshot) {
          if (!snapshot.exists) {
            _isConnected = false;
            onStatusChanged(false, "Waiting for Host in Room $roomId...");
            return;
          }

          final data = snapshot.data();
          if (data == null) {
            _isConnected = false;
            onStatusChanged(false, "No data in Room $roomId");
            return;
          }

          final bool active = data['active'] ?? false;
          if (!active) {
            _isConnected = false;
            onStatusChanged(false, "Host is offline");
            return;
          }

          if (!_isConnected) {
            _isConnected = true;
            onStatusChanged(true, "Connected to Room: $roomId");
          }

          final base64String = data['base64'] as String?;
          if (base64String != null && base64String.isNotEmpty) {
            final frame = FirebaseFramePacket(
              base64: base64String,
              width: data['width'] ?? 0,
              height: data['height'] ?? 0,
              timestamp: data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
            );
            onFrameReceived(frame);
          }
        },
        onError: (err) {
          _isConnected = false;
          onStatusChanged(false, "Connection Error: $err");
        },
      );

      return true;
    } catch (e) {
      _isConnected = false;
      onStatusChanged(false, "Failed to connect: $e");
      return false;
    }
  }

  void sendGesture({
    required String roomId,
    required FirebaseGesturePacket gesture,
  }) {
    if (!_isConnected || roomId.isEmpty) return;

    try {
      _firestore
          .collection('mirror_rooms')
          .doc(roomId)
          .collection('gestures')
          .add(gesture.toJson());
    } catch (_) {}
  }

  Future<void> disconnectClient() async {
    _isConnected = false;
    try {
      await _sessionSubscription?.cancel();
      _sessionSubscription = null;
    } catch (_) {}
  }
}
