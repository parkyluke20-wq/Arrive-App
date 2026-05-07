import 'supabase_service.dart';

class UserSession {
  UserSession._();
  static final instance = UserSession._();

  String? _role;

  Future<String> getRole() async {
    if (_role != null) return _role!;
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No authenticated user');
    final rows = await supabase
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id);
    if (rows.isEmpty) throw Exception('No role assigned');
    _role = rows.first['role'] as String;
    return _role!;
  }

  void clear() => _role = null;
}
