// lib/screens/widgets/llm_panel.dart
//
// 하단 LLM 인터페이스: 자연어 명령 입력 → API 호출 → JSON 액션 파싱 → GCS 제어.
// 단일 입력창 + 단일 응답 텍스트박스 (대화 히스토리 없음).

import 'package:flutter/material.dart';
import '../../llm/llm_service.dart';
import '../../llm/llm_settings.dart';
import '../../models/llm_action.dart';
import '../../ros2/gcs_controller.dart';
import 'llm_settings_dialog.dart';

class LlmPanel extends StatefulWidget {
  final GcsController ctrl;
  const LlmPanel({super.key, required this.ctrl});

  @override
  State<LlmPanel> createState() => _LlmPanelState();
}

enum _ResponseStatus { idle, loading, success, partial, error }

class _LlmPanelState extends State<LlmPanel> {
  final _inputCtrl = TextEditingController();
  final _llmService = LlmService();

  LlmSettings? _settings;
  _ResponseStatus _status = _ResponseStatus.idle;
  String _responseMessage = '자연어로 명령을 입력하세요. 예: "3미터 앞으로 이동", "출발", "정지", "경로 전체 삭제"';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await LlmSettings.load();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<LlmSettings>(
      context: context,
      builder: (_) => LlmSettingsDialog(initialSettings: _settings),
    );
    if (updated != null && mounted) {
      setState(() => _settings = updated);
    }
  }

  Future<void> _submit() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final settings = _settings;
    if (settings == null || !settings.isConfigured) {
      setState(() {
        _status = _ResponseStatus.error;
        _responseMessage = 'API 키가 설정되지 않았습니다. 우측 설정 아이콘에서 먼저 설정하세요.';
      });
      return;
    }

    setState(() {
      _status = _ResponseStatus.loading;
      _responseMessage = '처리 중...';
    });

    try {
      final raw = await _llmService.sendCommand(
        settings: settings,
        userInput: text,
        currentEast: widget.ctrl.currentEast,
        currentNorth: widget.ctrl.currentNorth,
        currentYawDeg: widget.ctrl.yawDeg,
        hasOrigin: widget.ctrl.hasOrigin,
      );

      final result = LlmResult.fromRawResponse(raw);

      if (result.actions.isEmpty) {
        setState(() {
          _status = _ResponseStatus.success;
          _responseMessage = result.message.isNotEmpty
              ? result.message
              : '실행할 명령이 없습니다.';
        });
        return;
      }

      final errors = widget.ctrl.executeLlmActions(result.actions);

      setState(() {
        if (errors.isEmpty) {
          _status = _ResponseStatus.success;
          _responseMessage = result.message.isNotEmpty
              ? result.message
              : '${result.actions.length}개 명령을 실행했습니다.';
        } else {
          _status = _ResponseStatus.partial;
          _responseMessage =
              '${result.message}\n\n일부 명령 실행 실패:\n${errors.join('\n')}';
        }
      });
    } catch (e) {
      setState(() {
        _status = _ResponseStatus.error;
        _responseMessage = e is LlmApiException ? e.message : '오류 발생: $e';
      });
    } finally {
      _inputCtrl.clear();
    }
  }

  Color get _statusColor => switch (_status) {
        _ResponseStatus.idle => Colors.white38,
        _ResponseStatus.loading => Colors.amberAccent,
        _ResponseStatus.success => Colors.greenAccent,
        _ResponseStatus.partial => Colors.orangeAccent,
        _ResponseStatus.error => Colors.redAccent,
      };

  IconData get _statusIcon => switch (_status) {
        _ResponseStatus.idle => Icons.smart_toy_outlined,
        _ResponseStatus.loading => Icons.hourglass_top,
        _ResponseStatus.success => Icons.check_circle,
        _ResponseStatus.partial => Icons.warning_amber,
        _ResponseStatus.error => Icons.error_outline,
      };

  @override
  Widget build(BuildContext context) {
    final configured = _settings?.isConfigured ?? false;

    return Container(
      color: const Color(0xFF16213E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy, size: 14, color: Colors.tealAccent.withOpacity(0.8)),
              const SizedBox(width: 6),
              const Text(
                'LLM COMMAND',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              if (_settings != null)
                Text(
                  configured
                      ? _settings!.provider.label
                      : 'API 키 미설정',
                  style: TextStyle(
                    color: configured ? Colors.white38 : Colors.orangeAccent,
                    fontSize: 10,
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.settings, size: 16, color: Colors.white54),
                tooltip: 'LLM 연동 설정',
                onPressed: _openSettings,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  enabled: _status != _ResponseStatus.loading,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '예: 3미터 앞으로 이동해줘',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.25),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withOpacity(0.15),
                    foregroundColor: Colors.tealAccent,
                    side: BorderSide(color: Colors.tealAccent.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _status == _ResponseStatus.loading ? null : _submit,
                  child: _status == _ResponseStatus.loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.tealAccent),
                        )
                      : const Text('전송',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _statusColor.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon, size: 14, color: _statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _responseMessage,
                    style: TextStyle(
                      color: _statusColor.withOpacity(0.95),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }
}
