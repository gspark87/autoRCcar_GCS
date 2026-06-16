// lib/models/llm_action.dart
// LLM이 반환하는 JSON 액션을 표현하는 모델.
// LLM 응답은 항상 {"actions": [ {action: ..., ...params}, ... ], "message": "..."}
// 형태의 JSON 문자열이어야 함.

import 'dart:convert';

class LlmAction {
  final String type; // add_waypoint | set_yaw | start | stop | clear_all |
                      // teleop_mode | speed_up | speed_down | steer_left |
                      // steer_right | speed_reset | steer_reset |
                      // start_process | stop_process |
                      // restart_jetson | shutdown_jetson
  final Map<String, dynamic> params;

  const LlmAction({required this.type, this.params = const {}});

  factory LlmAction.fromJson(Map<String, dynamic> json) {
    final type = json['action'] as String? ?? '';
    final params = Map<String, dynamic>.from(json)..remove('action');
    return LlmAction(type: type, params: params);
  }

  /// 차량 컴퓨터 재부팅/종료처럼 실행 중인 미션을 중단시킬 수 있는 고위험 액션.
  /// LLM 패널 UI에서 이 액션들은 실행 전 별도 확인 다이얼로그를 한 번 더 거친다.
  static const Set<String> highRiskTypes = {
    'restart_jetson',
    'shutdown_jetson',
  };

  bool get requiresConfirmation => highRiskTypes.contains(type);
}

class LlmResult {
  final List<LlmAction> actions;
  final String message; // 사용자에게 보여줄 자연어 설명/응답

  const LlmResult({required this.actions, required this.message});

  /// LLM 응답 원문(raw)을 파싱.
  /// 파싱 실패 시 actions는 빈 리스트, message에는 원문 그대로 표시.
  factory LlmResult.fromRawResponse(String raw) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
      cleaned = cleaned.replaceFirst(RegExp(r'```\s*$'), '');
      cleaned = cleaned.trim();
    }

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) {
        return LlmResult(actions: const [], message: raw);
      }
      final map = Map<String, dynamic>.from(decoded);

      final List<LlmAction> actions = [];
      final actionsJson = map['actions'];
      if (actionsJson is List) {
        for (final a in actionsJson) {
          if (a is Map) {
            actions.add(LlmAction.fromJson(Map<String, dynamic>.from(a)));
          }
        }
      }

      final message = map['message'] as String? ?? '';
      return LlmResult(actions: actions, message: message);
    } catch (_) {
      // JSON이 아니면 원문을 그대로 메시지로 표시 (액션 없음)
      return LlmResult(actions: const [], message: raw);
    }
  }
}

/// GcsController.executeLlmActions()의 실행 결과.
/// - errors: 즉시 실행을 시도했으나 실패한 액션의 사유 목록
/// - pendingConfirmations: 고위험 액션(LlmAction.requiresConfirmation)으로
///   분류되어 아직 실행되지 않은 액션 목록. 호출 측 UI가 사용자 확인을
///   받은 뒤 GcsController.confirmPendingAction()으로 실행해야 한다.
class LlmExecutionResult {
  final List<String> errors;
  final List<LlmAction> pendingConfirmations;

  const LlmExecutionResult({
    required this.errors,
    required this.pendingConfirmations,
  });

  bool get hasPending => pendingConfirmations.isNotEmpty;
  bool get hasErrors => errors.isNotEmpty;
}
