// lib/config/process_definitions.dart
//
// RUN 탭에서 제어하는 프로세스 목록.
// run_panel.dart(UI)와 gcs_controller.dart(LLM 액션 화이트리스트 검증)가
// 공통으로 참조하므로 위젯 레이어가 아닌 별도 설정 파일로 분리.

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

/// LLM 액션 화이트리스트 검증용: 유효한 모든 프로세스 id 집합
final Set<String> kValidProcessIds = {
  ...kProcesses.map((p) => p.$1),
  kRosbag.$1,
};
