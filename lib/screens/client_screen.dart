import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mirror/network/websocket_service.dart';

import '../models/mirror_protocol.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen> {
  final WebSocketClientService _client = WebSocketClientService();
  final TextEditingController _ipController = TextEditingController(text: "192.168.1.");
  final GlobalKey _imageKey = GlobalKey();

  String _status = "Disconnected";
  bool _isConnected = false;
  Uint8List? _latestImageBytes;
  Offset? _localTouchPoint;

  @override
  void initState() {
    super.initState();
    _client.onStatusChanged = (connected, status) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _status = status;
          if (!connected) {
            _latestImageBytes = null;
          }
        });
      }
    };

    _client.onFrameReceived = (frame) {
      if (mounted && _isConnected) {
        try {
          final bytes = base64Decode(frame.base64);
          setState(() => _latestImageBytes = bytes);
        } catch (_) {}
      }
    };

    _client.onRawFrameReceived = (rawBytes) {
      if (mounted && _isConnected) {
        setState(() => _latestImageBytes = rawBytes);
      }
    };
  }

  void _toggleConnection() {
    FocusScope.of(context).unfocus();
    if (_isConnected) {
      _client.disconnect();
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
        _client.connect(ip, port: 8080);
      }
    }
  }

  void _sendGesture(PointerEvent event, String action) {
    if (!_client.isConnected) return;

    // Immediate visual touch feedback on Client Screen
    if (action == 'down' || action == 'move') {
      setState(() => _localTouchPoint = event.localPosition);
    } else {
      setState(() => _localTouchPoint = null);
    }

    // Compute normalized coordinates relative to rendered screen image
    final RenderBox? renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final size = renderBox.size;
      if (size.width > 0 && size.height > 0) {
        final gesture = GesturePacket(
          action: action,
          pointerId: event.pointer,
          normalizedX: (event.localPosition.dx / size.width).clamp(0.0, 1.0),
          normalizedY: (event.localPosition.dy / size.height).clamp(0.0, 1.0),
        );
        _client.sendGesture(gesture);
      }
    }
  }

  @override
  void dispose() {
    _client.disconnect();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
              child: const Icon(Icons.important_devices_rounded, color: Colors.tealAccent, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Client Receiver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                Text('Remote Touch Controller', style: TextStyle(fontSize: 10, color: Colors.white54)),
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
                  color: _isConnected ? Colors.teal.withValues(alpha: 0.2) : Colors.redAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isConnected ? Colors.teal : Colors.redAccent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 4,
                      backgroundColor: _isConnected ? Colors.tealAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected ? "LIVE" : "OFFLINE",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isConnected ? Colors.tealAccent : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildConnectionCard(),
            Expanded(child: _buildViewerArea()),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  enabled: !_isConnected,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'Host IP Address',
                    labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: const Icon(Icons.router_rounded, color: Colors.tealAccent, size: 20),
                    suffixText: ':8080',
                    suffixStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.teal),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _toggleConnection,
                  icon: Icon(_isConnected ? Icons.power_settings_new_rounded : Icons.cast_connected_rounded, size: 18),
                  label: Text(_isConnected ? 'Disconnect' : 'Connect', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? const Color(0xFFEF4444) : Colors.teal,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                _isConnected ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 14,
                color: _isConnected ? Colors.tealAccent : Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: _isConnected ? FontWeight.bold : FontWeight.normal,
                    color: _isConnected ? Colors.tealAccent : Colors.white60,
                  ),
                ),
              ),
              if (!_isConnected) ...[
                const Text('Quick:', style: TextStyle(fontSize: 11, color: Colors.white38)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _ipController.text = "127.0.0.1"),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: const Text('localhost', style: TextStyle(fontSize: 10, color: Colors.tealAccent)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewerArea() {
    if (!_isConnected || _latestImageBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Icon(
                  _isConnected ? Icons.sync_rounded : Icons.phonelink_off_rounded,
                  size: 56,
                  color: _isConnected ? Colors.tealAccent : Colors.white38,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isConnected ? "Connected! Waiting for host stream..." : "Disconnected from Host",
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected
                    ? "Sub-50ms screen frames will appear as soon as host broadcasts."
                    : "Enter the IP displayed on the Host Screen and tap Connect.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 2)
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Listener(
              key: _imageKey,
              onPointerDown: (e) => _sendGesture(e, 'down'),
              onPointerMove: (e) => _sendGesture(e, 'move'),
              onPointerUp: (e) => _sendGesture(e, 'up'),
              onPointerCancel: (e) => _sendGesture(e, 'cancel'),
              child: Image.memory(
                _latestImageBytes!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

            // Local Feedback Ripple for Client Touches
            if (_localTouchPoint != null)
              Positioned(
                left: _localTouchPoint!.dx - 18,
                top: _localTouchPoint!.dy - 18,
                child: IgnorePointer(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.tealAccent.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.tealAccent, width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.touch_app, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}