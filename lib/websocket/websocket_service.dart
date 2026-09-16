import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_protocol.dart';

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
        final isWifiOrEth =
            interface.name.toLowerCase().contains('wlan') ||
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
  Function(WebSocketGesturePacket gesture)? onGestureReceived;
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
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClientConnection(socket);
        }
      });
      return true;
    } catch (e) {
      _log('Failed to start server: $e');
      _isHosting = false;
      return false;
    }
  }

  void _handleClientConnection(WebSocket socket) {
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
        onGestureReceived?.call(WebSocketGesturePacket.fromJson(json));
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
}

class WebSocketClientService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;

  Function(WebSocketFramePacket frame)? onFrameReceived;
  Function(Uint8List rawBytes)? onRawFrameReceived;
  Function(WebSocketGesturePacket gesture)? onGestureReceived;
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
        onFrameReceived?.call(WebSocketFramePacket.fromBase64Json(jsonMap));
      } else if (jsonMap['type'] == 'gesture') {
        onGestureReceived?.call(WebSocketGesturePacket.fromJson(jsonMap));
      }
    } catch (_) {}
  }

  void sendGesture(WebSocketGesturePacket gesture) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(gesture.toJson()));
      } catch (_) {}
    }
  }
}
