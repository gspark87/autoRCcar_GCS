import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/nav_state.dart';
import '../models/path_point.dart';
import '../models/control_command.dart';
import '../math/user_geometry.dart';
import '../math/cubic_spline.dart';
import 'rosbridge_service.dart';
import '../models/occupancy_grid.dart';
import '../models/system_status.dart';
import '../models/llm_action.dart';
import '../config/process_definitions.dart';

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

  // ── ENU 궤적 (E, N) - 위치 그래프용 ─────────────────────
  List<(double, double)> enuTrajectory = [];

  Function(LatLng)? onOriginSet;

  // ── 차량 위치 (지도) ─────────────────────────────────────
  LatLng? vehiclePosition;
  List<LatLng> trajectory = [];

  // ── Waypoints ───────────────────────────────────────────
  List<WaypointLLH> waypoints = [];

  // ── Spline 경로 ─────────────────────────────────────────
  List<LatLng> splinePath = [];

  // ── Spline 경로 (ENU) - 위치 그래프용 ────────────────────
  List<(double, double)> splineENU = [];

  // ── 연결 상태 ────────────────────────────────────────────
  ConnectionState get connectionState => _ros.state;

  GcsController({String host = 'localhost', int port = 9090})
      : _ros = RosbridgeService(host: host, port: port) {
    _ros.onNavState = _onNavState;
    _ros.onTeleopMode = _onTeleopMode;
    _ros.onControlCommand = _onControlCommand;
    _ros.onPwmCommand = _onPwmCommand;
    _ros.onOccupancyGrid = _onOccupancyGrid; 
    _ros.onConnectionChanged = (_) => notifyListeners();
    _ros.onProcessStatus = _onProcessStatus;
    _ros.onSystemStatus = _onSystemStatus;
  }

  // ── 프로세스 상태 (RUN 탭) ───────────────────────────────
  Map<String, String> processStatus = {};

  // ── 시스템 상태 (TBD/SYSTEM 탭) ──────────────────────────
  SystemStatus systemStatus = const SystemStatus();

  // ── Occupancy Grid ──────────────────────────────────
  OccupancyGridMsg? occupancyGrid;
  int occupancyGridVersion = 0;

  void _onProcessStatus(Map<String, String> status) {
    processStatus = status;
    notifyListeners();
  }

  void startProcess(String name) => _ros.publishProcessCommand(name, 'start');
  void stopProcess(String name) => _ros.publishProcessCommand(name, 'stop');

  // ── ROS 연결 ─────────────────────────────────────────────
  Future<void> connect(String host, int port) async {
    _ros.updateAddress(host, port);
    await _ros.connect();
  }

  void disconnect() => _ros.disconnect();

  void enableOccupancyGrid() => _ros.subscribeOccupancyGrid();
  void disableOccupancyGrid() => _ros.unsubscribeOccupancyGrid();

  // ── 카메라 스트림 ─────────────────────────────────────────
  Stream<Uint8List> get cameraStream => _ros.cameraStream;

  void enableCamera({String topic = '/camera/image_raw/compressed'}) =>
      _ros.subscribeCamera(topic: topic);
  void disableCamera() => _ros.unsubscribeCamera();

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
      // ── ENU 궤적 누적 ────────────────────────────────────
      enuTrajectory.add((msg.position.x, msg.position.y));
    }

    notifyListeners();
  }

  void _onSystemStatus(SystemStatus status) {
    systemStatus = status;
    notifyListeners();
  }

  void restartJetson() => _ros.publishSystemCommand('restart');
  void shutdownJetson() => _ros.publishSystemCommand('shutdown');

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

  void _onOccupancyGrid(OccupancyGridMsg grid) {
    occupancyGrid = grid;
    occupancyGridVersion++;
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

  /// 위치 그래프(ENU)에서 직접 좌표로 waypoint 추가
  void addWaypointENU(double east, double north) {
    LatLng latLng;
    if (_originLLH != null) {
      final llh = enu2llh([east, north, 0.0], _originLLH!);
      latLng = LatLng(rad2deg(llh[0]), rad2deg(llh[1]));
    } else {
      latLng = const LatLng(0, 0);
    }
    waypoints.add(WaypointLLH(latLng: latLng, x: east, y: north));
    _updateSpline();
    notifyListeners();
  }

  /// (east, north) 근처의 waypoint 삭제 (thresholdM 이내)
  void removeWaypointNearENU(double east, double north, double thresholdM) {
    if (waypoints.isEmpty) return;
    int closestIdx = -1;
    double closestDist2 = double.infinity;
    for (int i = 0; i < waypoints.length; i++) {
      final dx = waypoints[i].x - east;
      final dy = waypoints[i].y - north;
      final d2 = dx * dx + dy * dy;
      if (d2 < closestDist2) {
        closestDist2 = d2;
        closestIdx = i;
      }
    }
    if (closestIdx != -1 && closestDist2 < thresholdM * thresholdM) {
      removeWaypoint(closestIdx);
    }
  }

  void clearAll() {
    waypoints.clear();
    splinePath.clear();
    splineENU.clear();
    trajectory.clear();
    enuTrajectory.clear();
    notifyListeners();
  }

  // ── Spline 계산 ───────────────────────────────────────────
  void _updateSpline() {
    if (waypoints.length < 2) {
      splinePath.clear();
      splineENU.clear();
      return;
    }
    final xPts = waypoints.map((w) => w.x).toList();
    final yPts = waypoints.map((w) => w.y).toList();
    final result = calculateCubicSplinePath(xPts, yPts, ds: 0.5);
    if (result == null) {
      splinePath.clear();
      splineENU.clear();
      return;
    }

    splineENU = List.generate(result.x.length, (i) => (result.x[i], result.y[i]));

    if (_originLLH != null) {
      splinePath = splineENU.map((p) {
        final llh = enu2llh([p.$1, p.$2, 0.0], _originLLH!);
        return LatLng(rad2deg(llh[0]), rad2deg(llh[1]));
      }).toList();
    } else {
      splinePath = [];
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

  // ── LLM 명령 실행 ─────────────────────────────────────────
  // LlmService가 반환한 LlmResult.actions를 순서대로 실제 GCS 동작으로 변환.
  // 고위험 액션(restart_jetson, shutdown_jetson)은 즉시 실행하지 않고
  // pendingConfirmations로 분리하여 반환한다. 호출 측(LlmPanel)이 사용자
  // 확인을 받은 뒤 confirmPendingAction()으로 실제 실행해야 한다.
  LlmExecutionResult executeLlmActions(List<LlmAction> actions) {
    final errors = <String>[];
    final pending = <LlmAction>[];

    for (final action in actions) {
      if (action.requiresConfirmation) {
        pending.add(action);
        continue;
      }
      final error = _runAction(action);
      if (error != null) errors.add(error);
    }

    return LlmExecutionResult(errors: errors, pendingConfirmations: pending);
  }

  /// LlmPanel에서 확인 다이얼로그를 거친 고위험 액션을 실제로 실행.
  /// 반환값이 null이 아니면 실행 실패 사유.
  String? confirmPendingAction(LlmAction action) => _runAction(action);

  /// 실제 액션 실행. 성공 시 null, 실패 시 에러 메시지 반환.
  String? _runAction(LlmAction action) {
    try {
      switch (action.type) {
        // ── VEHICLE 탭 ──────────────────────────────────────
        case 'add_waypoint':
          final x = _asDouble(action.params['x']);
          final y = _asDouble(action.params['y']);
          if (x == null || y == null) {
            return 'add_waypoint: x/y 값이 올바르지 않습니다.';
          }
          addWaypointENU(x, y);
          return null;

        case 'set_yaw':
          final yaw = _asDouble(action.params['yaw']);
          if (yaw == null) return 'set_yaw: yaw 값이 올바르지 않습니다.';
          sendSetYaw(yaw);
          return null;

        case 'start':
          sendStart();
          return null;

        case 'stop':
          sendStop();
          return null;

        case 'clear_all':
          clearAll();
          return null;

        // ── MANUAL 탭 (teleop 모드에서만 유효한 동작은 가드 적용) ──
        case 'teleop_mode':
          // mode: 0=STOP, 1=TELEOP, 2=AUTO
          final mode = action.params['mode'];
          final modeInt = mode is num
              ? mode.toInt()
              : int.tryParse(mode?.toString() ?? '');
          if (modeInt == null || modeInt < 0 || modeInt > 2) {
            return 'teleop_mode: mode 값은 0(STOP)/1(TELEOP)/2(AUTO) 중 하나여야 합니다.';
          }
          sendTeleopCommand(modeInt);
          return null;

        case 'speed_up':
          if (!isTeleop) return 'speed_up: TELEOP 모드에서만 사용할 수 있습니다.';
          teleopSpeedUp();
          return null;

        case 'speed_down':
          if (!isTeleop) return 'speed_down: TELEOP 모드에서만 사용할 수 있습니다.';
          teleopSpeedDown();
          return null;

        case 'steer_left':
          if (!isTeleop) return 'steer_left: TELEOP 모드에서만 사용할 수 있습니다.';
          teleopSteerLeft();
          return null;

        case 'steer_right':
          if (!isTeleop) return 'steer_right: TELEOP 모드에서만 사용할 수 있습니다.';
          teleopSteerRight();
          return null;

        case 'speed_reset':
          if (!isTeleop) return 'speed_reset: TELEOP 모드에서만 사용할 수 있습니다.';
          sendSpeedReset();
          return null;

        case 'steer_reset':
          if (!isTeleop) return 'steer_reset: TELEOP 모드에서만 사용할 수 있습니다.';
          sendSteerReset();
          return null;

        // ── RUN 탭 (id는 kValidProcessIds 화이트리스트로 검증) ──
        case 'start_process':
          final id = action.params['id'] as String?;
          if (id == null || !kValidProcessIds.contains(id)) {
            return 'start_process: 알 수 없는 프로세스 id "$id".';
          }
          startProcess(id);
          return null;

        case 'stop_process':
          final id = action.params['id'] as String?;
          if (id == null || !kValidProcessIds.contains(id)) {
            return 'stop_process: 알 수 없는 프로세스 id "$id".';
          }
          stopProcess(id);
          return null;

        // ── SYSTEM 탭 (고위험: executeLlmActions에서 미리 분리되므로
        //    여기 도달하는 경우는 confirmPendingAction을 통한 호출뿐) ──
        case 'restart_jetson':
          restartJetson();
          return null;

        case 'shutdown_jetson':
          shutdownJetson();
          return null;

        default:
          return '알 수 없는 명령: ${action.type}';
      }
    } catch (e) {
      return '${action.type} 실행 중 오류: $e';
    }
  }

  double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// LLM 시스템 프롬프트에 현재 위치 컨텍스트를 제공하기 위한 현재 ENU 위치.
  double get currentEast => navState?.position.x ?? 0.0;
  double get currentNorth => navState?.position.y ?? 0.0;

  @override
  void dispose() {
    _ros.dispose();
    super.dispose();
  }
}
