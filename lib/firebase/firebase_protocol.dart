class FirebaseFramePacket {
  final String base64;
  final int width;
  final int height;
  final int timestamp;

  FirebaseFramePacket({
    required this.base64,
    required this.width,
    required this.height,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'base64': base64,
        'width': width,
        'height': height,
        'timestamp': timestamp,
      };

  factory FirebaseFramePacket.fromJson(Map<String, dynamic> json) {
    return FirebaseFramePacket(
      base64: json['base64'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class FirebaseGesturePacket {
  final String action; // 'down', 'move', 'up'
  final double normalizedX;
  final double normalizedY;
  final int timestamp;

  FirebaseGesturePacket({
    required this.action,
    required this.normalizedX,
    required this.normalizedY,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'normalizedX': normalizedX,
        'normalizedY': normalizedY,
        'timestamp': timestamp,
      };

  factory FirebaseGesturePacket.fromJson(Map<String, dynamic> json) {
    return FirebaseGesturePacket(
      action: json['action'] ?? 'down',
      normalizedX: (json['normalizedX'] ?? 0).toDouble(),
      normalizedY: (json['normalizedY'] ?? 0).toDouble(),
      timestamp: json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
