// lib/map/connectivity_service.dart
//
// OSM 타일 서버 접속 가능 여부를 주기적으로 확인하고 캐싱.
// HybridTileProvider가 매 타일마다 타임아웃을 기다리지 않도록
// 미리 온라인/오프라인 상태를 판단해 둠.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends ChangeNotifier {
  static const _checkUrl = 'https://tile.openstreetmap.org/0/0/0.png';
  static const _checkInterval = Duration(seconds: 15);
  static const _checkTimeout = Duration(seconds: 2);

  bool _isOnline = true; // 첫 체크 전까지는 온라인으로 가정
  bool _checked = false;
  Timer? _timer;

  bool get isOnline => _isOnline;
  bool get checked => _checked;

  ConnectivityService() {
    _check();
    _timer = Timer.periodic(_checkInterval, (_) => _check());
  }

  Future<void> _check() async {
    bool result;
    try {
      final res = await http.get(Uri.parse(_checkUrl)).timeout(_checkTimeout);
      result = res.statusCode == 200;
    } catch (_) {
      result = false;
    }

    _checked = true;
    if (result != _isOnline) {
      _isOnline = result;
      notifyListeners();
    }
  }

  /// 즉시 재확인 (예: 사용자가 "재시도" 버튼 눌렀을 때)
  Future<void> recheck() => _check();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
