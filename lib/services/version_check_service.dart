import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

class VersionCheckService {
  final void Function() onNewVersionAvailable;

  String? _currentVersion;
  Timer? _timer;

  VersionCheckService({required this.onNewVersionAvailable});

  Future<void> init() async {
    _currentVersion = await _fetchVersion();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _check());
  }

  Future<void> _check() async {
    final version = await _fetchVersion();
    if (version == null || _currentVersion == null) return;
    if (version != _currentVersion) {
      _timer?.cancel();
      _timer = null;
      onNewVersionAvailable();
    }
  }

  Future<String?> _fetchVersion() async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final response = await html.HttpRequest.getString('version.json?t=$ts');
      final data = jsonDecode(response) as Map<String, dynamic>;
      return data['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
