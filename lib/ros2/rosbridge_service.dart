// lib/ros2/rosbridge_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/nav_state.dart';
import '../models/control_command.dart';

enum ConnectionState { disconnected, connecting, connected, error }

class RosbridgeService {
  static const int _reconnectDelayMs = 3000;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  String _host;
  int _port;

  // 콜백
  Function(NavState)? onNavState;
  Function(bool)? onTeleopMode;
  Function(ControlCommand)? onControlCommand;
  Function(ConnectionState)? onConnectionChanged;
  Function(ControlCommand)? onPwmCommand;

  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  RosbridgeService({String host = 'localhost', int port = 9090})
      : _host = host,
        _port = port;

  void updateAddress(String host, int port) {
    _host = host;
    _port = port;
  }

  void connect() {
    if (_state == ConnectionState.connected ||
        _state == ConnectionState.connecting) return;

    _setState(ConnectionState.connecting);
    final uri = Uri.parse('ws://$_host:$_port');

    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );
      _setState(ConnectionState.connected);
      _subscribeTopics();
    } catch (e) {
      _onError(e);
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
  }

  void _subscribeTopics() {
    _subscribe('nav_topic', 'autorccar_interfaces/msg/NavState');
    _subscribe('hardware_control/teleop_mode', 'std_msgs/msg/Bool');
    _subscribe('hardware_control/control_command', 'autorccar_interfaces/msg/ControlCommand');
    _subscribe('hardware_control/pwm_command', 'autorccar_interfaces/msg/ControlCommand');
  }

  void _subscribe(String topic, String type) {
    _send({
      'op': 'subscribe',
      'topic': topic,
      'type': type,
    });
  }

  void _unsubscribeAll() {
    _send({'op': 'unsubscribe', 'topic': 'nav_topic'});
    _send({'op': 'unsubscribe', 'topic': 'hardware_control/teleop_mode'});
    _send({'op': 'unsubscribe', 'topic': 'hardware_control/control_command'});
  }

  // ── Publish ──────────────────────────────────────────────

  void publishCommand(int cmd) {
    _publish('gcs/command', 'std_msgs/msg/Int8', {'data': cmd});
  }

  void publishSetYaw(double yaw) {
    _publish('setyaw_topic', 'std_msgs/msg/Float32', {'data': yaw});
  }

  void publishGlobalPath(List<List<double>> pathList) {
    List<Map> pathPoints = pathList
        .map((p) => {'x': p[0], 'y': p[1], 'speed': 0.0})
        .toList();
    _publish('gcs/global_path', 'autorccar_interfaces/msg/Path',
        {'path_points': pathPoints});
  }

  void _publish(String topic, String type, Map msg) {
    _send({'op': 'publish', 'topic': topic, 'type': type, 'msg': msg});
  }

  void publishTeleopCommand(int cmd) {
    _publish('teleop/command', 'std_msgs/msg/Int8', {'data': cmd});
  }

  void publishTeleopControlCommand(double speed, double steeringAngle) {
    _publish('teleop/control_command', 'autorccar_interfaces/msg/ControlCommand',
        {'speed': speed, 'steering_angle': steeringAngle});
  }

  // ── Internal ─────────────────────────────────────────────

  void _send(Map data) {
    if (_state != ConnectionState.connected) return;
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final op = data['op'] as String?;
      if (op != 'publish') return;

      final topic = data['topic'] as String?;
      final msg = data['msg'] as Map<String, dynamic>?;
      if (msg == null) return;

      switch (topic) {
        case 'nav_topic':
          onNavState?.call(NavState.fromRosMsg(msg));
          break;
        case 'hardware_control/teleop_mode':
          onTeleopMode?.call(msg['data'] as bool? ?? false);
          break;
        case 'hardware_control/control_command':
          onControlCommand?.call(ControlCommand.fromRosMsg(msg));
          break;
        case 'hardware_control/pwm_command':
          onPwmCommand?.call(ControlCommand.fromRosMsg(msg));
          break;
      }
    } catch (_) {}
  }

  void _onError(dynamic error) {
    _setState(ConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    if (_state == ConnectionState.connected) {
      _setState(ConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(milliseconds: _reconnectDelayMs),
      () {
        if (_state != ConnectionState.connected) connect();
      },
    );
  }

  void _setState(ConnectionState s) {
    _state = s;
    onConnectionChanged?.call(s);
  }

  void dispose() {
    disconnect();
  }
}
