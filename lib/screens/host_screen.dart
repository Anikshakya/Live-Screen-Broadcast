import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mirror/network/websocket_service.dart';

import '../models/mirror_protocol.dart';
import '../models/museum_poi.dart';
import 'museum_map_view.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  final WebSocketServerService _server = WebSocketServerService();
  final GlobalKey _boundaryKey = GlobalKey();

  // Server & Capture State
  String _status = "Starting server...";
  int _clientCount = 0;
  Timer? _frameTimer;
  bool _isCapturing = false;
  Offset? _remoteGesturePoint;

  // UI Interactive State
  int _currentTabIndex = 0;
  double _sliderValue = 65.0;
  bool _switchValue = true;
  bool _showCustomPopup = false;

  // Drawing Canvas State
  final List<Offset?> _drawnPoints = [];

  @override
  void initState() {
    super.initState();
    _initServer();
  }

  Future<void> _initServer() async {
    _server.onClientCountChanged = (count) {
      if (mounted) setState(() => _clientCount = count);
    };

    _server.onGestureReceived = (gesture) {
      if (mounted) {
        if (gesture.action == 'down' || gesture.action == 'move') {
          final size = MediaQuery.of(context).size;
          setState(() {
            _remoteGesturePoint = Offset(
              gesture.normalizedX * size.width,
              gesture.normalizedY * size.height,
            );
          });
        } else {
          setState(() => _remoteGesturePoint = null);
        }
      }
    };

    bool success = await _server.startServer(port: 8080);
    if (mounted) {
      if (success) {
        setState(() => _status = "${_server.serverIp}:8080");
        _startScreenCapture();
      } else {
        setState(() => _status = "Failed to start server");
      }
    }
  }

  // Ultra Low-Latency Lock-Free Frame Capture Loop
  void _startScreenCapture() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) async {
      if (_clientCount == 0 || _isCapturing) return;
      _isCapturing = true;

      try {
        final boundary =
            _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary != null) {
          // pixelRatio: 0.65 reduces encoding time from ~80ms to ~6ms and payload from 1.5MB to 40KB
          final image = await boundary.toImage(pixelRatio: 0.65);
          final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

          if (byteData != null) {
            final base64Str = base64Encode(byteData.buffer.asUint8List());
            final packet = FramePacket(
              base64: base64Str,
              width: image.width,
              height: image.height,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
            _server.broadcast(jsonEncode(packet.toJson()));
          }
        }
      } catch (e) {
        debugPrint("Error capturing frame: $e");
      } finally {
        _isCapturing = false;
      }
    });
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _server.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cast_connected_rounded, color: Colors.tealAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Host Broadcaster',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    'Real-Time Low Latency Stream',
                    style: TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _clientCount > 0
                        ? Colors.teal.withValues(alpha: 0.2)
                        : Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _clientCount > 0 ? Colors.teal : Colors.redAccent,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 4,
                        backgroundColor:
                            _clientCount > 0 ? Colors.tealAccent : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _clientCount > 0 ? "$_clientCount Live" : "Offline",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _clientCount > 0 ? Colors.tealAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
        body: Stack(
          children: [
            IndexedStack(
              index: _currentTabIndex,
              children: [
                // Tab 0: Broadcaster Dashboard
                SafeArea(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildServerInfoCard(),
                        const SizedBox(height: 16),
                        _buildInteractiveControls(),
                        const SizedBox(height: 16),
                        _buildDrawingArea(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // Tab 1: Museum Map View
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: MuseumMapView(
                      pois: MuseumPoi.samplePois,
                    ),
                  ),
                ),
              ],
            ),

            // In-Screen Popup Overlay
            if (_showCustomPopup)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.all(32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Color(0xFF334155), width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_circle_outline, color: Colors.tealAccent, size: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Mirrored Popup Card",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "This interactive popup is rendered within the host RepaintBoundary and streams directly to connected receivers in real-time.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => setState(() => _showCustomPopup = false),
                          child: const Text("Dismiss Popup", style: TextStyle(fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                ),
              ),

            // Remote Touch Pointer (Client Touch Pointer)
            if (_remoteGesturePoint != null)
              Positioned(
                left: _remoteGesturePoint!.dx - 18,
                top: _remoteGesturePoint!.dy - 18,
                child: IgnorePointer(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 8, spreadRadius: 2)
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.touch_app, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
          ),
          child: NavigationBar(
            selectedIndex: _currentTabIndex,
            onDestinationSelected: (index) {
              setState(() => _currentTabIndex = index);
            },
            backgroundColor: const Color(0xFF1E293B),
            indicatorColor: Colors.teal.withValues(alpha: 0.3),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined, color: Colors.white60),
                selectedIcon: Icon(Icons.dashboard_rounded, color: Colors.tealAccent),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined, color: Colors.white60),
                selectedIcon: Icon(Icons.map_rounded, color: Colors.tealAccent),
                label: 'Museum Map',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded, size: 32, color: Colors.tealAccent),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("BROADCAST ADDRESS", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _server.serverIp));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IP Address copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white60),
                        tooltip: 'Copy IP',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.white38),
                SizedBox(width: 6),
                Text(
                  "Enter this IP address into the Receiver Client App",
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveControls() {
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
              Icon(Icons.touch_app_rounded, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "Interactive Elements",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),

          // Slider
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white60, size: 20),
              Expanded(
                child: Slider(
                  value: _sliderValue,
                  min: 0,
                  max: 100,
                  activeColor: Colors.teal,
                  inactiveColor: const Color(0xFF0F172A),
                  onChanged: (val) => setState(() => _sliderValue = val),
                ),
              ),
              Text(
                "${_sliderValue.toInt()}%",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.tealAccent),
              ),
            ],
          ),

          // Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Enable Remote Stream", style: TextStyle(fontSize: 14, color: Colors.white)),
              Switch(
                value: _switchValue,
                activeThumbColor: Colors.tealAccent,
                activeTrackColor: Colors.teal.withValues(alpha: 0.5),
                onChanged: (val) => setState(() => _switchValue = val),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => _showCustomPopup = true),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text("Show Popup"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.tealAccent,
                    side: const BorderSide(color: Colors.teal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Snackbars are mirrored in real-time!"),
                        backgroundColor: Color(0xFF334155),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active_outlined, size: 16),
                  label: const Text("Snackbar"),
                ),
              ),
            ],
          )
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
                  Icon(Icons.gesture_rounded, color: Colors.tealAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Live Drawing Pad",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => setState(() => _drawnPoints.clear()),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                label: const Text("Clear", style: TextStyle(color: Colors.redAccent)),
              )
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 16),
          const SizedBox(height: 8),
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border.all(color: const Color(0xFF334155)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() => _drawnPoints.add(details.localPosition));
                },
                onPanUpdate: (details) {
                  setState(() => _drawnPoints.add(details.localPosition));
                },
                onPanEnd: (details) {
                  setState(() => _drawnPoints.add(null));
                },
                child: CustomPaint(
                  painter: DrawingPainter(_drawnPoints),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              "Draw above to test ultra-low latency stroke rendering.",
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          )
        ],
      ),
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = Colors.tealAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) => true;
}