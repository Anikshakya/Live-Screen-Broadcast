import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_mirror_service.dart';
import 'firebase_protocol.dart';

class FirebaseClientScreen extends StatefulWidget {
  const FirebaseClientScreen({super.key});

  @override
  State<FirebaseClientScreen> createState() => _FirebaseClientScreenState();
}

class _FirebaseClientScreenState extends State<FirebaseClientScreen> {
  final TextEditingController _roomIdController = TextEditingController(text: "room_101");
  final FirebaseMirrorService _firebaseService = FirebaseMirrorService();

  bool _isConnected = false;
  String _status = "Firebase Offline";
  Uint8List? _latestImageBytes;
  Offset? _localTouchPoint;

  @override
  void dispose() {
    _disconnectFirebase();
    _roomIdController.dispose();
    super.dispose();
  }

  Future<void> _toggleFirebaseConnection() async {
    FocusScope.of(context).unfocus();

    if (_isConnected) {
      await _disconnectFirebase();
    } else {
      final roomId = _roomIdController.text.trim();
      if (roomId.isNotEmpty) {
        setState(() => _status = "Connecting to Firebase Room $roomId...");
        await _connectFirebase(roomId);
      }
    }
  }

  Future<void> _connectFirebase(String roomId) async {
    bool success = await _firebaseService.connectToSession(
      roomId: roomId,
      onFrameReceived: (frame) {
        if (mounted) {
          try {
            final bytes = base64Decode(frame.base64);
            setState(() {
              _latestImageBytes = bytes;
              _isConnected = true;
            });
          } catch (e) {
            debugPrint("Firebase frame decode error: $e");
          }
        }
      },
      onStatusChanged: (connected, statusMsg) {
        if (mounted) {
          setState(() {
            _isConnected = connected;
            _status = statusMsg;
            if (!connected) {
              _latestImageBytes = null;
            }
          });
        }
      },
    );

    if (!success && mounted) {
      setState(() {
        _isConnected = false;
      });
    }
  }

  Future<void> _disconnectFirebase() async {
    await _firebaseService.disconnectClient();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _status = "Disconnected";
        _latestImageBytes = null;
        _localTouchPoint = null;
      });
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (!_isConnected) return;
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) return;

    final normalizedX = details.localPosition.dx / constraints.maxWidth;
    final normalizedY = details.localPosition.dy / constraints.maxHeight;

    setState(() {
      _localTouchPoint = details.localPosition;
    });

    final gesture = FirebaseGesturePacket(
      action: 'down',
      normalizedX: normalizedX,
      normalizedY: normalizedY,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    _firebaseService.sendGesture(roomId: roomId, gesture: gesture);

    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _localTouchPoint = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_download_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FIREBASE CLOUD CLIENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Text('Real-Time Cloud Mirror', style: TextStyle(fontSize: 10, color: Colors.orangeAccent)),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildConnectionHeader(),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isConnected ? Colors.orangeAccent : const Color(0xFF334155),
                    width: _isConnected ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onTapUp: (details) => _handleTap(details, constraints),
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_latestImageBytes != null)
                              Image.memory(
                                _latestImageBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                              )
                            else
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isConnected ? Icons.cloud_sync_rounded : Icons.cloud_off_rounded,
                                      size: 56,
                                      color: _isConnected ? Colors.orangeAccent : Colors.white24,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isConnected
                                          ? "Waiting for cloud host frame broadcast..."
                                          : "Connect to a Firebase Room ID to view stream.",
                                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            if (_localTouchPoint != null)
                              Positioned(
                                left: _localTouchPoint!.dx - 20,
                                top: _localTouchPoint!.dy - 20,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.orangeAccent.withValues(alpha: 0.5),
                                    border: Border.all(color: Colors.orangeAccent, width: 2),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roomIdController,
                  enabled: !_isConnected,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Firebase Room ID',
                    labelStyle: const TextStyle(color: Colors.orangeAccent),
                    prefixIcon: const Icon(Icons.meeting_room_rounded, color: Colors.orangeAccent, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _toggleFirebaseConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isConnected ? Colors.redAccent : Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_isConnected ? "Disconnect" : "Connect"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 12,
                  color: _isConnected ? Colors.greenAccent : Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
