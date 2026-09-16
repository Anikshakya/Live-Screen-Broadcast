import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/mirror_protocol.dart';

class IPHelper {
  static Future<String> getLocalIPAddress() async {
    if (kIsWeb) return '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        final isWifiOrEth = interface.name.toLowerCase().contains('wlan') ||
            interface.name.toLowerCase().contains('wifi') ||
            interface.name.toLowerCase().contains('eth') ||
            interface.name.toLowerCase().contains('en');

        if (isWifiOrEth) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
      }

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }
}

class WebSocketServerService {
  HttpServer? _server;
  final List<WebSocket> _connectedClients = [];
  int _port = 8080;
  String _serverIp = '0.0.0.0';
  bool _isHosting = false;

  Function(int clientCount)? onClientCountChanged;
  Function(GesturePacket gesture)? onGestureReceived;
  Function(String log)? onLog;

  bool get isHosting => _isHosting;
  String get serverIp => _serverIp;
  int get port => _port;
  int get clientCount => _connectedClients.length;

  Future<bool> startServer({int port = 8080}) async {
    if (kIsWeb) {
      _log('Hosting server is not supported directly in web browser target.');
      return false;
    }
    _port = port;
    try {
      _serverIp = await IPHelper.getLocalIPAddress();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isHosting = true;
      _log('Server started on ws://$_serverIp:$_port');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final clientIp = request.connectionInfo?.remoteAddress.address ?? 'Client';
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClientConnection(socket, clientIp);
        } else {
          // Serve built-in HTML5 Web Viewer to normal web browsers
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_getWebViewerHtml())
            ..close();
        }
      });
      return true;
    } catch (e) {
      _log('Failed to start server: $e');
      _isHosting = false;
      return false;
    }
  }

  void _handleClientConnection(WebSocket socket, String clientIp) {
    _connectedClients.add(socket);
    onClientCountChanged?.call(_connectedClients.length);

    socket.listen(
      (data) {
        if (data is String) _handleIncomingMessage(data);
      },
      onDone: () {
        _connectedClients.remove(socket);
        onClientCountChanged?.call(_connectedClients.length);
      },
      onError: (_) {
        _connectedClients.remove(socket);
        onClientCountChanged?.call(_connectedClients.length);
      },
    );
  }

  void _handleIncomingMessage(String messageStr) {
    try {
      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      if (json['type'] == 'gesture') {
        onGestureReceived?.call(GesturePacket.fromJson(json));
      }
    } catch (_) {}
  }

  void broadcast(dynamic payload) {
    if (_connectedClients.isEmpty) return;
    final deadSockets = <WebSocket>[];
    for (final socket in _connectedClients) {
      try {
        socket.add(payload);
      } catch (_) {
        deadSockets.add(socket);
      }
    }
    for (final dead in deadSockets) {
      _connectedClients.remove(dead);
      onClientCountChanged?.call(_connectedClients.length);
    }
  }

  Future<void> stopServer() async {
    for (final socket in _connectedClients) {
      try {
        await socket.close();
      } catch (_) {}
    }
    _connectedClients.clear();
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _isHosting = false;
  }

  void _log(String msg) => onLog?.call(msg);

  String _getWebViewerHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Live Screen Mirror</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background-color: #0F172A; color: #F8FAFC;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex; flex-direction: column;
      height: 100vh; overflow: hidden;
    }
    header {
      background: #1E293B; padding: 12px 20px;
      display: flex; align-items: center; justify-content: space-between;
      border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    .badge {
      background: rgba(16, 185, 129, 0.2); color: #10B981;
      padding: 4px 10px; border-radius: 20px;
      font-weight: bold; font-size: 12px;
      border: 1px solid rgba(16, 185, 129, 0.4);
    }
    .container {
      flex: 1; position: relative; display: flex;
      align-items: center; justify-content: center; background: #000;
    }
    #screen-img {
      max-width: 100%; max-height: 100%; object-fit: contain;
      user-select: none; -webkit-user-drag: none;
    }
    #gesture-canvas {
      position: absolute; top: 0; left: 0;
      width: 100%; height: 100%; touch-action: none;
    }
    .stats {
      position: absolute; top: 16px; left: 16px;
      background: rgba(0, 0, 0, 0.85); padding: 10px 14px;
      border-radius: 10px; font-size: 12px;
      border: 1px solid rgba(6, 182, 212, 0.4); color: #06B6D4;
      pointer-events: none;
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h3 style="font-size: 16px; color: #14B8A6;">Web Viewer</h3>
    </div>
    <div id="status-badge" class="badge">CONNECTING...</div>
  </header>
  <div class="container" id="viewer-container">
    <img id="screen-img" alt="Screen Stream" />
    <canvas id="gesture-canvas"></canvas>
    <div class="stats" id="stats-panel">FPS: 0 | Latency: 0ms</div>
  </div>

  <script>
    const wsUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host;
    const imgEl = document.getElementById('screen-img');
    const canvas = document.getElementById('gesture-canvas');
    const badge = document.getElementById('status-badge');
    const statsEl = document.getElementById('stats-panel');

    let ws = new WebSocket(wsUrl);
    let lastFrameTime = performance.now();
    let frameCount = 0;

    function resizeCanvas() {
      canvas.width = canvas.clientWidth;
      canvas.height = canvas.clientHeight;
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    ws.onopen = () => {
      badge.textContent = 'LIVE';
      badge.style.background = 'rgba(16, 185, 129, 0.2)';
      badge.style.color = '#10B981';
    };

    ws.onclose = () => {
      badge.textContent = 'DISCONNECTED';
      badge.style.background = 'rgba(244, 63, 94, 0.2)';
      badge.style.color = '#F43F5E';
    };

    ws.onmessage = (event) => {
      try {
        if (typeof event.data === 'string') {
          const data = JSON.parse(event.data);
          if (data.type === 'frame') {
            imgEl.src = 'data:image/png;base64,' + data.base64;
            frameCount++;
            const now = performance.now();
            if (now - lastFrameTime >= 1000) {
              const latency = Date.now() - (data.timestamp || Date.now());
              statsEl.textContent = `FPS: \${frameCount} | Latency: \${Math.max(0, latency)}ms`;
              frameCount = 0;
              lastFrameTime = now;
            }
          }
        }
      } catch (e) {}
    };

    function sendGesture(action, event) {
      if (ws.readyState !== WebSocket.OPEN) return;
      
      const rect = imgEl.getBoundingClientRect();
      const x = event.clientX || (event.touches && event.touches[0].clientX);
      const y = event.clientY || (event.touches && event.touches[0].clientY);
      
      if(x !== undefined && y !== undefined) {
        const normX = (x - rect.left) / rect.width;
        const normY = (y - rect.top) / rect.height;
        
        ws.send(JSON.stringify({
          type: 'gesture',
          action: action,
          pointerId: 1,
          normalizedX: normX,
          normalizedY: normY
        }));
      }
    }

    canvas.addEventListener('mousedown', (e) => sendGesture('down', e));
    canvas.addEventListener('mousemove', (e) => { if(e.buttons > 0) sendGesture('move', e); });
    canvas.addEventListener('mouseup', (e) => sendGesture('up', e));
    
    canvas.addEventListener('touchstart', (e) => sendGesture('down', e), {passive: false});
    canvas.addEventListener('touchmove', (e) => sendGesture('move', e), {passive: false});
    canvas.addEventListener('touchend', (e) => sendGesture('up', e));
  </script>
</body>
</html>
''';
  }
}

class WebSocketClientService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  Function(FramePacket frame)? onFrameReceived;
  Function(Uint8List rawBytes)? onRawFrameReceived;
  Function(GesturePacket gesture)? onGestureReceived;
  Function(bool connected, String status)? onStatusChanged;

  bool get isConnected => _isConnected;

  Future<bool> connect(String ipAddress, {int port = 8080}) async {
    await disconnect();

    try {
      final wsUri = Uri.parse('ws://$ipAddress:$port');
      _channel = WebSocketChannel.connect(wsUri);

      _subscription = _channel!.stream.listen(
        (data) {
          if (!_isConnected) {
            _isConnected = true;
            onStatusChanged?.call(true, 'Connected!');
          }
          if (data is String) {
            _parseIncomingMessage(data);
          } else if (data is List<int>) {
            onRawFrameReceived?.call(Uint8List.fromList(data));
          }
        },
        onDone: () {
          _handleDisconnected('Disconnected');
        },
        onError: (err) {
          _handleDisconnected('Error: $err');
        },
      );

      _isConnected = true;
      onStatusChanged?.call(true, 'Connected!');
      return true;
    } catch (e) {
      _handleDisconnected('Failed: $e');
      return false;
    }
  }

  void _handleDisconnected(String status) {
    if (_isConnected || _channel != null || _subscription != null) {
      _isConnected = false;
      _cleanup();
      onStatusChanged?.call(false, status);
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _cleanup();
    onStatusChanged?.call(false, 'Disconnected');
  }

  void _cleanup() {
    try {
      _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _parseIncomingMessage(String messageStr) {
    try {
      final jsonMap = jsonDecode(messageStr) as Map<String, dynamic>;
      if (jsonMap['type'] == 'frame') {
        onFrameReceived?.call(FramePacket.fromBase64Json(jsonMap));
      } else if (jsonMap['type'] == 'gesture') {
        onGestureReceived?.call(GesturePacket.fromJson(jsonMap));
      }
    } catch (_) {}
  }

  void sendGesture(GesturePacket gesture) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(gesture.toJson()));
      } catch (_) {}
    }
  }
}