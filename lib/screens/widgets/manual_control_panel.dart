// lib/screens/widgets/manual_control_panel.dart

import 'package:flutter/material.dart';

class ManualControlPanel extends StatelessWidget {
  const ManualControlPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── 모드 전환 버튼 3개 ─────────────────────────
          Row(
            children: [
              Expanded(child: _modeButton('MODE 1', Icons.looks_one, Colors.blueAccent)),
              const SizedBox(width: 6),
              Expanded(child: _modeButton('MODE 2', Icons.looks_two, Colors.orangeAccent)),
              const SizedBox(width: 6),
              Expanded(child: _modeButton('MODE 3', Icons.looks_3, Colors.purpleAccent)),
            ],
          ),
          const SizedBox(height: 8),

          // ── 기능 버튼 2개 ──────────────────────────────
          Row(
            children: [
              Expanded(child: _funcButton('FUNC 1', Icons.bolt, Colors.tealAccent)),
              const SizedBox(width: 6),
              Expanded(child: _funcButton('FUNC 2', Icons.settings, Colors.tealAccent)),
            ],
          ),
          const SizedBox(height: 80),

          // ── 방향키 ────────────────────────────────────
          _buildDpad(),
        ],
      ),
    );
  }

  Widget _buildDpad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _arrowButton(Icons.keyboard_arrow_up, 'UP'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _arrowButton(Icons.keyboard_arrow_left, 'LEFT'),
            const SizedBox(width: 4),
            _centerButton(),
            const SizedBox(width: 4),
            _arrowButton(Icons.keyboard_arrow_right, 'RIGHT'),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _arrowButton(Icons.keyboard_arrow_down, 'DOWN'),
          ],
        ),
      ],
    );
  }

  Widget _arrowButton(IconData icon, String label) {
    return SizedBox(
      width: 72,
      height: 72,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.08),
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
        onPressed: () {},
        child: Icon(icon, size: 36),
      ),
    );
  }

  Widget _centerButton() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, Color color) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: 14),
        label: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        onPressed: () {},
      ),
    );
  }

  Widget _funcButton(String label, IconData icon, Color color) {
    return SizedBox(
      height: 40,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: 14),
        label: Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        onPressed: () {},
      ),
    );
  }
}