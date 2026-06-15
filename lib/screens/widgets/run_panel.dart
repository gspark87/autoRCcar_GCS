// lib/screens/widgets/run_panel.dart
//
// autorccar 패키지들의 실행/종료를 제어하는 패널 + rosbag record 제어.
// 차량 측 autorccar_util/process_manager_node 와
// /util/process_command (publish), /util/process_status (subscribe) 로 통신.

import 'package:flutter/material.dart';
import '../../ros2/gcs_controller.dart';

/// (프로세스 id, 표시 이름, 설명)
const List<(String, String, String)> kProcesses = [
  ('gscam', 'GSCAM', 'ros2 run gscam gscam_node'),
  ('livox', 'Livox MID360', 'ros2 launch livox_ros_driver2 msg_MID360_launch.py'),
  ('ublox', 'Ublox F9R', 'ros2 run autorccar_ubloxf9r ubloxf9r'),
  ('lio_sam', 'LIO-SAM', 'ros2 launch lio_sam run.launch.py'),
  ('ins_gnss', 'INS/GNSS Nav', 'ros2 launch autorccar_ins_gnss ins_gnss_nav.launch.py'),
  ('planning_control', 'Planning & Control', 'ros2 launch autorccar_planning_control planning_control.launch.py'),
  ('hardware_control', 'Hardware Control', 'ros2 launch autorccar_hardware_control hardware_control.launch.py'),
  ('costmap', 'Costmap', 'ros2 launch autorccar_costmap costmap.launch.py'),
];

/// rosbag record (별도 행, 하단에 표시)
const (String, String, String) kRosbag =
    ('rosbag', 'Rosbag Record', 'ros2 bag record -a -o ~/bags/rosbag2_<timestamp>');

class RunPanel extends StatelessWidget {
  final GcsController ctrl;
  const RunPanel({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ...kProcesses.map((p) {
          final (id, label, desc) = p;
          final status = ctrl.processStatus[id] ?? 'unknown';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ProcessRow(
              id: id,
              label: label,
              desc: desc,
              status: status,
              onStart: () => ctrl.startProcess(id),
              onStop: () => ctrl.stopProcess(id),
            ),
          );
        }),

        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(color: Colors.white12),
        ),

        // ── Rosbag Record ─────────────────────────────────
        _ProcessRow(
          id: kRosbag.$1,
          label: kRosbag.$2,
          desc: kRosbag.$3,
          status: ctrl.processStatus[kRosbag.$1] ?? 'unknown',
          onStart: () => ctrl.startProcess(kRosbag.$1),
          onStop: () => ctrl.stopProcess(kRosbag.$1),
          isRecording: true,
        ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  final String id;
  final String label;
  final String desc;
  final String status; // running / stopped / unknown / error
  final VoidCallback onStart;
  final VoidCallback onStop;
  final bool isRecording;

  const _ProcessRow({
    required this.id,
    required this.label,
    required this.desc,
    required this.status,
    required this.onStart,
    required this.onStop,
    this.isRecording = false,
  });

  bool get _isRunning => status == 'running';

  Color get _statusColor {
    if (isRecording && _isRunning) return Colors.redAccent;
    switch (status) {
      case 'running':
        return Colors.greenAccent;
      case 'error':
        return Colors.redAccent;
      case 'stopped':
        return Colors.white38;
      default:
        return Colors.white24; // unknown (status 토픽 미수신)
    }
  }

  String get _statusLabel {
    if (isRecording && _isRunning) return 'RECORDING';
    switch (status) {
      case 'running':
        return 'RUNNING';
      case 'error':
        return 'ERROR';
      case 'stopped':
        return 'STOPPED';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (isRecording && _isRunning)
            ? Colors.redAccent.withOpacity(0.08)
            : Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: (isRecording && _isRunning)
              ? Colors.redAccent.withOpacity(0.5)
              : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isRecording && _isRunning)
                const Icon(Icons.fiber_manual_record,
                    color: Colors.redAccent, size: 12)
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _statusLabel,
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _smallButton(
                  isRecording ? 'Start Recording' : 'Start',
                  isRecording ? Icons.fiber_manual_record : Icons.play_arrow,
                  isRecording ? Colors.redAccent : Colors.greenAccent,
                  _isRunning ? null : onStart,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _smallButton(
                  isRecording ? 'Stop & Save' : 'Stop',
                  Icons.stop,
                  Colors.redAccent,
                  _isRunning ? onStop : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallButton(
      String label, IconData icon, Color color, VoidCallback? onPressed) {
    final isDisabled = onPressed == null;
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDisabled ? Colors.white10 : color.withOpacity(0.15),
          foregroundColor: isDisabled ? Colors.white24 : color,
          side: BorderSide(
              color: isDisabled ? Colors.white12 : color.withOpacity(0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: 14),
        label: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        onPressed: onPressed,
      ),
    );
  }
}
