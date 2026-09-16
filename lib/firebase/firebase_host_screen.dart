import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../shared/museum_map_view.dart';
import '../shared/museum_poi.dart';
import 'firebase_mirror_service.dart';

class FirebaseHostScreen extends StatefulWidget {
  const FirebaseHostScreen({super.key});

  @override
  State<FirebaseHostScreen> createState() => _FirebaseHostScreenState();
}

class _FirebaseHostScreenState extends State<FirebaseHostScreen> {
  final GlobalKey _globalKey = GlobalKey();
  final FirebaseMirrorService _firebaseService = FirebaseMirrorService();
  final TextEditingController _roomIdController = TextEditingController(
    text: "room_101",
  );

  bool _isFirebaseHosting = false;
  String _status = "Firebase Cloud Ready";
  Offset? _remoteGesturePoint;
  Timer? _frameTimer;
  bool _isCapturing = false;

  // UI Interactive State
  int _currentTabIndex = 0;
  double _sliderValue = 65.0;
  bool _switchValue = true;
  final List<Offset?> _drawnPoints = [];

  @override
  void dispose() {
    _stopFirebaseHosting();
    _roomIdController.dispose();
    super.dispose();
  }

  void _generateRandomRoom() {
    if (_isFirebaseHosting) return;
    final randomCode = math.Random().nextInt(9000) + 1000;
    setState(() {
      _roomIdController.text = "room_$randomCode";
    });
  }

  void _toggleFirebaseHosting() {
    if (_isFirebaseHosting) {
      _stopFirebaseHosting();
    } else {
      _startFirebaseHosting();
    }
  }

  Future<void> _startFirebaseHosting() async {
    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or generate a valid Room ID'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _status = "Connecting to Firebase Room $roomId...";
    });

    bool success = await _firebaseService.startHostSession(
      roomId: roomId,
      onGestureReceived: (gesture) {
        if (mounted) {
          if (gesture.action == 'down' || gesture.action == 'move') {
            final size = MediaQuery.of(context).size;
            setState(() {
              _remoteGesturePoint = Offset(
                gesture.normalizedX * size.width,
                gesture.normalizedY * size.height,
              );
            });
            Timer(const Duration(milliseconds: 800), () {
              if (mounted) setState(() => _remoteGesturePoint = null);
            });
          }
        }
      },
      onStatusChanged: (statusMsg) {
        if (mounted) setState(() => _status = statusMsg);
      },
    );

    if (success) {
      setState(() => _isFirebaseHosting = true);
      _frameTimer?.cancel();
      // High-speed real-time capture loop
      _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        _captureAndSendCloudFrame();
      });
    }
  }

  Future<void> _captureAndSendCloudFrame() async {
    if (_isCapturing || !_isFirebaseHosting) return;
    _isCapturing = true;

    try {
      final boundary =
          _globalKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _isCapturing = false;
        return;
      }

      // Optimized pixelRatio (0.38) for fast frame encoding under Firestore 1MB limits
      final image = await boundary.toImage(pixelRatio: 0.38);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final base64String = base64Encode(byteData.buffer.asUint8List());
        _firebaseService.broadcastFrame(
          roomId: _roomIdController.text.trim(),
          base64Frame: base64String,
          width: image.width,
          height: image.height,
        );
      }
    } catch (e) {
      debugPrint("Cloud capture frame error: $e");
    } finally {
      _isCapturing = false;
    }
  }

  void _stopFirebaseHosting() {
    _frameTimer?.cancel();
    _frameTimer = null;
    final roomId = _roomIdController.text.trim();
    if (roomId.isNotEmpty) {
      _firebaseService.stopHostSession(roomId: roomId);
    }
    if (mounted) {
      setState(() {
        _isFirebaseHosting = false;
        _status = "Firebase Offline";
      });
    }
  }

  @override
  Widget build(BuildContext meContext) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _stopFirebaseHosting();
        }
      },
      child: RepaintBoundary(
        key: _globalKey,
        child: Scaffold(
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
                  child: const Icon(
                    Icons.local_fire_department,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FIREBASE CLOUD HOST',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Global Real-Time Broadcast',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orangeAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              Container(
                color: const Color(0xFF0F172A),
                child: _currentTabIndex == 0
                    ? _buildInteractiveDashboard()
                    : MuseumMapView(pois: MuseumPoi.samplePois),
              ),

              // Remote Gesture Visualizer Overlay
              if (_remoteGesturePoint != null)
                Positioned(
                  left: _remoteGesturePoint!.dx - 24,
                  top: _remoteGesturePoint!.dy - 24,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orangeAccent.withValues(alpha: 0.4),
                      border: Border.all(
                        color: Colors.orangeAccent,
                        width: 2.5,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.orangeAccent,
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.touch_app_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentTabIndex,
            onTap: (index) => setState(() => _currentTabIndex = index),
            backgroundColor: const Color(0xFF1E293B),
            selectedItemColor: Colors.orangeAccent,
            unselectedItemColor: Colors.white54,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Host Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.map_rounded),
                label: 'Museum Map',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFirebaseStatusCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildDrawingArea(),
        ],
      ),
    );
  }

  Widget _buildFirebaseStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.meeting_room_rounded,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "FIREBASE ROOM SETTINGS",
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              if (!_isFirebaseHosting)
                TextButton.icon(
                  onPressed: _generateRandomRoom,
                  icon: const Icon(
                    Icons.casino_rounded,
                    size: 16,
                    color: Colors.orangeAccent,
                  ),
                  label: const Text(
                    "New Room",
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _roomIdController,
                  enabled: !_isFirebaseHosting,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Firebase Room ID',
                    labelStyle: const TextStyle(color: Colors.orangeAccent),
                    prefixIcon: const Icon(
                      Icons.cloud_upload_rounded,
                      color: Colors.orangeAccent,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: Colors.white60,
                        size: 18,
                      ),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _roomIdController.text.trim()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Room ID copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _toggleFirebaseHosting,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isFirebaseHosting
                      ? Colors.redAccent
                      : Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  _isFirebaseHosting
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                ),
                label: Text(_isFirebaseHosting ? "Stop" : "Start Host"),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isFirebaseHosting
                      ? Icons.sensors_rounded
                      : Icons.sensors_off_rounded,
                  size: 14,
                  color: _isFirebaseHosting
                      ? Colors.greenAccent
                      : Colors.white38,
                ),
                const SizedBox(width: 8),
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _isFirebaseHosting
                        ? Colors.greenAccent
                        : Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.orangeAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "Interactive UI Controls",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Cloud Feature Toggle:",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Switch(
                value: _switchValue,
                activeThumbColor: Colors.orangeAccent,
                onChanged: (val) => setState(() => _switchValue = val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Sync Level: ${_sliderValue.toInt()}%",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Slider(
                value: _sliderValue,
                min: 0,
                max: 100,
                activeColor: Colors.orangeAccent,
                inactiveColor: const Color(0xFF334155),
                onChanged: (val) => setState(() => _sliderValue = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingArea() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.gesture_rounded,
                    color: Colors.orangeAccent,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    "Cloud Live Canvas",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => setState(() => _drawnPoints.clear()),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  "Clear",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 16),
          const SizedBox(height: 8),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border.all(color: const Color(0xFF334155)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                onPanStart: (details) =>
                    setState(() => _drawnPoints.add(details.localPosition)),
                onPanUpdate: (details) =>
                    setState(() => _drawnPoints.add(details.localPosition)),
                onPanEnd: (details) => setState(() => _drawnPoints.add(null)),
                child: CustomPaint(
                  painter: _FirebaseDrawingPainter(_drawnPoints),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebaseDrawingPainter extends CustomPainter {
  final List<Offset?> points;
  _FirebaseDrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.orangeAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FirebaseDrawingPainter oldDelegate) => true;
}
