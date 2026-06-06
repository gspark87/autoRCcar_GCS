// lib/models/path_point.dart

import 'package:latlong2/latlong.dart';

/// ENU 좌표 Waypoint (내부 계산용)
class WaypointENU {
  double x; // East [m]
  double y; // North [m]

  WaypointENU({required this.x, required this.y});
}

/// 지도 표시용 Waypoint (위경도)
class WaypointLLH {
  final LatLng latLng;
  final double x; // ENU East
  final double y; // ENU North

  const WaypointLLH({
    required this.latLng,
    required this.x,
    required this.y,
  });
}
