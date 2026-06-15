// lib/models/occupancy_grid.dart
// nav_msgs/msg/OccupancyGrid 에 대응
//
// 주의: rosbridge는 int8[]/uint8[] 배열 필드를 JSON 배열이 아닌
// base64 인코딩된 문자열로 보내는 경우가 많음. 두 경우 모두 처리.

import 'dart:convert';

class OccupancyGridMsg {
  final int width;
  final int height;
  final double resolution; // [m/cell]
  final double originX;    // map frame 기준 origin [m]
  final double originY;
  final List<int> data;    // -1: unknown, 0: free, 100: occupied

  const OccupancyGridMsg({
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
    required this.data,
  });

  factory OccupancyGridMsg.fromRosMsg(Map<String, dynamic> msg) {
    final info = msg['info'] as Map<String, dynamic>? ?? {};
    final origin = info['origin'] as Map<String, dynamic>? ?? {};
    final position = origin['position'] as Map<String, dynamic>? ?? {};

    final rawData = msg['data'];
    List<int> data;

    if (rawData is String) {
      // rosbridge가 int8[]/uint8[]를 base64 문자열로 인코딩한 경우
      final bytes = base64.decode(rawData);
      // uint8(0~255) -> int8(-128~127) 변환
      data = bytes.map((b) => b > 127 ? b - 256 : b).toList();
    } else if (rawData is List) {
      data = rawData.map((e) => (e as num).toInt()).toList();
    } else {
      data = const [];
    }

    return OccupancyGridMsg(
      width: (info['width'] as num?)?.toInt() ?? 0,
      height: (info['height'] as num?)?.toInt() ?? 0,
      resolution: (info['resolution'] as num?)?.toDouble() ?? 0.05,
      originX: (position['x'] as num?)?.toDouble() ?? 0.0,
      originY: (position['y'] as num?)?.toDouble() ?? 0.0,
      data: data,
    );
  }
}
