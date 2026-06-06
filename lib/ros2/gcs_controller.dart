// lib/ros2/gcs_controller.dart
// main.py GcsController 의 Dart 포팅
// ROS2 ↔ GUI 사이의 비즈니스 로직

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/nav_state.dart';
import '../models/path_point.dart';
import '../math/user_geometry.dart';
import '../math/cubic_spline.dart';
import 'rosbridge_service.dart';

class GcsController extends ChangeNotifier {
  final RosbridgeService _ros;

  // ── Nav 상태 ───────────────────────────────────────────
  NavState? navState;
  double rollDeg = 0, pitchDeg = 0, yawDeg = 0;

  // ── 모드 ────────────────────────────────────────────────
  bool isTeleop = false;

  // ── 지도 원점 (LLH rad) ─────────────────────────────────
  // 첫 nav_topic 수신 시 자동 설정, 또는 수동 설정
  List<double>? _originLLH;
  bool get hasOrigin => _originLLH != null;

  // ── 차량 위치 (지도) ─────────────────────────────────────
  LatLng? vehiclePosition;
  List<LatLng> trajectory = [];

  // ── Waypoints ───────────────────────────────────────────
  List<WaypointLLH> waypoints = [];

  // ── Spline 경로 ─────────────────────────────────────────
  List<LatLng> splinePath = [];

  // ── 연결 상태 ────────────────────────────────────────────
  ConnectionState get connectionState => _ros.state;

  GcsController({String host = 'localhost', int port = 9090})
      : _ros = RosbridgeService(host: host, port: port) {
    _ros.onNavState = _onNavState;
    _ros.onTeleopMode = _onTeleopMode;
    _ros.onConnectionChanged = (_) => notifyListeners();
  }

  // ── ROS 연결 ─────────────────────────────────────────────

  void connect(String host, int port) {
    _ros.updateAddress(host, port);
    _ros.connect();
  }

  void disconnect() => _ros.disconnect();

  // ── Nav 콜백 ─────────────────────────────────────────────

  void _onNavState(NavState msg) {
    navState = msg;

    // Euler 변환
    final euler = quat2euler([
      msg.quaternion.w,
      msg.quaternion.x,
      msg.quaternion.y,
      msg.quaternion.z,
    ]);
    rollDeg = rad2deg(euler[0]);
    pitchDeg = rad2deg(euler[1]);
    yawDeg = rad2deg(euler[2]);

    // 원점 자동 설정 (첫 수신 시)
    // 주의: nav_topic position은 ENU [m] 이므로
    // 원점 LLH가 없으면 지도 표시 불가 → 수동 설정 필요
    if (_originLLH != null) {
      final enu = [msg.position.x, msg.position.y, msg.position.z];
      final llh = enu2llh(enu, _originLLH!);
      vehiclePosition = LatLng(rad2deg(llh[0]), rad2deg(llh[1]));
      trajectory.add(vehiclePosition!);
      if (trajectory.length > 2000) trajectory.removeAt(0);
    }

    notifyListeners();
  }

  void _onTeleopMode(bool teleop) {
    isTeleop = teleop;
    notifyListeners();
  }

  // ── 원점 설정 ─────────────────────────────────────────────

  /// 지도에서 origin 수동 설정 (위경도 deg)
  void setOrigin(LatLng latLng, {double altitude = 0}) {
    _originLLH = [
      deg2rad(latLng.latitude),
      deg2rad(latLng.longitude),
      altitude,
    ];
    trajectory.clear();
    notifyListeners();
  }

  // ── Waypoint 관리 ─────────────────────────────────────────

  /// 지도 클릭 → Waypoint 추가
  void addWaypoint(LatLng latLng) {
    double ex = 0, ey = 0;
    if (_originLLH != null) {
      final llh = [deg2rad(latLng.latitude), deg2rad(latLng.longitude), 0.0];
      final enu = llh2enu(llh, _originLLH!);
      ex = enu[0];
      ey = enu[1];
    }
    waypoints.add(WaypointLLH(latLng: latLng, x: ex, y: ey));
    _updateSpline();
    notifyListeners();
  }

  /// Waypoint 삭제 (index)
  void removeWaypoint(int index) {
    if (index >= 0 && index < waypoints.length) {
      waypoints.removeAt(index);
      _updateSpline();
      notifyListeners();
    }
  }

  /// 전체 초기화
  void clearAll() {
    waypoints.clear();
    splinePath.clear();
    trajectory.clear();
    notifyListeners();
  }

  // ── Spline 계산 ───────────────────────────────────────────

  void _updateSpline() {
    if (waypoints.length < 2 || _originLLH == null) {
      splinePath.clear();
      return;
    }

    final xPts = waypoints.map((w) => w.x).toList();
    final yPts = waypoints.map((w) => w.y).toList();
    final result = calculateCubicSplinePath(xPts, yPts, ds: 0.5);

    if (result == null) {
      splinePath.clear();
      return;
    }

    splinePath = [];
    for (int i = 0; i < result.x.length; i++) {
      final llh = enu2llh([result.x[i], result.y[i], 0.0], _originLLH!);
      splinePath.add(LatLng(rad2deg(llh[0]), rad2deg(llh[1])));
    }
  }

  // ── ROS Publish ───────────────────────────────────────────

  void sendStart() => _ros.publishCommand(1);
  void sendStop() => _ros.publishCommand(0);

  void sendSetYaw(double yaw) => _ros.publishSetYaw(yaw);

  void sendGlobalPath() {
    if (waypoints.isEmpty) return;
    final pathList = waypoints.map((w) => [w.x, w.y]).toList();
    _ros.publishGlobalPath(pathList);
  }

  // ── Import / Export (ENU txt) ─────────────────────────────

  /// txt 파일 내용(문자열) 파싱 → waypoint 로드
  void importPathFromText(String content) {
    if (_originLLH == null) return;
    waypoints.clear();
    for (final line in content.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x != null && y != null) {
          final llh = enu2llh([x, y, 0.0], _originLLH!);
          waypoints.add(WaypointLLH(
            latLng: LatLng(rad2deg(llh[0]), rad2deg(llh[1])),
            x: x,
            y: y,
          ));
        }
      }
    }
    _updateSpline();
    notifyListeners();
  }

  /// waypoint → txt 형식 문자열 export
  String exportPathToText() {
    return waypoints.map((w) => '${w.x} ${w.y}').join('\n');
  }

  @override
  void dispose() {
    _ros.dispose();
    super.dispose();
  }
}
