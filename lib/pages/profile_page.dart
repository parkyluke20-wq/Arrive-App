import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';

enum EffectiveRole {
  customerUser,
  customerAdmin,
  internalUser,
  internalAdmin,
  supplierUser,
}

extension EffectiveRoleUi on EffectiveRole {
  String get label {
    switch (this) {
      case EffectiveRole.customerUser:
        return 'Customer User';
      case EffectiveRole.customerAdmin:
        return 'Customer Admin';
      case EffectiveRole.internalUser:
        return 'Internal User';
      case EffectiveRole.internalAdmin:
        return 'Internal Admin';
      case EffectiveRole.supplierUser:
        return 'Supplier User';
    }
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final supabase = Supabase.instance.client;
  final ScrollController _scrollController = ScrollController();
  InputDecoration _denseDecoration(String label) => const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      border: OutlineInputBorder(),
    ).copyWith(labelText: label);
  bool loading = true;
  String? error;

  late String currentUserId;
  late String currentUserEmail;

  EffectiveRole effectiveRole = EffectiveRole.customerUser;

  List<Map<String, dynamic>> customers = [];
  int? selectedCustomerId;

  List<Map<String, dynamic>> members = [];

  final TextEditingController inviteEmailController = TextEditingController();

  bool showPasswordForm = false;
  bool updatingPassword = false;
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ---------------------------------------------------------------------------
  // LOAD PROFILE
  // ---------------------------------------------------------------------------

  Future<void> _loadProfile() async {
    try {
      final session = supabase.auth.currentSession;
      if (session == null) throw Exception('No active session');

      currentUserId = session.user.id;
      currentUserEmail = session.user.email ?? '';

      final roles = await supabase
          .from('user_roles')
          .select('role, scope_type, scope_type_id')
          .eq('user_id', currentUserId);

      if (roles.isEmpty) throw Exception('No roles assigned');

      effectiveRole = _resolveRole(roles.first['role']);

      customers = await _loadCustomersForRole(roles);
      customers.sort(
        (a, b) => a['customer_name'].compareTo(b['customer_name']),
      );

      if (customers.isNotEmpty) {
        selectedCustomerId = customers.first['customer_id'];
        await _loadMembers();
      }

      setState(() => loading = false);
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  EffectiveRole _resolveRole(String role) {
    switch (role) {
      case 'customer_user':
        return EffectiveRole.customerUser;
      case 'customer_admin':
        return EffectiveRole.customerAdmin;
      case 'internal_user':
        return EffectiveRole.internalUser;
      case 'internal_admin':
        return EffectiveRole.internalAdmin;
      case 'supplier_user':
        return EffectiveRole.supplierUser;
      default:
        throw Exception('Unknown role');
    }
  }

  // ---------------------------------------------------------------------------
  // CUSTOMERS
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _loadCustomersForRole(
    List<dynamic> roles,
  ) async {
    final customerIds = <int>{};
    final siteIds = <int>{};
    bool isGlobal = false;

    for (final r in roles) {
      if (r['scope_type'] == 'global') {
        isGlobal = true;
      }
      if (r['scope_type'] == 'customer') {
        customerIds.add(r['scope_type_id']);
      }
      if (r['scope_type'] == 'site') {
        siteIds.add(r['scope_type_id']);
      }
    }

    if (isGlobal) {
      return await supabase
          .from('customers')
          .select('customer_id, customer_name')
          .eq('active', true)
          .order('customer_name');
    }

    // 🔹 SITE-SCOPED USERS
    if (siteIds.isNotEmpty) {
      final cs = await supabase
          .from('customer_sites')
          .select('customer_id')
          .inFilter('site_id', siteIds.toList());

      customerIds.addAll(
        cs.map((r) => r['customer_id'] as int),
      );
    }

    if (customerIds.isEmpty) return [];

    return await supabase
        .from('customers')
        .select('customer_id, customer_name')
        .inFilter('customer_id', customerIds.toList())
        .eq('active', true)
        .order('customer_name');
  }

  // ---------------------------------------------------------------------------
  // MEMBERS
  // ---------------------------------------------------------------------------

  Future<void> _loadMembers() async {
    final customerId = selectedCustomerId;
    if (customerId == null) return;

    final roleRows = await supabase
        .from('user_roles')
        .select('user_id, role')
        .eq('scope_type', 'customer')
        .eq('scope_type_id', customerId);

    if (roleRows.isEmpty) {
      setState(() => members = []);
      return;
    }

    final userIds =
        roleRows.map((r) => r['user_id'] as String).toList();

    final userRows = await supabase
        .from('users')
        .select('user_id, email')
        .inFilter('user_id', userIds);

    final rows = userRows.map((u) {
      final roleRow =
          roleRows.firstWhere((r) => r['user_id'] == u['user_id']);
      return {
        'user_id': u['user_id'],
        'email': u['email'],
        'role': roleRow['role'],
      };
    }).toList();

    rows.sort((a, b) {
      if (a['user_id'] == currentUserId) return -1;
      if (b['user_id'] == currentUserId) return 1;
      return a['email'].compareTo(b['email']);
    });

    setState(() => members = rows);
  }

  // ---------------------------------------------------------------------------
  // MEMBER ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove user'),
        content: const Text(
          'Are you sure you want to remove this user?\n'
          'They will lose access instantly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final deactivateRes = await supabase
        .from('users')
        .update({'active': false})
        .eq('user_id', member['user_id'])
        .select();

    if (deactivateRes.isEmpty) {
      _snack('Failed to deactivate user');
      return;
    }

    final deleteRes = await supabase
        .from('user_roles')
        .delete()
        .eq('user_id', member['user_id'])
        .eq('scope_type', 'customer')
        .eq('scope_type_id', selectedCustomerId!)
        .select();

    if (deleteRes.isEmpty) {
      _snack('User deactivated, but role removal failed');
      return;
    }

    await _loadMembers();
    _snack('User removed');
  }

  Future<void> _upgradeToAdmin(Map<String, dynamic> member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Upgrade to admin'),
        content: const Text(
          'Are you sure you want to upgrade this user to Customer Admin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final res = await supabase
        .from('user_roles')
        .update({'role': 'customer_admin'})
        .eq('user_id', member['user_id'])
        .eq('scope_type', 'customer')
        .eq('scope_type_id', selectedCustomerId!)
        .select();

    if (res.isEmpty) {
      _snack('Upgrade failed (permission denied)');
      return;
    }

    await _loadMembers();
    _snack('User upgraded to admin');
  }

  Widget _memberRow(Map<String, dynamic> member) {
    final isAdmin = member['role'] == 'customer_admin';
    final isSelf = member['user_id'] == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              member['email'],
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isAdmin && !isSelf) ...[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => _upgradeToAdmin(member),
              child: const Text('Upgrade'),
            ),
            const SizedBox(width: 8),
          ],
          if (!isSelf)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: () => _removeMember(member),
              child: const Text('Remove'),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PASSWORD
  // ---------------------------------------------------------------------------

  Future<void> _updatePassword() async {
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (newPassword.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }

    if (newPassword != confirmPassword) {
      _snack('Passwords do not match');
      return;
    }

    setState(() => updatingPassword = true);

    try {
      await supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      newPasswordController.clear();
      confirmPasswordController.clear();

      setState(() {
        showPasswordForm = false;
        updatingPassword = false;
      });

      _snack('Password updated');
    } catch (e) {
      setState(() => updatingPassword = false);
      _snack(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // INVITE
  // ---------------------------------------------------------------------------

  Future<void> _inviteUser() async {
    final email = inviteEmailController.text.trim();
    if (email.isEmpty) return;

    int? inviteCustomerId;

    if (effectiveRole == EffectiveRole.customerAdmin ||
        effectiveRole == EffectiveRole.customerUser) {
      inviteCustomerId =
          customers.isNotEmpty ? customers.first['customer_id'] : null;
    } else {
      inviteCustomerId = selectedCustomerId;
    }

    if (inviteCustomerId == null) return;

    final customerName = customers
        .firstWhere((c) => c['customer_id'] == inviteCustomerId)['customer_name'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Invite'),
        content: Text('Invite $email to $customerName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Invite'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await supabase.from('invites').upsert(
      {
        'email': email,
        'role': 'customer_user',
        'scope_type': 'customer',
        'scope_type_id': inviteCustomerId,
        'created_by': currentUserId,
      },
      onConflict: 'email',
    );

    inviteEmailController.clear();
    _snack('Invite sent');
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Scaffold(body: Center(child: Text(error!)));
    }

    return AppScaffold(
      title: 'Profile',
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: SingleChildScrollView(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Details',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _detailRow('Email', currentUserEmail),
                _detailRow('Role', effectiveRole.label),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BrandColors.lightBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      setState(() => showPasswordForm = !showPasswordForm),
                  child: Text(
                    showPasswordForm ? 'Cancel' : 'Update Password',
                  ),
                ),

                if (showPasswordForm) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      helperText: 'Minimum 6 characters',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: updatingPassword ? null : _updatePassword,
                    child: updatingPassword
                        ? const CircularProgressIndicator()
                        : const Text('Update Password'),
                  ),
                ],

                if (effectiveRole != EffectiveRole.customerUser &&
                    effectiveRole != EffectiveRole.supplierUser &&
                    customers.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Text(
                    'Select Customer',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField2<int>(
                    isExpanded: true,
                    value: selectedCustomerId,
                    decoration: _denseDecoration('Customer'),
                    items: customers
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c['customer_id'],
                            child: Text(
                              c['customer_name'],
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    dropdownStyleData: const DropdownStyleData(
                      maxHeight: 260,
                    ),
                    menuItemStyleData: const MenuItemStyleData(
                      height: 32,
                    ),
                    onChanged: (value) async {
                      setState(() => selectedCustomerId = value);
                      await _loadMembers();
                    },
                  ),
                ],

                if (effectiveRole != EffectiveRole.supplierUser) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Invite User',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inviteEmailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BrandColors.green,
                          foregroundColor: BrandColors.charcoal,
                        ),
                        onPressed: null,
                        child: const Text('Invite'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Coming soon...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                ],

                if (effectiveRole != EffectiveRole.supplierUser) ...[
                const SizedBox(height: 32),
                const Text(
                  'Members',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
               Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  children: members.map(_memberRow).toList(),
                ),
              ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('$label:')),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
