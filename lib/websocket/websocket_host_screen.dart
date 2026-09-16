import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../shared/museum_map_view.dart';
import '../shared/museum_poi.dart';
import 'websocket_protocol.dart';
import 'websocket_service.dart';

class WebSocketHostScreen extends StatefulWidget {
  const WebSocketHostScreen({super.key});

  @override
  State<WebSocketHostScreen> createState() => _WebSocketHostScreenState();
}

class _WebSocketHostScreenState extends State<WebSocketHostScreen> {
  final WebSocketServerService _server = WebSocketServerService();
  final GlobalKey _boundaryKey = GlobalKey();

  // WebSocket Server State
  String _status = "Starting server...";
  int _clientCount = 0;
  Timer? _frameTimer;
  bool _isCapturing = false;
  Offset? _remoteGesturePoint;

  // UI Interactive State
  int _currentTabIndex = 0;
  double _sliderValue = 65.0;
  bool _switchValue = true;

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
      _handleGesture(gesture);
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

  void _handleGesture(WebSocketGesturePacket gesture) {
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
  }

  void _startScreenCapture() {
    _frameTimer?.cancel();
    _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _captureAndSendFrame();
    });
  }

  Future<void> _captureAndSendFrame() async {
    if (_isCapturing || _clientCount == 0) return;
    _isCapturing = true;

    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _isCapturing = false;
        return;
      }

      // High quality HD screen capture (pixelRatio: 0.65)
      final image = await boundary.toImage(pixelRatio: 0.65);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final buffer = byteData.buffer.asUint8List();
        _server.broadcast(buffer);
      }
    } catch (e) {
      debugPrint("Capture frame error: $e");
    } finally {
      _isCapturing = false;
    }
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
          backgroundColor: const Color(0xFF1E293B),
          elevation: 0,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: Colors.tealAccent, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WEBSOCKET HOST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                  Text('Local Wi-Fi Streaming', style: TextStyle(fontSize: 10, color: Colors.tealAccent)),
                ],
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            Container(
              color: const Color(0xFF0F172A),
              child: _currentTabIndex == 0 ? _buildInteractiveDashboard() : MuseumMapView(pois: MuseumPoi.samplePois),
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
                    color: Colors.tealAccent.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.tealAccent, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.tealAccent, blurRadius: 10, spreadRadius: 1)
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.touch_app, color: Colors.white, size: 24),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (index) => setState(() => _currentTabIndex = index),
          backgroundColor: const Color(0xFF1E293B),
          selectedItemColor: Colors.tealAccent,
          unselectedItemColor: Colors.white54,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Interactive UI',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_rounded),
              label: 'Museum Map',
            ),
          ],
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
          _buildServerStatusCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildPoiGrid(),
          const SizedBox(height: 16),
          _buildDrawingArea(),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
                  const Text("LOCAL WI-FI ADDRESS (WEBSOCKET)", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.tealAccent),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.devices_rounded, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  "Connected WebSocket Clients: $_clientCount",
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
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
              Icon(Icons.tune_rounded, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "Interactive UI Controls",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Host Feature Toggle:", style: TextStyle(color: Colors.white70, fontSize: 14)),
              Switch(
                value: _switchValue,
                activeThumbColor: Colors.tealAccent,
                onChanged: (val) => setState(() => _switchValue = val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Sync Level: ${_sliderValue.toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Slider(
                value: _sliderValue,
                min: 0,
                max: 100,
                activeColor: Colors.tealAccent,
                inactiveColor: const Color(0xFF334155),
                onChanged: (val) => setState(() => _sliderValue = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPoiGrid() {
    final pois = MuseumPoi.samplePois;
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
              Icon(Icons.museum_rounded, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                "Museum Highlights",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: pois.length,
            itemBuilder: (context, index) {
              final poi = pois[index];
              return InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected ${poi.name}'),
                      backgroundColor: Colors.teal,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Icon(poi.icon, color: Colors.tealAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          poi.name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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
                  painter: _DrawingPainter(_drawnPoints),
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

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  _DrawingPainter(this.points);

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
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}
