class FramePacket {
  final String type = 'frame';
  final String base64;
  final int width;
  final int height;
  final int timestamp;

  FramePacket({
    required this.base64,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'base64': base64,
        'width': width,
        'height': height,
        'timestamp': timestamp,
      };

  factory FramePacket.fromBase64Json(Map<String, dynamic> json) {
    return FramePacket(
      base64: json['base64'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class GesturePacket {
  final String type = 'gesture';
  final String action; // 'down', 'move', 'up', 'cancel'
  final int pointerId;
  final double normalizedX;
  final double normalizedY;

  GesturePacket({
    required this.action,
    required this.pointerId,
    required this.normalizedX,
    required this.normalizedY,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'action': action,
        'pointerId': pointerId,
        'normalizedX': normalizedX,
        'normalizedY': normalizedY,
      };

  factory GesturePacket.fromJson(Map<String, dynamic> json) {
    return GesturePacket(
      action: json['action'] ?? 'unknown',
      pointerId: json['pointerId'] ?? 0,
      normalizedX: (json['normalizedX'] ?? 0).toDouble(),
      normalizedY: (json['normalizedY'] ?? 0).toDouble(),
    );
  }
}

class SystemHandshakePacket {
  final String type = 'handshake';
  final String deviceName;

  SystemHandshakePacket({required this.deviceName});

  Map<String, dynamic> toJson() => {
        'type': type,
        'deviceName': deviceName,
      };

  factory SystemHandshakePacket.fromJson(Map<String, dynamic> json) {
    return SystemHandshakePacket(
      deviceName: json['deviceName'] ?? 'Unknown Device',
    );
  }
}