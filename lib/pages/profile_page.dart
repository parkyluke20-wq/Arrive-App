import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

enum EffectiveRole {
  customerUser,
  customerAdmin,
  internalUser,
  internalAdmin,
  supplierUser,
}

enum UserType { customer, supplier, internal }

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

                Row(
                  children: [
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

                    const SizedBox(width: 12), // spacing between buttons

                  if (effectiveRole == EffectiveRole.internalUser ||
                  effectiveRole == EffectiveRole.internalAdmin) ...[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BrandColors.lightBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => _CreateUserDialog(
                            customers: customers,
                            effectiveRole: effectiveRole,
                          ),
                        );
                      },
                      child: const Text('Create New User'),
                    ),
                    ],
                  ],
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

                const SizedBox(height: 8),

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

class _CreateUserDialog extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  final EffectiveRole effectiveRole;

  const _CreateUserDialog({
    required this.customers,
    required this.effectiveRole,
  });

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  @override
  void initState() {
    super.initState();

    nameController.addListener(() => setState(() {}));
    emailController.addListener(() => setState(() {}));

    _loadSites();
  }
  List<Map<String, dynamic>> sites = [];
  final nameController = TextEditingController();
  final emailController = TextEditingController();

  UserType? selectedType;
  int? selectedCustomerId;
  int? selectedSiteId;

  bool _isValid() {
    if (nameController.text.trim().isEmpty) return false;
    if (emailController.text.trim().isEmpty) return false;
    if (selectedType == null) return false;

    if (selectedType == UserType.customer ||
        selectedType == UserType.supplier) {
      return selectedCustomerId != null;
    }
    if (selectedType == UserType.internal) {
      return selectedSiteId != null;
    }

    return false;
  }

  bool submitting = false;

  Future<void> _loadSites() async {
    final res = await Supabase.instance.client
        .from('sites')
        .select('site_id, site_name');

    sites = List<Map<String, dynamic>>.from(res);
  }

  @override
    Widget build(BuildContext context) {
      return AlertDialog(
        title: const Text('Create User'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 40),

              DropdownButtonFormField2<UserType>(
                isExpanded: true,
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'User Type',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: UserType.customer, child: Text('Customer')),
                  DropdownMenuItem(value: UserType.supplier, child: Text('Supplier')),
                  DropdownMenuItem(value: UserType.internal, child: Text('Internal')),
                ],
                dropdownStyleData: const DropdownStyleData(
                  maxHeight: 260,
                ),
                menuItemStyleData: const MenuItemStyleData(
                  height: 32,
                ),
                onChanged: (v) => setState(() => selectedType = v),
              ),

              const SizedBox(height: 60),

              if (selectedType == UserType.customer ||
                  selectedType == UserType.supplier)
                DropdownButtonFormField2<int>(
                  isExpanded: true,
                  value: selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  items: widget.customers
                      .map((c) => DropdownMenuItem<int>(
                            value: c['customer_id'],
                            child: Text(
                              c['customer_name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 260,
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                  ),
                  onChanged: (v) => setState(() => selectedCustomerId = v),
                ),
              const SizedBox(height: 20),

              if (selectedType == UserType.internal)
                DropdownButtonFormField2<int>(
                  isExpanded: true,
                  value: selectedSiteId,
                  decoration: const InputDecoration(
                    labelText: 'Site',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  items: sites
                      .map((s) => DropdownMenuItem<int>(
                            value: s['site_id'],
                            child: Text(
                              s['site_name'],
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 260,
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                  ),
                  onChanged: (v) => setState(() => selectedSiteId = v),
                ),


              const SizedBox(height: 16),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: (!_isValid() || submitting) ? null : _submit,
            child: submitting
                ? const CircularProgressIndicator()
                : const Text('Create'),
          ),
        ],
      );
    }

    Future<void> _submit() async {
      setState(() => submitting = true);

      final name = _toProperCase(nameController.text.trim());
      final email = emailController.text.trim();

      if (name.isEmpty || email.isEmpty || selectedType == null) {
        return;
      }

      String role;
      String scopeType;
      int scopeId;

      switch (selectedType!) {
        case UserType.customer:
          role = 'customer_user';
          scopeType = 'customer';
          scopeId = selectedCustomerId!;
          break;
        case UserType.supplier:
          role = 'supplier_user';
          scopeType = 'customer';
          scopeId = selectedCustomerId!;
          break;
        case UserType.internal:
          role = 'internal_user';
          scopeType = 'site';
          scopeId = selectedSiteId!;
          break;
      }

      final csv =
      'email,name,role,scope_type,scope_id\n'
      '$email,$name,$role,$scopeType,$scopeId';

      print('CREATE USER: calling function...');

      try {
        final response = await http.post(
          Uri.parse('https://eozwxanmzamutjztoxbo.supabase.co/functions/v1/bulk_create_users_from_app'),
          headers: {
            'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVvend4YW5temFtdXRqenRveGJvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2OTYwODU4MCwiZXhwIjoyMDg1MTg0NTgwfQ.O0UlhIQSDK3jYMbZESITa6ThNeWH6ICf17SoJnb1l5w',
            'Content-Type': 'text/csv',
          },
          body: csv,
        );

        print('STATUS: ${response.statusCode}');
        print('BODY: ${response.body}');

        if (response.statusCode != 200) {
          setState(() => submitting = false);
          _snack('Failed: ${response.body}');
          return;
        }
        final result = response.body;

        setState(() => submitting = false);

        // close create dialog
        final parentContext = context;
        Navigator.pop(context);

        Future.microtask(() {
          _showResultDialog(parentContext, result);
        });

      } catch (e) {
        print('CREATE USER ERROR: $e');
        setState(() => submitting = false);
        _snack('Error: $e');
      }
    }
  
    String _toProperCase(String input) {
    return input
        .toLowerCase()
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  void _showResultDialog(BuildContext context, String result) {
    List<dynamic> parsed = [];

    try {
      final decoded = jsonDecode(result);
      if (decoded is List) {
        parsed = decoded;
      }
    } catch (e) {
      parsed = [];
    }

    final buffer = StringBuffer();

    for (final u in parsed) {
      if (u is Map<String, dynamic>) {
        final status = u['status'];

        buffer.writeln('Name: ${u['name'] ?? ''}');
        buffer.writeln('Email: ${u['email'] ?? ''}');

        if (status == 'created') {
          buffer.writeln('Password: ${u['password'] ?? ''}');
        } else {
          buffer.writeln('Status: Failed');
          buffer.writeln('Reason: ${u['error'] ?? 'Unknown error'}');
        }

        buffer.writeln('');
      }
    }

    final displayText = buffer.toString().trim();
    final hasFailure = parsed.any((u) =>
        u is Map<String, dynamic> && u['status'] != 'created');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hasFailure ? 'User Creation Failed' : 'User Created!'),
              IconButton( 
                icon: const Icon(Icons.copy),
                tooltip: 'Copy',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: displayText));
                  _snack('Copied to clipboard');
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(fontSize: 14, color: Colors.black),
                children: parsed.expand<InlineSpan>((u) {
                  if (u is! Map<String, dynamic>) return <InlineSpan>[];

                  final status = u['status'];

                  return [
                    const TextSpan(
                      text: 'Name: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: '${u['name'] ?? ''}\n\n'),

                    const TextSpan(
                      text: 'Email: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: '${u['email'] ?? ''}\n\n'),

                    if (status == 'created') ...[
                      const TextSpan(
                        text: 'Password: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: '${u['password'] ?? ''}\n\n'),
                    ] else ...[
                      const TextSpan(
                        text: 'Status: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: 'Failed\n\n'),

                      const TextSpan(
                        text: 'Reason: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: '${u['error'] ?? 'Unknown error'}\n\n'),
                    ],

                    const TextSpan(text: '\n\n\n'),
                  ];
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
  }