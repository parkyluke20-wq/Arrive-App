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

  Future<bool> isGlobalAdmin() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    final rows = await supabase
        .from('user_roles')
        .select('scope_type')
        .eq('user_id', user.id)
        .eq('role', 'internal_admin')
        .eq('scope_type', 'global');
    return rows.isNotEmpty;
  }

  Future<bool> isGlobalScope() async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    final rows = await supabase
        .from('user_roles')
        .select('scope_type')
        .eq('user_id', user.id)
        .eq('scope_type', 'global');
    return rows.isNotEmpty;
  }

  void clear() => _role = null;
}
