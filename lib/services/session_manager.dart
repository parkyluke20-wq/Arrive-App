import 'dart:async';

import '../constants/app_constants.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  Timer? _timer;

  final Duration timeout = AppConstants.sessionTimeout;

  void start(void Function() onTimeout) {
    _timer?.cancel();
    _timer = Timer(timeout, onTimeout);
  }

  void reset(void Function() onTimeout) {
    start(onTimeout);
  }

  void stop() {
    _timer?.cancel();
  }
}