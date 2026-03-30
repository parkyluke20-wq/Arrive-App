import 'dart:async';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  Timer? _timer;

  final Duration timeout = const Duration(minutes: 240);

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