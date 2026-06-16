// lib/llm/llm_service.dart
//
// GCS에서 직접 Claude / OpenAI API를 호출하여 자연어 명령을
// 정해진 JSON 액션 스키마로 변환받는다.
//
// 응답 스키마 (시스템 프롬프트로 강제):
// {
//   "actions": [
//     {"action": "add_waypoint", "x": 3.0, "y": 0.0},
//     {"action": "set_yaw", "yaw": 90.0},
//     {"action": "start"},
//     {"action": "stop"},
//     {"action": "clear_all"}
//   ],
//   "message": "사용자에게 보여줄 짧은 설명"
// }

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_settings.dart';

class LlmService {
  static const _claudeUrl = 'https://api.anthropic.com/v1/messages';
  static const _openAiUrl = 'https://api.openai.com/v1/chat/completions';
  static const _anthropicVersion = '2023-06-01';

  /// 차량 좌표계(ENU, East/North/Up [m])와 현재 yaw를 기준으로
  /// LLM이 add_waypoint/set_yaw 등을 올바르게 생성하도록 안내하는 시스템 프롬프트.
  String _buildSystemPrompt({
    required double currentEast,
    required double currentNorth,
    required double currentYawDeg,
    required bool hasOrigin,
  }) {
    return '''
당신은 자율주행 RC카 GCS(Ground Control Station)의 명령 변환기입니다.
사용자의 자연어 명령을 받아 아래 JSON 스키마로만 응답하세요. 설명 텍스트나 마크다운 없이 순수 JSON만 출력합니다.

스키마:
{
  "actions": [ <action object>, ... ],
  "message": "<사용자에게 보여줄 한국어 한두 문장 설명>"
}

action object는 다음 중 하나의 형태만 가능합니다:
- {"action": "add_waypoint", "x": <East 미터, number>, "y": <North 미터, number>}
- {"action": "set_yaw", "yaw": <진북 기준 yaw 각도(deg), -180~180>}
- {"action": "start"}
- {"action": "stop"}
- {"action": "clear_all"}

좌표계 규칙:
- x = East(동쪽, +), y = North(북쪽, +). 단위는 미터.
- 차량의 현재 위치는 (East=$currentEast, North=$currentNorth), 현재 yaw=$currentYawDeg deg (진북=0, 시계방향 증가) 입니다.
- "앞으로 N미터"처럼 차량 기준 상대 명령은 현재 yaw 방향을 기준으로 East/North 변위를 계산해 add_waypoint의 절대 좌표(x,y)로 변환하세요.
  예: yaw=0(북쪽)이면 "앞으로 3m" → 현재 위치에서 North가 +3.
- 여러 waypoint를 순서대로 요구하면 actions 배열에 add_waypoint를 순서대로 여러 개 넣으세요.
- origin(GPS 기준점) 설정 여부: ${hasOrigin ? "설정됨" : "설정되지 않음 (좌표가 부정확할 수 있음을 message에 안내)"}.
- 명령이 모호하거나 위 액션으로 표현할 수 없으면 actions를 빈 배열로 두고 message에 이유를 설명하세요.
- 순수 JSON 객체 하나만 출력하세요. 코드블록(```)도 사용하지 마세요.
''';
  }

  Future<String> sendCommand({
    required LlmSettings settings,
    required String userInput,
    required double currentEast,
    required double currentNorth,
    required double currentYawDeg,
    required bool hasOrigin,
  }) async {
    final systemPrompt = _buildSystemPrompt(
      currentEast: currentEast,
      currentNorth: currentNorth,
      currentYawDeg: currentYawDeg,
      hasOrigin: hasOrigin,
    );

    switch (settings.provider) {
      case LlmProvider.claude:
        return _callClaude(settings, systemPrompt, userInput);
      case LlmProvider.openai:
        return _callOpenAi(settings, systemPrompt, userInput);
    }
  }

  Future<String> _callClaude(
    LlmSettings settings,
    String systemPrompt,
    String userInput,
  ) async {
    final res = await http.post(
      Uri.parse(_claudeUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': settings.claudeApiKey,
        'anthropic-version': _anthropicVersion,
      },
      body: jsonEncode({
        'model': settings.claudeModel,
        'max_tokens': 1024,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userInput},
        ],
      }),
    );

    if (res.statusCode != 200) {
      throw LlmApiException(
          'Claude API 오류 (${res.statusCode}): ${_extractErrorMessage(res.body)}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw const LlmApiException('Claude 응답에 content가 없습니다.');
    }
    final textBlock = content.firstWhere(
      (c) => c['type'] == 'text',
      orElse: () => null,
    );
    if (textBlock == null) {
      throw const LlmApiException('Claude 응답에서 텍스트를 찾을 수 없습니다.');
    }
    return textBlock['text'] as String? ?? '';
  }

  Future<String> _callOpenAi(
    LlmSettings settings,
    String systemPrompt,
    String userInput,
  ) async {
    final res = await http.post(
      Uri.parse(_openAiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.openAiApiKey}',
      },
      body: jsonEncode({
        'model': settings.openAiModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userInput},
        ],
        'response_format': {'type': 'json_object'},
      }),
    );

    if (res.statusCode != 200) {
      throw LlmApiException(
          'OpenAI API 오류 (${res.statusCode}): ${_extractErrorMessage(res.body)}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw const LlmApiException('OpenAI 응답에 choices가 없습니다.');
    }
    final message = choices.first['message'] as Map<String, dynamic>?;
    return message?['content'] as String? ?? '';
  }

  String _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] != null) return err['message'].toString();
        if (err != null) return err.toString();
      }
    } catch (_) {}
    return body.length > 200 ? '${body.substring(0, 200)}...' : body;
  }
}

class LlmApiException implements Exception {
  final String message;
  const LlmApiException(this.message);
  @override
  String toString() => message;
}
