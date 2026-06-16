// lib/models/llm_action.dart
// LLM이 반환하는 JSON 액션을 표현하는 모델.
// LLM 응답은 항상 {"actions": [ {action: ..., ...params}, ... ], "message": "..."}
// 형태의 JSON 문자열이어야 함.

import 'dart:convert';

class LlmAction {
  final String type; // add_waypoint | set_yaw | start | stop | clear_all
  final Map<String, dynamic> params;

  const LlmAction({required this.type, this.params = const {}});

  factory LlmAction.fromJson(Map<String, dynamic> json) {
    final type = json['action'] as String? ?? '';
    final params = Map<String, dynamic>.from(json)..remove('action');
    return LlmAction(type: type, params: params);
  }
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
