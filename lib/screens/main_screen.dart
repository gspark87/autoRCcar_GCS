// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../ros2/gcs_controller.dart';
import '../ros2/rosbridge_service.dart' as rb;
import 'widgets/nav_status_panel.dart';
import 'widgets/control_panel.dart';
import 'widgets/connection_dialog.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final MapController _mapController = MapController();
  bool _isSettingOrigin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GcsController>().onOriginSet = (latLng) {
        _mapController.move(latLng, 18);
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<GcsController>();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: _buildAppBar(ctrl),
      body: Row(
        children: [
          // ── 지도 영역 (60%) ─────────────────────────────
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                _buildMap(ctrl),
                _buildMapOverlay(ctrl),
              ],
            ),
          ),
          // ── 우측 패널 (40%) ─────────────────────────────
          Container(
            width: 380,
            color: const Color(0xFF16213E),
            child: Column(
              children: [
                Expanded(child: NavStatusPanel(ctrl: ctrl)),
                ControlPanel(ctrl: ctrl, onSetOrigin: _enterOriginMode),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(GcsController ctrl) {
    final isConnected = ctrl.connectionState == rb.ConnectionState.connected;
    final isConnecting = ctrl.connectionState == rb.ConnectionState.connecting;

    return AppBar(
      backgroundColor: const Color(0xFF0F3460),
      title: const Text(
        'AutoRCCar GCS',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      actions: [
        // 연결 상태 표시
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isConnected
                  ? Colors.green.withOpacity(0.2)
                  : isConnecting
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
              border: Border.all(
                color: isConnected
                    ? Colors.green
                    : isConnecting
                        ? Colors.orange
                        : Colors.red,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isConnected
                      ? Icons.wifi
                      : isConnecting
                          ? Icons.wifi_find
                          : Icons.wifi_off,
                  color: isConnected
                      ? Colors.green
                      : isConnecting
                          ? Colors.orange
                          : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected
                      ? 'CONNECTED'
                      : isConnecting
                          ? 'CONNECTING...'
                          : 'DISCONNECTED',
                  style: TextStyle(
                    color: isConnected
                        ? Colors.green
                        : isConnecting
                            ? Colors.orange
                            : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 연결 설정 버튼
        IconButton(
          icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
          tooltip: 'rosbridge 연결 설정',
          onPressed: () => _showConnectionDialog(context),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMap(GcsController ctrl) {
    final center = ctrl.vehiclePosition ?? const LatLng(37.3595, 127.1052);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 18,
        onTap: (tapPos, latLng) {
          if (_isSettingOrigin) {
            ctrl.setOrigin(latLng);
            setState(() => _isSettingOrigin = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Origin 설정: ${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}',
                ),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          } else {
            ctrl.addWaypoint(latLng);
          }
        },
      ),
      children: [
        // OSM 타일
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.autorccar_gcs',
          errorTileCallback: (tile, error, stackTrace) {},
        ),
        // 주행 궤적
        if (ctrl.trajectory.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: ctrl.trajectory,
                strokeWidth: 2.5,
                color: Colors.blueAccent.withOpacity(0.8),
              ),
            ],
          ),
        // Spline 경로
        if (ctrl.splinePath.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: ctrl.splinePath,
                strokeWidth: 2.0,
                color: Colors.white.withOpacity(0.7),
              ),
            ],
          ),
        // Waypoint 연결선
        if (ctrl.waypoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: ctrl.waypoints.map((w) => w.latLng).toList(),
                strokeWidth: 1.0,
                color: Colors.black.withOpacity(0.8),
              ),
            ],
          ),
        // Waypoint 마커
        MarkerLayer(
          markers: [
            // Waypoints
            ...ctrl.waypoints.asMap().entries.map((e) {
              final idx = e.key;
              final wp = e.value;
              return Marker(
                point: wp.latLng,
                width: 36,
                height: 36,
                child: GestureDetector(
                  onSecondaryTap: () => ctrl.removeWaypoint(idx),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black54, width: 2),
                        ),
                      ),
                      Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            // 차량 마커
            if (ctrl.vehiclePosition != null)
              Marker(
                point: ctrl.vehiclePosition!,
                width: 40,
                height: 40,
                child: Transform.rotate(
                  angle: _yawToMapAngle(ctrl.yawDeg),
                  child: const Icon(
                    Icons.navigation,
                    color: Colors.blueAccent,
                    size: 32,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
            // Origin 마커
            if (ctrl.hasOrigin && ctrl.vehiclePosition == null)
              Marker(
                point: _mapController.camera.center,
                width: 20,
                height: 20,
                child: const Icon(Icons.add, color: Colors.red, size: 20),
              ),
          ],
        ),
      ],
    );
  }

Widget _buildMapOverlay(GcsController ctrl) {
  return Stack(
    children: [
      // 좌측 하단 오버레이
      Positioned(
        bottom: 16,
        left: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSettingOrigin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      '지도를 클릭하여 Origin 설정',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            if (!_isSettingOrigin && ctrl.hasOrigin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '좌클릭: Waypoint 추가  |  우클릭: 삭제  |  ${ctrl.waypoints.length}개',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            if (!ctrl.hasOrigin && !_isSettingOrigin)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '⚠ ROS2 연결 후 Origin 자동 설정됩니다',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
      // 우측 상단 GPS 표시
      if (ctrl.vehiclePosition != null)
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'GPS POSITION',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lat: ${ctrl.vehiclePosition!.latitude.toStringAsFixed(7)}',
                  style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
                Text(
                  'Lon: ${ctrl.vehiclePosition!.longitude.toStringAsFixed(7)}',
                  style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

  double _yawToMapAngle(double yawDeg) {
    // yaw: 북쪽 기준 시계방향 [deg] → 지도 회전각 [rad]
    return -yawDeg * 3.14159265 / 180.0;
  }

  void _enterOriginMode() {
    setState(() => _isSettingOrigin = true);
  }

  void _showConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => ConnectionDialog(
        onConnect: (host, port) {
          context.read<GcsController>().connect(host, port);
        },
      ),
    );
  }
}
