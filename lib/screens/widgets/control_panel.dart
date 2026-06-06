// lib/screens/widgets/control_panel.dart

import 'package:flutter/material.dart';
import '../../ros2/gcs_controller.dart';

class ControlPanel extends StatelessWidget {
  final GcsController ctrl;
  final VoidCallback onSetOrigin;

  const ControlPanel({
    super.key,
    required this.ctrl,
    required this.onSetOrigin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 모드 배너
          _modeBanner(),
          const SizedBox(height: 10),

          // Origin 설정
          _gcsButton(
            label: 'Set Origin',
            icon: Icons.my_location,
            color: Colors.blueAccent,
            onPressed: onSetOrigin,
          ),
          const SizedBox(height: 6),

          // 경로 버튼들
          Row(
            children: [
              Expanded(
                child: _gcsButton(
                  label: 'Clear All',
                  icon: Icons.clear_all,
                  color: Colors.white38,
                  onPressed: ctrl.clearAll,
                  small: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _gcsButton(
                  label: 'Send Path',
                  icon: Icons.send,
                  color: Colors.tealAccent,
                  onPressed: ctrl.waypoints.isNotEmpty ? ctrl.sendGlobalPath : null,
                  small: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Set Yaw
          _gcsButton(
            label: 'Set Yaw',
            icon: Icons.rotate_right,
            color: Colors.purpleAccent,
            onPressed: () => _showSetYawDialog(context),
          ),
          const SizedBox(height: 6),

          // Start / Stop
          Row(
            children: [
              Expanded(
                child: _gcsButton(
                  label: 'START',
                  icon: Icons.play_arrow,
                  color: Colors.greenAccent,
                  onPressed: ctrl.isTeleop ? null : ctrl.sendStart,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _gcsButton(
                  label: 'STOP',
                  icon: Icons.stop,
                  color: Colors.redAccent,
                  onPressed: ctrl.sendStop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Waypoint 개수
          if (ctrl.waypoints.isNotEmpty)
            Text(
              'Waypoints: ${ctrl.waypoints.length}  |  Spline: ${ctrl.splinePath.length}pts',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _modeBanner() {
    final isTeleop = ctrl.isTeleop;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isTeleop
            ? Colors.orange.withOpacity(0.2)
            : Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isTeleop ? Colors.orange : Colors.green,
          width: 1.5,
        ),
      ),
      child: Text(
        isTeleop ? 'TELEOP MODE' : 'AUTO MODE',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isTeleop ? Colors.orange : Colors.green,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _gcsButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
    bool small = false,
  }) {
    final isDisabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: small ? 36 : 40,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDisabled ? Colors.white10 : color.withOpacity(0.15),
          foregroundColor: isDisabled ? Colors.white24 : color,
          side: BorderSide(
              color: isDisabled ? Colors.white12 : color.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: small ? 14 : 16),
        label: Text(
          label,
          style: TextStyle(fontSize: small ? 11 : 12, fontWeight: FontWeight.bold),
        ),
        onPressed: onPressed,
      ),
    );
  }

  void _showSetYawDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text('Set Yaw',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
              signed: true, decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '진북 기준 Yaw 각도 [deg]',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blueAccent)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent.withOpacity(0.3)),
            onPressed: () {
              final parsed = double.tryParse(controller.text);
              if (parsed != null) {
                double val = parsed;
                while (val > 180) val = val - 360;
                while (val <= -180) val = val + 360;
                ctrl.sendSetYaw(val);
                Navigator.pop(ctx);
              }
            },
            child:
                const Text('Set', style: TextStyle(color: Colors.purpleAccent)),
          ),
        ],
      ),
    );
  }
}
