import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'websocket_protocol.dart';
import 'websocket_service.dart';

class WebSocketClientScreen extends StatefulWidget {
  const WebSocketClientScreen({super.key});

  @override
  State<WebSocketClientScreen> createState() => _WebSocketClientScreenState();
}

class _WebSocketClientScreenState extends State<WebSocketClientScreen> {
  final TextEditingController _ipController = TextEditingController();
  final WebSocketClientService _webSocketClient = WebSocketClientService();

  bool _isConnected = false;
  String _status = "Disconnected";
  Uint8List? _latestImageBytes;
  Offset? _localTouchPoint;

  @override
  void initState() {
    super.initState();
    _setupWebSocketListeners();
  }

  void _setupWebSocketListeners() {
    _webSocketClient.onStatusChanged = (connected, statusMsg) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _status = statusMsg;
          if (!connected) {
            _latestImageBytes = null;
          }
        });
      }
    };

    _webSocketClient.onRawFrameReceived = (imageBytes) {
      if (mounted) {
        setState(() {
          _latestImageBytes = imageBytes;
        });
      }
    };
  }

  @override
  void dispose() {
    _webSocketClient.onStatusChanged = null;
    _webSocketClient.onRawFrameReceived = null;
    _webSocketClient.disconnect();
    _ipController.dispose();
    super.dispose();
  }

  void _toggleWebSocketConnection() {
    FocusScope.of(context).unfocus();

    if (_isConnected) {
      _webSocketClient.disconnect();
      setState(() {
        _isConnected = false;
        _status = "Disconnected";
        _latestImageBytes = null;
        _localTouchPoint = null;
      });
    } else {
      final ip = _ipController.text.trim();
      if (ip.isNotEmpty) {
        setState(() => _status = "Connecting to ws://$ip:8080...");
        _webSocketClient.connect(ip, port: 8080);
      }
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (!_isConnected) return;

    final normalizedX = details.localPosition.dx / constraints.maxWidth;
    final normalizedY = details.localPosition.dy / constraints.maxHeight;

    setState(() {
      _localTouchPoint = details.localPosition;
    });

    final gesture = WebSocketGesturePacket(
      action: 'down',
      pointerId: 1,
      normalizedX: normalizedX,
      normalizedY: normalizedY,
    );

    _webSocketClient.sendGesture(gesture);

    Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        final upGesture = WebSocketGesturePacket(
          action: 'up',
          pointerId: 1,
          normalizedX: normalizedX,
          normalizedY: normalizedY,
        );
        _webSocketClient.sendGesture(upGesture);
        setState(() => _localTouchPoint = null);
      }
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
                color: Colors.teal,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.devices_rounded, color: Colors.tealAccent, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WEBSOCKET CLIENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Text('Ultra-Low Latency LAN Stream', style: TextStyle(fontSize: 10, color: Colors.tealAccent)),
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
                    color: _isConnected ? Colors.tealAccent : const Color(0xFF334155),
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
                                      _isConnected ? Icons.sync_rounded : Icons.cast_connected_rounded,
                                      size: 56,
                                      color: _isConnected ? Colors.tealAccent : Colors.white24,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isConnected
                                          ? "Waiting for host screen frames..."
                                          : "Connect to Host IP Address to view stream.",
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
                                    color: Colors.tealAccent.withValues(alpha: 0.5),
                                    border: Border.all(color: Colors.tealAccent, width: 2),
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
                  controller: _ipController,
                  enabled: !_isConnected,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'WebSocket Host IP Address',
                    labelStyle: const TextStyle(color: Colors.tealAccent),
                    hintText: 'e.g. 192.168.1.15',
                    hintStyle: const TextStyle(color: Colors.white24),
                    prefixIcon: const Icon(Icons.wifi_rounded, color: Colors.tealAccent, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _toggleWebSocketConnection,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isConnected ? Colors.redAccent : Colors.teal,
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
                  color: _isConnected ? Colors.greenAccent : Colors.tealAccent,
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
