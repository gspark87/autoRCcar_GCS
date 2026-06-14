// lib/ros2/gcs_controller.dart

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/nav_state.dart';
import '../models/path_point.dart';
import '../models/control_command.dart';
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
 
  // ── Control Command ────────────────────────────────
  ControlCommand controlCommand = const ControlCommand();

  // ── PWM Command ────────────────────────────────────
  ControlCommand pwmCommand = const ControlCommand(); // ← 추가

  // ── 지도 원점 (LLH rad) ─────────────────────────────────
  // nav_topic의 origin (ECEF) 첫 수신 시 자동 설정
  List<double>? _originLLH;
  bool get hasOrigin => _originLLH != null;

  // origin의 위경도 (표시용)
  double? originLatDeg;
  double? originLonDeg;

  Function(LatLng)? onOriginSet;

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
    _ros.onControlCommand = _onControlCommand;
    _ros.onPwmCommand = _onPwmCommand;
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

    // Euler 변환 (w,x,y,z 순서)
    final euler = quat2euler([
      msg.quaternion.w,
      msg.quaternion.x,
      msg.quaternion.y,
      msg.quaternion.z,
    ]);
    rollDeg = rad2deg(euler[0]);
    pitchDeg = rad2deg(euler[1]);
    yawDeg = rad2deg(euler[2]);

    // ── Origin 자동 설정 ──────────────────────────────────
    // nav_topic의 origin (ECEF XYZ) → LLH 변환
    // ECEF가 (0,0,0)이 아닌 경우에만 유효한 값으로 판단
    final ecef = [msg.origin.x, msg.origin.y, msg.origin.z];
    final ecefNorm = ecef[0] * ecef[0] + ecef[1] * ecef[1] + ecef[2] * ecef[2];

    if (_originLLH == null && ecefNorm > 1e6) {
      // ECEF → LLH 변환
      final llh = xyz2llh(ecef);
      _originLLH = llh;
      originLatDeg = rad2deg(llh[0]);
      originLonDeg = rad2deg(llh[1]);
      onOriginSet?.call(LatLng(originLatDeg!, originLonDeg!));
    }

    // ── 차량 위치 업데이트 ────────────────────────────────
    if (_originLLH != null) {
      final enu = [msg.position.x, msg.position.y, msg.position.z];
      final llh = enu2llh(enu, _originLLH!);
      vehiclePosition = LatLng(rad2deg(llh[0]), rad2deg(llh[1]));
      trajectory.add(vehiclePosition!);
      // if (trajectory.length > 2000) trajectory.removeAt(0); 
    }

    notifyListeners();
  }

  void _onPwmCommand(ControlCommand cmd) {
    pwmCommand = cmd;
    notifyListeners();
  }

  void _onControlCommand(ControlCommand cmd) {
    controlCommand = cmd;
    notifyListeners();
  }

  void _onTeleopMode(bool teleop) {
    isTeleop = teleop;
    notifyListeners();
  }

  void sendTeleopCommand(int cmd) => _ros.publishTeleopCommand(cmd);

  void sendSpeedReset() {
    teleopSpeed = 0.0;
    _ros.publishTeleopControlCommand(teleopSpeed, teleopSteer);
    notifyListeners();
  }

  void sendSteerReset() {
    teleopSteer = 0.0;
    _ros.publishTeleopControlCommand(teleopSpeed, deg2rad(teleopSteer));
    notifyListeners();
  }

  // ── 원점 수동 설정 (지도 클릭) ────────────────────────────
  void setOrigin(LatLng latLng, {double altitude = 0}) {
    _originLLH = [
      deg2rad(latLng.latitude),
      deg2rad(latLng.longitude),
      altitude,
    ];
    originLatDeg = latLng.latitude;
    originLonDeg = latLng.longitude;
    trajectory.clear();
    notifyListeners();
  }

  // ── Waypoint 관리 ─────────────────────────────────────────

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

  void removeWaypoint(int index) {
    if (index >= 0 && index < waypoints.length) {
      waypoints.removeAt(index);
      _updateSpline();
      notifyListeners();
    }
  }

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
    if (result == null) { splinePath.clear(); return; }

    splinePath = [];
    for (int i = 0; i < result.x.length; i++) {
      final llh = enu2llh([result.x[i], result.y[i], 0.0], _originLLH!);
      splinePath.add(LatLng(rad2deg(llh[0]), rad2deg(llh[1])));
    }
  }

  // ── Teleop 제어값 ─────────────────────────────────────
  double teleopSpeed = 0.0;
  double teleopSteer = 0.0;

  void teleopSpeedUp() {
    teleopSpeed += 0.1;
    _ros.publishTeleopControlCommand(teleopSpeed, teleopSteer);
    notifyListeners();
  }

  void teleopSpeedDown() {
    teleopSpeed -= 0.1;
    _ros.publishTeleopControlCommand(teleopSpeed, teleopSteer);
    notifyListeners();
  }

  void teleopSteerLeft() {
    teleopSteer += 1.0;
    _ros.publishTeleopControlCommand(teleopSpeed, deg2rad(teleopSteer));
    notifyListeners();
  }

  void teleopSteerRight() {
    teleopSteer -= 1.0;
    _ros.publishTeleopControlCommand(teleopSpeed, deg2rad(teleopSteer));
    notifyListeners();
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

  // ── Import / Export ───────────────────────────────────────

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

  String exportPathToText() {
    return waypoints.map((w) => '${w.x} ${w.y}').join('\n');
  }

  @override
  void dispose() {
    _ros.dispose();
    super.dispose();
  }
}
