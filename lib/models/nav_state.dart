// lib/models/nav_state.dart
// autorccar_interfaces/NavState 에 대응

class Vec3 {
  final double x, y, z;
  const Vec3({this.x = 0, this.y = 0, this.z = 0});

  factory Vec3.fromMap(Map<String, dynamic> m) => Vec3(
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        z: (m['z'] as num?)?.toDouble() ?? 0,
      );
}

class Quaternion {
  final double x, y, z, w;
  const Quaternion({this.x = 0, this.y = 0, this.z = 0, this.w = 1});

  factory Quaternion.fromMap(Map<String, dynamic> m) => Quaternion(
        x: (m['x'] as num?)?.toDouble() ?? 0,
        y: (m['y'] as num?)?.toDouble() ?? 0,
        z: (m['z'] as num?)?.toDouble() ?? 0,
        w: (m['w'] as num?)?.toDouble() ?? 1,
      );
}

class NavState {
  final Vec3 position;   // ENU [m]
  final Vec3 velocity;   // ENU [m/s]
  final Quaternion quaternion; // w,x,y,z

  const NavState({
    required this.position,
    required this.velocity,
    required this.quaternion,
  });

  factory NavState.fromRosMsg(Map<String, dynamic> msg) {
    return NavState(
      position: Vec3.fromMap(msg['position'] ?? {}),
      velocity: Vec3.fromMap(msg['velocity'] ?? {}),
      quaternion: Quaternion.fromMap(msg['quaternion'] ?? {}),
    );
  }
}
