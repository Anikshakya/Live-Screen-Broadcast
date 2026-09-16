class WebSocketFramePacket {
  final String type = 'frame';
  final String base64;
  final int width;
  final int height;
  final int timestamp;

  WebSocketFramePacket({
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

  factory WebSocketFramePacket.fromBase64Json(Map<String, dynamic> json) {
    return WebSocketFramePacket(
      base64: json['base64'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class WebSocketGesturePacket {
  final String type = 'gesture';
  final String action; // 'down', 'move', 'up', 'cancel'
  final int pointerId;
  final double normalizedX;
  final double normalizedY;

  WebSocketGesturePacket({
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

  factory WebSocketGesturePacket.fromJson(Map<String, dynamic> json) {
    return WebSocketGesturePacket(
      action: json['action'] ?? 'unknown',
      pointerId: json['pointerId'] ?? 0,
      normalizedX: (json['normalizedX'] ?? 0).toDouble(),
      normalizedY: (json['normalizedY'] ?? 0).toDouble(),
    );
  }
}
