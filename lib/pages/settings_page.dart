import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../layouts/app_scaffold.dart';
import '../services/supabase_service.dart';
import '../theme/brand_colors.dart';

// ─── Shared helpers ───────────────────────────────────────────────────────────

const _dayNames = <int, String>{
  0: 'Sunday',
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
};

const _dayOrder = [1, 2, 3, 4, 5, 6, 0];

TimeOfDay _parseTime(String t) {
  final parts = t.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

String _formatPoolName(String name) => name
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _displayTime(String stored) {
  final parts = stored.split(':');
  if (parts.length < 2) return stored;
  return '${parts[0]}:${parts[1]}';
}

InputDecoration _fieldDecoration(String label) => const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      border: OutlineInputBorder(),
    ).copyWith(labelText: label);

Widget _activeBadge(bool active) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: active ? BrandColors.green : BrandColors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: const TextStyle(fontSize: 12),
      ),
    );

Widget _strategyBadge(String strategy) {
  final colors = <String, Color>{
    'site_window': BrandColors.lightBlue,
    'pool_window': BrandColors.orange,
    'fixed_times': BrandColors.deepBlue,
    'daily_limit': BrandColors.green,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: colors[strategy] ?? BrandColors.grey,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      strategy,
      style: const TextStyle(fontSize: 12, color: Colors.white),
    ),
  );
}

Widget _headerCell(String text, double width) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );

Widget _textCell(String text, double width) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(text, overflow: TextOverflow.ellipsis),
      ),
    );

Widget _widgetCell(Widget child, double width) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: child,
      ),
    );

String _friendlyDbError(PostgrestException e) {
  if (e.code == '23505') return 'This record already exists.';
  if (e.code == '23514') return 'A value failed a database constraint check.';
  if (e.code == '23503') return 'A referenced record does not exist.';
  return "Couldn't save — please try again.";
}

// ─── Main page ────────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
      return;
    }
    try {
      final rows = await supabase
          .from('user_roles')
          .select('role, scope_type')
          .eq('user_id', user.id)
          .eq('role', 'internal_admin')
          .eq('scope_type', 'global');
      if (rows.isEmpty) {
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/inbound-overview', (_) => false);
        }
        return;
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/inbound-overview', (_) => false);
      }
      return;
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 5,
      child: AppScaffold(
        title: 'Settings',
        showFooter: false,
        body: Column(
          children: [
            Material(
              color: BrandColors.deepBlue,
              child: const TabBar(
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: BrandColors.orange,
                isScrollable: true,
                tabs: [
                  Tab(text: 'Customers'),
                  Tab(text: 'Pools'),
                  Tab(text: 'Pool Assignment'),
                  Tab(text: 'Slot Availability'),
                  Tab(text: 'Operating Hours'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _CustomersTab(),
                  _PoolsTab(),
                  _PoolAssignmentTab(),
                  _SlotAvailabilityTab(),
                  _OperatingHoursTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1 — CUSTOMERS
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomersTab extends StatefulWidget {
  const _CustomersTab();

  @override
  State<_CustomersTab> createState() => _CustomersTabState();
}

class _CustomersTabState extends State<_CustomersTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allCustomers = [];
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _sites = [];
  String _filterStatus = 'all';
  final _searchController = TextEditingController();
  String _search = '';
  String? _sortColumn;
  bool _sortAscending = true;
  Timer? _searchDebounce;
  final _tableScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _tableScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        withRetry(() => supabase
            .from('customers')
            .select('customer_id, customer_code, customer_name, active, created_at')
            .order('customer_name')),
        withRetry(() => supabase
            .from('sites')
            .select('site_id, site_name')
            .eq('active', true)
            .order('site_name')),
      ]);
      if (!mounted) return;
      setState(() {
        _allCustomers = List<Map<String, dynamic>>.from(results[0]);
        _sites = List<Map<String, dynamic>>.from(results[1]);
        _applyFilters();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load customers — please try again";
      });
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allCustomers);
    if (_filterStatus == 'active') {
      filtered = filtered.where((c) => c['active'] == true).toList();
    } else if (_filterStatus == 'inactive') {
      filtered = filtered.where((c) => c['active'] == false).toList();
    }
    if (_search.isNotEmpty) {
      final s = _search.toLowerCase();
      filtered = filtered.where((c) {
        return (c['customer_name'] ?? '').toString().toLowerCase().contains(s) ||
            (c['customer_code'] ?? '').toString().toLowerCase().contains(s);
      }).toList();
    }
    _customers = filtered;
    if (_sortColumn == 'code') {
      _customers.sort((a, b) {
        final cmp = (a['customer_code'] ?? '').toString()
            .compareTo((b['customer_code'] ?? '').toString());
        return _sortAscending ? cmp : -cmp;
      });
    } else if (_sortColumn == 'name') {
      _customers.sort((a, b) {
        final cmp = (a['customer_name'] ?? '').toString()
            .compareTo((b['customer_name'] ?? '').toString());
        return _sortAscending ? cmp : -cmp;
      });
    }
  }

  Widget _sortableHeaderCell(String label, double width, String col) {
    final active = _sortColumn == col;
    return GestureDetector(
      onTap: () => setState(() {
        if (_sortColumn == col) {
          _sortAscending = !_sortAscending;
        } else {
          _sortColumn = col;
          _sortAscending = true;
        }
        _applyFilters();
      }),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  color: Colors.white,
                  size: 14,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openModal({Map<String, dynamic>? customer}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerModal(
        customer: customer,
        allSites: _sites,
        onSaved: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    const double actionW = 80;
    const double codeW = 160;
    const double nameW = 240;
    const double activeW = 100;
    const double createdW = 160;
    const double tableW = actionW + codeW + nameW + activeW + createdW;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Controls ──
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Customers:',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.lightBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Customer'),
                onPressed: () => _openModal(),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _filterStatus,
                  decoration: _fieldDecoration('Status'),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 200,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  items: const [
                    DropdownMenuItem(
                        value: 'all', child: Text('All statuses')),
                    DropdownMenuItem(
                        value: 'active', child: Text('Active only')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive only')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _filterStatus = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search name or code...',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(
                      const Duration(milliseconds: 300),
                      () => setState(() {
                        _search = value;
                        _applyFilters();
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Table ──
          Expanded(
            child: Scrollbar(
              controller: _tableScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tableScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableW,
                  child: Column(
                    children: [
                      Container(
                        color: BrandColors.lightBlue,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            _headerCell('Action', actionW),
                            _sortableHeaderCell('Code', codeW, 'code'),
                            _sortableHeaderCell('Name', nameW, 'name'),
                            _headerCell('Active', activeW),
                            _headerCell('Created', createdW),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: _customers.map((c) {
                              final createdAt = c['created_at'] != null
                                  ? DateTime.tryParse(
                                          c['created_at'].toString())
                                      ?.toLocal()
                                  : null;
                              final createdStr = createdAt != null
                                  ? '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}'
                                  : '—';
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Colors.black12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: actionW,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Tooltip(
                                          message: 'Edit',
                                          child: IconButton(
                                            icon: const Icon(Icons.edit),
                                            color: BrandColors.orange,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 28,
                                                minHeight: 28),
                                            onPressed: () =>
                                                _openModal(customer: c),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _textCell(
                                        c['customer_code'] ?? '—', codeW),
                                    _textCell(
                                        c['customer_name'] ?? '—', nameW),
                                    _widgetCell(
                                        _activeBadge(
                                            c['active'] as bool? ?? false),
                                        activeW),
                                    _textCell(createdStr, createdW),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Customer modal (add + edit with detail) ──────────────────────────────────

class _CustomerModal extends StatefulWidget {
  final Map<String, dynamic>? customer;
  final List<Map<String, dynamic>> allSites;
  final VoidCallback onSaved;

  const _CustomerModal({
    required this.customer,
    required this.allSites,
    required this.onSaved,
  });

  @override
  State<_CustomerModal> createState() => _CustomerModalState();
}

class _CustomerModalState extends State<_CustomerModal> {
  final _idController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _active = true;
  bool _submitting = false;

  List<Map<String, dynamic>> _customerSites = [];
  int? _selectedSiteToAdd;
  bool _loadingDetail = false;

  List<Map<String, dynamic>> _quotas = [];
  int? _selectedQuotaSite;
  final _quotaPalletsController = TextEditingController();
  final Map<int, TextEditingController> _quotaControllers = {};

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _idController.text = widget.customer!['customer_id'].toString();
      _codeController.text = widget.customer!['customer_code'] ?? '';
      _nameController.text = widget.customer!['customer_name'] ?? '';
      _active = widget.customer!['active'] as bool? ?? true;
      _loadDetail();
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _quotaPalletsController.dispose();
    for (final c in _quotaControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    final customerId = widget.customer!['customer_id'] as int;
    try {
      final results = await Future.wait([
        withRetry(() => supabase
            .from('customer_sites')
            .select('site_id, sites(site_name)')
            .eq('customer_id', customerId)),
        withRetry(() => supabase
            .from('customer_daily_quota')
            .select('site_id, max_daily_pallets, sites(site_name)')
            .eq('customer_id', customerId)),
      ]);
      if (!mounted) return;
      final sites = List<Map<String, dynamic>>.from(results[0]);
      final quotas = List<Map<String, dynamic>>.from(results[1]);
      for (final q in quotas) {
        final siteId = q['site_id'] as int;
        _quotaControllers[siteId]?.dispose();
        _quotaControllers[siteId] = TextEditingController(
          text: q['max_daily_pallets'].toString(),
        );
      }
      setState(() {
        _customerSites = sites;
        _quotas = quotas;
        _loadingDetail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetail = false);
    }
  }

  Future<void> _saveCustomer() async {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    if (code.isEmpty || name.isEmpty) {
      _snack('Customer code and name are required.');
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_isEdit) {
        await supabase
            .from('customers')
            .update({
              'customer_code': code,
              'customer_name': name,
              'active': _active,
            })
            .eq('customer_id', widget.customer!['customer_id']);
      } else {
        final idText = _idController.text.trim();
        if (idText.isEmpty) {
          setState(() => _submitting = false);
          _snack('Customer ID is required.');
          return;
        }
        final id = int.tryParse(idText);
        if (id == null) {
          setState(() => _submitting = false);
          _snack('Customer ID must be an integer.');
          return;
        }
        await supabase.from('customers').insert({
          'customer_id': id,
          'customer_code': code,
          'customer_name': name,
          'active': _active,
        });
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      setState(() => _submitting = false);
      _snack(_friendlyDbError(e));
    } catch (_) {
      setState(() => _submitting = false);
      _snack("Couldn't save — please try again.");
    }
  }

  Future<void> _addSite() async {
    final siteId = _selectedSiteToAdd;
    if (siteId == null) return;
    final customerId = widget.customer!['customer_id'] as int;
    try {
      await supabase.from('customer_sites').insert({
        'customer_id': customerId,
        'site_id': siteId,
      });
      setState(() => _selectedSiteToAdd = null);
      await _loadDetail();
    } on PostgrestException catch (e) {
      _snack(_friendlyDbError(e));
    } catch (_) {
      _snack("Couldn't add site — please try again.");
    }
  }

  Future<void> _removeSite(int siteId, String siteName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Remove Site'),
        content: Text('Remove $siteName from this customer?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final customerId = widget.customer!['customer_id'] as int;
    try {
      await supabase
          .from('customer_sites')
          .delete()
          .eq('customer_id', customerId)
          .eq('site_id', siteId);
      await _loadDetail();
    } catch (_) {
      _snack("Couldn't remove site — please try again.");
    }
  }

  Future<void> _saveQuota(int siteId) async {
    final ctrl = _quotaControllers[siteId];
    if (ctrl == null) return;
    final pallets = int.tryParse(ctrl.text.trim());
    if (pallets == null || pallets < 0) {
      _snack('Max daily pallets must be a non-negative integer.');
      return;
    }
    final customerId = widget.customer!['customer_id'] as int;
    try {
      await supabase
          .from('customer_daily_quota')
          .update({'max_daily_pallets': pallets})
          .eq('customer_id', customerId)
          .eq('site_id', siteId);
      _snack('Quota saved.');
    } catch (_) {
      _snack("Couldn't save quota — please try again.");
    }
  }

  Future<void> _deleteQuota(int siteId, String siteName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Delete Quota'),
        content: Text('Delete the daily quota for $siteName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final customerId = widget.customer!['customer_id'] as int;
    try {
      await supabase
          .from('customer_daily_quota')
          .delete()
          .eq('customer_id', customerId)
          .eq('site_id', siteId);
      await _loadDetail();
    } catch (_) {
      _snack("Couldn't delete quota — please try again.");
    }
  }

  Future<void> _addQuota() async {
    final siteId = _selectedQuotaSite;
    final palletsText = _quotaPalletsController.text.trim();
    if (siteId == null) {
      _snack('Select a site for the quota.');
      return;
    }
    final pallets = int.tryParse(palletsText);
    if (pallets == null || pallets < 0) {
      _snack('Max daily pallets must be a non-negative integer.');
      return;
    }
    final customerId = widget.customer!['customer_id'] as int;
    try {
      await supabase.from('customer_daily_quota').insert({
        'customer_id': customerId,
        'site_id': siteId,
        'max_daily_pallets': pallets,
      });
      setState(() {
        _selectedQuotaSite = null;
        _quotaPalletsController.clear();
      });
      await _loadDetail();
    } on PostgrestException catch (e) {
      _snack(_friendlyDbError(e));
    } catch (_) {
      _snack("Couldn't add quota — please try again.");
    }
  }

  List<Map<String, dynamic>> get _sitesAvailableForQuota {
    final quotaSiteIds =
        _quotas.map((q) => q['site_id'] as int).toSet();
    return _customerSites.where((cs) {
      return !quotaSiteIds.contains(cs['site_id'] as int);
    }).toList();
  }

  List<Map<String, dynamic>> get _sitesNotLinked {
    final linked = _customerSites.map((cs) => cs['site_id'] as int).toSet();
    return widget.allSites
        .where((s) => !linked.contains(s['site_id'] as int))
        .toList();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BrandColors.background,
      title: Text(_isEdit ? 'Edit Customer' : 'Add Customer'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Form fields ──
              if (!_isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: _idController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: _fieldDecoration('Customer ID *'),
                  ),
                ),
              if (_isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextField(
                    controller: _idController,
                    readOnly: true,
                    decoration: _fieldDecoration('Customer ID (read-only)'),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _codeController,
                  decoration: _fieldDecoration('Customer Code *'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _nameController,
                  decoration: _fieldDecoration('Customer Name *'),
                ),
              ),
              Row(
                children: [
                  const Text('Active'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),

              // ── Customer detail (edit mode only) ──
              if (_isEdit) ...[
                const Divider(height: 32),
                const Text('Customer Sites',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_loadingDetail)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  ..._customerSites.map((cs) {
                    final siteId = cs['site_id'] as int;
                    final siteName =
                        cs['sites']?['site_name'] as String? ?? '—';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(siteName)),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: BrandColors.red,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () =>
                                _removeSite(siteId, siteName),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (_sitesNotLinked.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<int>(
                            isExpanded: true,
                            value: _selectedSiteToAdd,
                            decoration: _fieldDecoration('Add site'),
                            items: _sitesNotLinked
                                .map((s) => DropdownMenuItem<int>(
                                      value: s['site_id'] as int,
                                      child: Text(
                                        s['site_name'] as String,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            dropdownStyleData: const DropdownStyleData(
                              maxHeight: 260,
                              decoration: BoxDecoration(
                                  color: BrandColors.background),
                            ),
                            menuItemStyleData:
                                const MenuItemStyleData(height: 32),
                            onChanged: (v) =>
                                setState(() => _selectedSiteToAdd = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BrandColors.lightBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _selectedSiteToAdd != null
                              ? _addSite
                              : null,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                ],
                const Divider(height: 32),
                const Text('Customer Daily Quota',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_loadingDetail)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  ..._quotas.map((q) {
                    final siteId = q['site_id'] as int;
                    final siteName =
                        q['sites']?['site_name'] as String? ?? '—';
                    final ctrl = _quotaControllers[siteId] ??
                        TextEditingController(
                            text: q['max_daily_pallets'].toString());
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(siteName)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              controller: ctrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 8),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () => _saveQuota(siteId),
                            child: const Text('Save'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            color: BrandColors.red,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () =>
                                _deleteQuota(siteId, siteName),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (_sitesAvailableForQuota.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField2<int>(
                            isExpanded: true,
                            value: _selectedQuotaSite,
                            decoration: _fieldDecoration('Site'),
                            items: _sitesAvailableForQuota
                                .map((s) => DropdownMenuItem<int>(
                                      value: s['site_id'] as int,
                                      child: Text(
                                        s['sites']?['site_name']
                                                as String? ??
                                            '—',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ))
                                .toList(),
                            dropdownStyleData: const DropdownStyleData(
                              maxHeight: 260,
                              decoration: BoxDecoration(
                                  color: BrandColors.background),
                            ),
                            menuItemStyleData:
                                const MenuItemStyleData(height: 32),
                            onChanged: (v) =>
                                setState(() => _selectedQuotaSite = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _quotaPalletsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: _fieldDecoration('Pallets'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BrandColors.lightBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _addQuota,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _saveCustomer,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — POOLS
// ═══════════════════════════════════════════════════════════════════════════════

class _PoolsTab extends StatefulWidget {
  const _PoolsTab();

  @override
  State<_PoolsTab> createState() => _PoolsTabState();
}

class _PoolsTabState extends State<_PoolsTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _allPools = [];
  List<Map<String, dynamic>> _pools = [];
  List<Map<String, dynamic>> _sites = [];
  String _filterSite = 'all';
  String _filterActive = 'all';
  String _filterStrategy = 'all';
  final _tableScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tableScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        withRetry(() => supabase
            .from('capacity_pools')
            .select(
                'pool_id, pool_name, display_name, site_id, load_type, priority, active, slot_strategy, exclude_bank_holidays, max_bookings_per_day, sites(site_name)')
            .order('priority')),
        withRetry(() => supabase
            .from('sites')
            .select('site_id, site_name')
            .eq('active', true)
            .order('site_name')),
      ]);
      if (!mounted) return;
      setState(() {
        _allPools = List<Map<String, dynamic>>.from(results[0]);
        _sites = List<Map<String, dynamic>>.from(results[1]);
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Pools load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load pools — please try again";
      });
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allPools);
    if (_filterSite != 'all') {
      filtered = filtered
          .where((p) =>
              (p['sites']?['site_name'] as String?) == _filterSite)
          .toList();
    }
    if (_filterActive == 'active') {
      filtered =
          filtered.where((p) => p['active'] == true).toList();
    } else if (_filterActive == 'inactive') {
      filtered =
          filtered.where((p) => p['active'] == false).toList();
    }
    if (_filterStrategy != 'all') {
      filtered = filtered
          .where((p) => p['slot_strategy'] == _filterStrategy)
          .toList();
    }
    _pools = filtered;
  }

  List<String> get _siteOptions {
    final names = _allPools
        .map((p) => p['sites']?['site_name'] as String?)
        .where((s) => s != null)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    return ['all', ...names];
  }

  void _openModal({Map<String, dynamic>? pool}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PoolModal(pool: pool, sites: _sites, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    const double actionW = 80;
    const double displayNameW = 180;
    const double poolNameW = 250;
    const double siteW = 140;
    const double loadTypeW = 100;
    const double strategyW = 130;
    const double priorityW = 95;
    const double activeW = 80;
    const double maxBookW = 90;
    const double bankHolW = 80;
    const double tableW = actionW +
        displayNameW +
        poolNameW +
        siteW +
        loadTypeW +
        strategyW +
        priorityW +
        activeW +
        maxBookW +
        bankHolW;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Pools:',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.lightBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Pool'),
                onPressed: () => _openModal(),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _filterSite,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 300,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  items: _siteOptions
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s == 'all' ? 'All sites' : s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _filterSite = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _filterActive,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 200,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(
                        value: 'active', child: Text('Active only')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive only')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _filterActive = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _filterStrategy,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 260,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  items: const [
                    DropdownMenuItem(
                        value: 'all', child: Text('All strategies')),
                    DropdownMenuItem(
                        value: 'site_window', child: Text('site_window')),
                    DropdownMenuItem(
                        value: 'pool_window', child: Text('pool_window')),
                    DropdownMenuItem(
                        value: 'fixed_times', child: Text('fixed_times')),
                    DropdownMenuItem(
                        value: 'daily_limit', child: Text('daily_limit')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _filterStrategy = v;
                      _applyFilters();
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Scrollbar(
              controller: _tableScrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tableScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableW,
                  child: Column(
                    children: [
                      Container(
                        color: BrandColors.lightBlue,
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            _headerCell('Action', actionW),
                            _headerCell(
                                'Display Name', displayNameW),
                            _headerCell('Pool Name', poolNameW),
                            _headerCell('Site', siteW),
                            _headerCell('Load Type', loadTypeW),
                            _headerCell('Strategy', strategyW),
                            SizedBox(
                              width: priorityW,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Text(
                                  'Priority',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            _headerCell('Active', activeW),
                            _headerCell('Max/Day', maxBookW),
                            _headerCell('BH Excl', bankHolW),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: _pools.map((p) {
                              final siteName =
                                  p['sites']?['site_name']
                                          as String? ??
                                      '—';
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: Colors.black12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: actionW,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 4),
                                        child: Tooltip(
                                          message: 'Edit',
                                          child: IconButton(
                                            icon:
                                                const Icon(Icons.edit),
                                            color: BrandColors.orange,
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(
                                                    minWidth: 28,
                                                    minHeight: 28),
                                            onPressed: () =>
                                                _openModal(pool: p),
                                          ),
                                        ),
                                      ),
                                    ),
                                    _textCell(
                                        p['display_name'] ?? '—',
                                        displayNameW),
                                    _textCell(
                                        p['pool_name'] ?? '—',
                                        poolNameW),
                                    _textCell(siteName, siteW),
                                    _textCell(
                                        p['load_type'] ?? '—',
                                        loadTypeW),
                                    _widgetCell(
                                        _strategyBadge(
                                            p['slot_strategy'] ??
                                                ''),
                                        strategyW),
                                    SizedBox(
                                      width: priorityW,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        child: Text(
                                          '${p['priority'] ?? '—'}',
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    _widgetCell(
                                        _activeBadge(
                                            p['active'] as bool? ??
                                                false),
                                        activeW),
                                    _textCell(
                                        p['max_bookings_per_day']
                                                ?.toString() ??
                                            '—',
                                        maxBookW),
                                    _textCell(
                                        '${p['exclude_bank_holidays'] ?? '—'}',
                                        bankHolW),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pool modal ───────────────────────────────────────────────────────────────

class _PoolModal extends StatefulWidget {
  final Map<String, dynamic>? pool;
  final List<Map<String, dynamic>> sites;
  final VoidCallback onSaved;

  const _PoolModal(
      {required this.pool,
      required this.sites,
      required this.onSaved});

  @override
  State<_PoolModal> createState() => _PoolModalState();
}

class _PoolModalState extends State<_PoolModal> {
  final _displayNameController = TextEditingController();
  final _poolNameController = TextEditingController();
  final _loadTypeController = TextEditingController();
  final _priorityController = TextEditingController();
  final _excludeBhController = TextEditingController();
  final _maxBookingsController = TextEditingController();
  int? _selectedSiteId;
  bool _active = true;
  String _slotStrategy = 'site_window';
  bool _submitting = false;

  bool get _isEdit => widget.pool != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.pool!;
      _displayNameController.text = p['display_name'] ?? '';
      _poolNameController.text = p['pool_name'] ?? '';
      _loadTypeController.text = p['load_type'] ?? '';
      _priorityController.text = '${p['priority'] ?? ''}';
      _excludeBhController.text =
          '${p['exclude_bank_holidays'] ?? 1}';
      _maxBookingsController.text =
          p['max_bookings_per_day']?.toString() ?? '';
      _selectedSiteId = p['site_id'] as int?;
      _active = p['active'] as bool? ?? true;
      _slotStrategy = p['slot_strategy'] ?? 'site_window';
    } else {
      _excludeBhController.text = '1';
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _poolNameController.dispose();
    _loadTypeController.dispose();
    _priorityController.dispose();
    _excludeBhController.dispose();
    _maxBookingsController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    final poolName = _poolNameController.text.trim();
    if (displayName.isEmpty || poolName.isEmpty) {
      _snack('Display name and pool name are required.');
      return;
    }
    if (_selectedSiteId == null) {
      _snack('Select a site.');
      return;
    }
    final priority = int.tryParse(_priorityController.text.trim());
    if (priority == null) {
      _snack('Priority must be an integer.');
      return;
    }
    final excludeBh =
        int.tryParse(_excludeBhController.text.trim()) ?? 1;
    int? maxBookings;
    if (_slotStrategy == 'fixed_times') {
      maxBookings = null;
    } else {
      final raw = _maxBookingsController.text.trim();
      if (raw.isNotEmpty) {
        maxBookings = int.tryParse(raw);
        if (maxBookings == null || maxBookings <= 0) {
          _snack('Max bookings per day must be a positive integer.');
          return;
        }
      }
    }
    setState(() => _submitting = true);
    final payload = {
      'display_name': displayName,
      'pool_name': poolName,
      'site_id': _selectedSiteId,
      'load_type': _loadTypeController.text.trim().isEmpty
          ? null
          : _loadTypeController.text.trim(),
      'priority': priority,
      'active': _active,
      'slot_strategy': _slotStrategy,
      'exclude_bank_holidays': excludeBh,
      'max_bookings_per_day': maxBookings,
    };
    try {
      if (_isEdit) {
        await supabase
            .from('capacity_pools')
            .update(payload)
            .eq('pool_id', widget.pool!['pool_id']);
      } else {
        await supabase.from('capacity_pools').insert(payload);
      }
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      setState(() => _submitting = false);
      _snack(_friendlyDbError(e));
    } catch (_) {
      setState(() => _submitting = false);
      _snack("Couldn't save — please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixedTimes = _slotStrategy == 'fixed_times';
    return AlertDialog(
      backgroundColor: BrandColors.background,
      title: Text(_isEdit ? 'Edit Pool' : 'Add Pool'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _displayNameController,
                  decoration: _fieldDecoration('Display Name *'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _poolNameController,
                  decoration: _fieldDecoration('Pool Name *'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField2<int>(
                  isExpanded: true,
                  value: _selectedSiteId,
                  decoration: _fieldDecoration('Site *'),
                  items: widget.sites
                      .map((s) => DropdownMenuItem<int>(
                            value: s['site_id'] as int,
                            child: Text(s['site_name'] as String,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 260,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  onChanged: (v) =>
                      setState(() => _selectedSiteId = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _loadTypeController,
                  decoration: _fieldDecoration('Load Type (optional)'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _priorityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: _fieldDecoration('Priority *'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _excludeBhController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration:
                      _fieldDecoration('Exclude Bank Holidays'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _slotStrategy,
                  decoration: _fieldDecoration('Slot Strategy *'),
                  items: const [
                    DropdownMenuItem(
                        value: 'site_window',
                        child: Text('site_window')),
                    DropdownMenuItem(
                        value: 'pool_window',
                        child: Text('pool_window')),
                    DropdownMenuItem(
                        value: 'fixed_times',
                        child: Text('fixed_times')),
                    DropdownMenuItem(
                        value: 'daily_limit',
                        child: Text('daily_limit')),
                  ],
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 260,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _slotStrategy = v;
                      if (v == 'fixed_times') {
                        _maxBookingsController.clear();
                      }
                    });
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _maxBookingsController,
                  enabled: !fixedTimes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: _fieldDecoration(
                      'Max Bookings Per Day (optional)'),
                ),
              ),
              if (fixedTimes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Max bookings per day is not applicable for the fixed_times strategy.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              Row(
                children: [
                  const Text('Active'),
                  const SizedBox(width: 8),
                  Switch(
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — POOL ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════

class _PoolAssignmentTab extends StatefulWidget {
  const _PoolAssignmentTab();

  @override
  State<_PoolAssignmentTab> createState() => _PoolAssignmentTabState();
}

class _PoolAssignmentTabState extends State<_PoolAssignmentTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _pools = [];
  List<Map<String, dynamic>> _customers = [];
  String _filterSite = 'all';

  List<String> get _siteOptions {
    final names = _pools
        .map((p) => p['sites']?['site_name'] as String?)
        .where((s) => s != null)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    return ['all', ...names];
  }

  List<Map<String, dynamic>> get _filteredPools {
    if (_filterSite == 'all') return _pools;
    return _pools
        .where((p) => (p['sites']?['site_name'] as String?) == _filterSite)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        withRetry(() => supabase
            .from('capacity_pool_customers')
            .select(
                'pool_customer_id, pool_id, customer_id, mode, capacity_pools(display_name, site_id, sites(site_name)), customers(customer_name)')
            .order('pool_id')),
        withRetry(() => supabase
            .from('capacity_pools')
            .select(
                'pool_id, pool_name, display_name, site_id, sites(site_name)')
            .eq('active', true)
            .order('pool_name')),
        withRetry(() => supabase
            .from('customers')
            .select('customer_id, customer_name')
            .eq('active', true)
            .order('customer_name')),
      ]);
      if (!mounted) return;
      setState(() {
        _assignments = List<Map<String, dynamic>>.from(results[0]);
        _pools = List<Map<String, dynamic>>.from(results[1]);
        _customers = List<Map<String, dynamic>>.from(results[2]);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Pool assignments load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load pool assignments — please try again";
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> get _byPool {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final a in _assignments) {
      final poolId = a['pool_id'].toString();
      out.putIfAbsent(poolId, () => []).add(a);
    }
    return out;
  }

  Future<void> _deleteAssignment(
      String poolCustomerId, String customerName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Remove Assignment'),
        content: Text(
            'Remove $customerName from this pool?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase
          .from('capacity_pool_customers')
          .delete()
          .eq('pool_customer_id', poolCustomerId);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "Couldn't remove assignment — please try again")));
    }
  }

  Future<void> _editMode(Map<String, dynamic> assignment) async {
    final poolId = assignment['pool_id'].toString();
    final poolAssignments =
        _assignments.where((a) => a['pool_id'].toString() == poolId).toList();
    final currentMode = assignment['mode'] as String;
    final otherRows =
        poolAssignments.where((a) => a['pool_customer_id'] != assignment['pool_customer_id']).toList();

    String? selectedMode = currentMode;
    String? errorMsg;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: BrandColors.background,
          title: const Text('Edit Assignment Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (otherRows.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'This pool has ${otherRows.length} other assignment(s). '
                    'Mode can only change if all other rows already use the new mode.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              DropdownButtonFormField2<String>(
                isExpanded: true,
                value: selectedMode,
                decoration: _fieldDecoration('Mode'),
                items: const [
                  DropdownMenuItem(
                      value: 'include', child: Text('include')),
                  DropdownMenuItem(
                      value: 'exclude', child: Text('exclude')),
                ],
                dropdownStyleData: const DropdownStyleData(
                  maxHeight: 200,
                  decoration: BoxDecoration(
                      color: BrandColors.background),
                ),
                menuItemStyleData:
                    const MenuItemStyleData(height: 32),
                onChanged: (v) => setLocal(() => selectedMode = v),
              ),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(errorMsg!,
                      style: TextStyle(
                          color: BrandColors.red, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedMode == currentMode) {
                  Navigator.pop(ctx);
                  return;
                }
                final incompatible = otherRows.any(
                    (r) => r['mode'] != selectedMode);
                if (incompatible) {
                  setLocal(() => errorMsg =
                      'Cannot change mode: other rows in this pool use a different mode.');
                  return;
                }
                try {
                  await supabase
                      .from('capacity_pool_customers')
                      .update({'mode': selectedMode})
                      .eq('pool_customer_id',
                          assignment['pool_customer_id']);
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } on PostgrestException catch (e) {
                  setLocal(() => errorMsg = _friendlyDbError(e));
                } catch (_) {
                  setLocal(() => errorMsg =
                      "Couldn't update mode — please try again.");
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final grouped = _byPool;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Pool Assignment:',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.lightBlue,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Assignment'),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _AddAssignmentModal(
                      pools: _pools,
                      customers: _customers,
                      assignments: _assignments,
                      onSaved: _load,
                    ),
                  );
                },
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField2<String>(
                  isExpanded: true,
                  value: _filterSite,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 300,
                    decoration:
                        BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData:
                      const MenuItemStyleData(height: 32),
                  items: _siteOptions
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s == 'all' ? 'All sites' : s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _filterSite = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _filteredPools
                    .where((p) =>
                        grouped.containsKey(p['pool_id'].toString()))
                    .map((pool) {
                  final poolId = pool['pool_id'].toString();
                  final rows = grouped[poolId] ?? [];
                  final mode = rows.isNotEmpty
                      ? rows.first['mode'] as String? ?? '—'
                      : '—';
                  final poolName =
                      _formatPoolName(pool['pool_name'] as String? ?? '');
                  final siteName =
                      pool['sites']?['site_name'] as String? ?? '—';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: BrandColors.deepBlue
                                .withValues(alpha: 0.08),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$poolName — $siteName',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: mode == 'include'
                                      ? BrandColors.green
                                      : BrandColors.orange,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: Text('Mode: $mode',
                                    style: const TextStyle(
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        ...rows.map((a) {
                          final customerName =
                              a['customers']?['customer_name']
                                      as String? ??
                                  '—';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: const BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Colors.black12)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(customerName)),
                                Tooltip(
                                  message: 'Edit mode',
                                  child: IconButton(
                                    icon: const Icon(Icons.edit),
                                    color: BrandColors.orange,
                                    padding: EdgeInsets.zero,
                                    constraints:
                                        const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28),
                                    onPressed: () =>
                                        _editMode(a),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Remove',
                                  child: IconButton(
                                    icon:
                                        const Icon(Icons.delete),
                                    color: BrandColors.red,
                                    padding: EdgeInsets.zero,
                                    constraints:
                                        const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28),
                                    onPressed: () =>
                                        _deleteAssignment(
                                            a['pool_customer_id']
                                                .toString(),
                                            customerName),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAssignmentModal extends StatefulWidget {
  final List<Map<String, dynamic>> pools;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> assignments;
  final VoidCallback onSaved;

  const _AddAssignmentModal({
    required this.pools,
    required this.customers,
    required this.assignments,
    required this.onSaved,
  });

  @override
  State<_AddAssignmentModal> createState() =>
      _AddAssignmentModalState();
}

class _AddAssignmentModalState extends State<_AddAssignmentModal> {
  String? _selectedPoolId;
  int? _selectedCustomerId;
  String _mode = 'include';
  bool _modeLocked = false;
  String? _errorMsg;
  bool _submitting = false;

  void _onPoolChanged(String? poolId) {
    if (poolId == null) return;
    final existing = widget.assignments
        .where((a) => a['pool_id'] == poolId)
        .toList();
    setState(() {
      _selectedPoolId = poolId;
      if (existing.isNotEmpty) {
        _mode = existing.first['mode'] as String? ?? 'include';
        _modeLocked = true;
      } else {
        _modeLocked = false;
        _mode = 'include';
      }
    });
  }

  Future<void> _save() async {
    if (_selectedPoolId == null || _selectedCustomerId == null) {
      setState(() => _errorMsg = 'Select a pool and a customer.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });
    try {
      await supabase.from('capacity_pool_customers').insert({
        'pool_id': _selectedPoolId,
        'customer_id': _selectedCustomerId,
        'mode': _mode,
      });
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      setState(() {
        _submitting = false;
        _errorMsg = e.code == '23505'
            ? 'This customer is already assigned to this pool.'
            : _friendlyDbError(e);
      });
    } catch (_) {
      setState(() {
        _submitting = false;
        _errorMsg = "Couldn't save — please try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: BrandColors.background,
      title: const Text('Add Pool Assignment'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField2<String>(
                isExpanded: true,
                value: _selectedPoolId,
                decoration: _fieldDecoration('Pool *'),
                items: widget.pools.map((p) {
                  final displayName =
                      p['display_name'] as String? ?? '—';
                  final siteName =
                      p['sites']?['site_name'] as String? ?? '—';
                  return DropdownMenuItem<String>(
                    value: p['pool_id'].toString(),
                    child: Text('$displayName — $siteName',
                        overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                dropdownStyleData: const DropdownStyleData(
                  maxHeight: 260,
                  decoration:
                      BoxDecoration(color: BrandColors.background),
                ),
                menuItemStyleData:
                    const MenuItemStyleData(height: 32),
                onChanged: _onPoolChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: DropdownButtonFormField2<int>(
                isExpanded: true,
                value: _selectedCustomerId,
                decoration: _fieldDecoration('Customer *'),
                items: widget.customers
                    .map((c) => DropdownMenuItem<int>(
                          value: c['customer_id'] as int,
                          child: Text(
                              c['customer_name'] as String? ?? '—',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                dropdownStyleData: const DropdownStyleData(
                  maxHeight: 260,
                  decoration:
                      BoxDecoration(color: BrandColors.background),
                ),
                menuItemStyleData:
                    const MenuItemStyleData(height: 32),
                onChanged: (v) =>
                    setState(() => _selectedCustomerId = v),
              ),
            ),
            DropdownButtonFormField2<String>(
              isExpanded: true,
              value: _mode,
              decoration: _fieldDecoration('Mode *'),
              items: const [
                DropdownMenuItem(
                    value: 'include', child: Text('include')),
                DropdownMenuItem(
                    value: 'exclude', child: Text('exclude')),
              ],
              dropdownStyleData: const DropdownStyleData(
                maxHeight: 200,
                decoration:
                    BoxDecoration(color: BrandColors.background),
              ),
              menuItemStyleData:
                  const MenuItemStyleData(height: 32),
              onChanged:
                  _modeLocked ? null : (v) => setState(() => _mode = v ?? _mode),
            ),
            if (_modeLocked && _selectedPoolId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This pool uses $_mode mode — all assignments must share the same mode.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_errorMsg!,
                    style: TextStyle(
                        color: BrandColors.red, fontSize: 13)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — SLOT AVAILABILITY
// ═══════════════════════════════════════════════════════════════════════════════

class _SlotAvailabilityTab extends StatefulWidget {
  const _SlotAvailabilityTab();

  @override
  State<_SlotAvailabilityTab> createState() => _SlotAvailabilityTabState();
}

class _SlotAvailabilityTabState extends State<_SlotAvailabilityTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pools = [];
  String? _filterSiteId;
  List<({String id, String name})> _availableSites = [];
  String? _selectedPoolId;

  bool _loadingHours = false;
  List<Map<String, dynamic>> _operatingHours = [];

  bool _loadingSlots = false;
  List<Map<String, dynamic>> _fixedSlots = [];

  Map<String, dynamic>? get _selectedPool =>
      _pools.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p!['pool_id'] == _selectedPoolId,
          orElse: () => null);

  String get _selectedStrategy =>
      _selectedPool?['slot_strategy'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _loadPools();
  }

  Future<void> _loadPools() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await withRetry(() => supabase
          .from('capacity_pools')
          .select(
              'pool_id, pool_name, display_name, slot_strategy, site_id, sites(site_name)')
          .eq('active', true)
          .order('display_name'));
      if (!mounted) return;
      final pools = List<Map<String, dynamic>>.from(result);
      final seen = <String>{};
      final sites = <({String id, String name})>[];
      for (final p in pools) {
        final siteId = p['site_id']?.toString();
        final siteName = p['sites']?['site_name'] as String?;
        if (siteId != null && siteName != null && seen.add(siteId)) {
          sites.add((id: siteId, name: siteName));
        }
      }
      sites.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _pools = pools;
        _availableSites = sites;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Slot availability pools load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load pools — please try again";
      });
    }
  }

  List<Map<String, dynamic>> get _filteredPools {
    final pools = _filterSiteId == null
        ? List<Map<String, dynamic>>.from(_pools)
        : _pools.where((p) => p['site_id']?.toString() == _filterSiteId).toList();
    pools.sort((a, b) =>
        (a['display_name'] as String? ?? '').compareTo(b['display_name'] as String? ?? ''));
    return pools;
  }

  Future<void> _loadPoolData(String poolId) async {
    setState(() { _loadingHours = true; _loadingSlots = true; });
    try {
      final results = await Future.wait([
        withRetry(() => supabase
            .from('pool_operating_hours')
            .select(
                'pool_id, day_of_week_int, day_of_week_text, open_time, close_time')
            .eq('pool_id', poolId)),
        withRetry(() => supabase
            .from('pool_fixed_slot_times')
            .select(
                'pool_id, day_of_week_int, day_of_week_text, slot_time, visible')
            .eq('pool_id', poolId)
            .order('day_of_week_int')
            .order('slot_time')),
      ]);
      if (!mounted) return;
      setState(() {
        _operatingHours = List<Map<String, dynamic>>.from(results[0]);
        _fixedSlots = List<Map<String, dynamic>>.from(results[1]);
        _loadingHours = false;
        _loadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loadingHours = false; _loadingSlots = false; });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showHoursDialog(
      {Map<String, dynamic>? existing, required int dayInt}) async {
    final dayName = _dayNames[dayInt] ?? 'Day';
    TimeOfDay open = existing != null
        ? _parseTime(existing['open_time'] as String)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay close = existing != null
        ? _parseTime(existing['close_time'] as String)
        : const TimeOfDay(hour: 17, minute: 0);
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: BrandColors.background,
          title: Text(
              '${existing != null ? 'Edit' : 'Add'} Hours — $dayName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Open time')),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: open,
                      );
                      if (picked != null) setLocal(() => open = picked);
                    },
                    child: Text(
                        '${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('Close time')),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: close,
                      );
                      if (picked != null)
                        setLocal(() => close = picked);
                    },
                    child: Text(
                        '${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: TextStyle(
                          color: BrandColors.red, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final openMins = open.hour * 60 + open.minute;
                final closeMins = close.hour * 60 + close.minute;
                if (closeMins <= openMins) {
                  setLocal(() =>
                      err = 'Close time must be after open time.');
                  return;
                }
                try {
                  final payload = {
                    'pool_id': _selectedPoolId,
                    'day_of_week_int': dayInt,
                    'day_of_week_text': _dayNames[dayInt],
                    'open_time': _formatTimeOfDay(open),
                    'close_time': _formatTimeOfDay(close),
                  };
                  if (existing != null) {
                    await supabase
                        .from('pool_operating_hours')
                        .update({
                          'open_time': _formatTimeOfDay(open),
                          'close_time': _formatTimeOfDay(close),
                        })
                        .eq('pool_id', _selectedPoolId!)
                        .eq('day_of_week_int', dayInt);
                  } else {
                    await supabase
                        .from('pool_operating_hours')
                        .insert(payload);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadPoolData(_selectedPoolId!);
                } on PostgrestException catch (e) {
                  setLocal(() => err = _friendlyDbError(e));
                } catch (_) {
                  setLocal(() => err =
                      "Couldn't save — please try again.");
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHours(int dayInt, String dayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Delete Operating Hours'),
        content: Text('Delete hours for $dayName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase
          .from('pool_operating_hours')
          .delete()
          .eq('pool_id', _selectedPoolId!)
          .eq('day_of_week_int', dayInt);
      await _loadPoolData(_selectedPoolId!);
    } catch (_) {
      _snack("Couldn't delete hours — please try again.");
    }
  }

  Future<void> _toggleSlotVisible(
      Map<String, dynamic> slot, bool value) async {
    try {
      await supabase
          .from('pool_fixed_slot_times')
          .update({'visible': value})
          .eq('pool_id', _selectedPoolId!)
          .eq('day_of_week_int', slot['day_of_week_int'])
          .eq('slot_time', slot['slot_time']);
      await _loadPoolData(_selectedPoolId!);
    } catch (_) {
      _snack("Couldn't update visibility — please try again.");
    }
  }

  Future<void> _deleteSlot(
      Map<String, dynamic> slot, String dayName) async {
    final slotTime = _displayTime(slot['slot_time'] as String);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Delete Slot Time'),
        content:
            Text('Delete slot $slotTime on $dayName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase
          .from('pool_fixed_slot_times')
          .delete()
          .eq('pool_id', _selectedPoolId!)
          .eq('day_of_week_int', slot['day_of_week_int'])
          .eq('slot_time', slot['slot_time']);
      await _loadPoolData(_selectedPoolId!);
    } catch (_) {
      _snack("Couldn't delete slot — please try again.");
    }
  }

  Future<void> _showAddSlotDialog(int dayInt) async {
    final dayName = _dayNames[dayInt] ?? 'Day';
    TimeOfDay? selectedTime;
    String? err;

    final halfHourTimes = [
      for (int h = 0; h < 24; h++) ...[
        TimeOfDay(hour: h, minute: 0),
        TimeOfDay(hour: h, minute: 30),
      ]
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: BrandColors.background,
          title: Text('Add Slot Time — $dayName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField2<TimeOfDay>(
                isExpanded: true,
                value: selectedTime,
                decoration: _fieldDecoration('Slot time *'),
                items: halfHourTimes
                    .map((t) => DropdownMenuItem<TimeOfDay>(
                          value: t,
                          child: Text(
                              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'),
                        ))
                    .toList(),
                dropdownStyleData: const DropdownStyleData(
                  maxHeight: 300,
                  decoration:
                      BoxDecoration(color: BrandColors.background),
                ),
                menuItemStyleData:
                    const MenuItemStyleData(height: 32),
                onChanged: (v) => setLocal(() => selectedTime = v),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: TextStyle(
                          color: BrandColors.red, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedTime == null) {
                  setLocal(() => err = 'Select a slot time.');
                  return;
                }
                if (selectedTime!.minute != 0 &&
                    selectedTime!.minute != 30) {
                  setLocal(() => err =
                      'Slot time must be on the hour or half hour.');
                  return;
                }
                try {
                  final slotStr = _formatTimeOfDay(selectedTime!);
                  await supabase
                      .from('pool_fixed_slot_times')
                      .insert({
                    'pool_id': _selectedPoolId,
                    'day_of_week_int': dayInt,
                    'day_of_week_text': _dayNames[dayInt],
                    'slot_time': slotStr,
                    'visible': true,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadPoolData(_selectedPoolId!);
                } on PostgrestException catch (e) {
                  setLocal(() => err = _friendlyDbError(e));
                } catch (_) {
                  setLocal(() =>
                      err = "Couldn't save — please try again.");
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Slot Availability:',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            width: 400,
            child: DropdownButtonFormField2<String?>(
              isExpanded: true,
              value: _filterSiteId,
              decoration: _fieldDecoration('Filter by site'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All sites'),
                ),
                ..._availableSites.map((s) => DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.name,
                          overflow: TextOverflow.ellipsis),
                    )),
              ],
              dropdownStyleData: const DropdownStyleData(
                maxHeight: 300,
                decoration:
                    BoxDecoration(color: BrandColors.background),
              ),
              menuItemStyleData:
                  const MenuItemStyleData(height: 32),
              onChanged: (v) {
                setState(() {
                  _filterSiteId = v;
                  _selectedPoolId = null;
                  _operatingHours = [];
                  _fixedSlots = [];
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 400,
            child: DropdownButtonFormField2<String>(
              isExpanded: true,
              value: _selectedPoolId,
              decoration: _fieldDecoration('Select pool'),
              items: _filteredPools.map((p) {
                final formattedPoolName =
                    _formatPoolName(p['pool_name'] as String? ?? '');
                final siteName =
                    p['sites']?['site_name'] as String? ?? '—';
                return DropdownMenuItem<String>(
                  value: p['pool_id'].toString(),
                  child: Text('$formattedPoolName — $siteName',
                      overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              dropdownStyleData: const DropdownStyleData(
                maxHeight: 300,
                decoration:
                    BoxDecoration(color: BrandColors.background),
              ),
              menuItemStyleData:
                  const MenuItemStyleData(height: 32),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedPoolId = v);
                _loadPoolData(v);
              },
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedPoolId == null)
            const Text('Select a pool above to view its slot configuration.')
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Operating hours ──
                    const Text('Pool Operating Hours',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_loadingHours)
                      const CircularProgressIndicator()
                    else
                      _buildOperatingHoursGrid(),
                    const SizedBox(height: 32),

                    // ── Fixed slot times ──
                    const Text('Pool Fixed Slot Times',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_selectedStrategy != 'fixed_times')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.grey.shade300),
                        ),
                        child: Text(
                          "Fixed slot times only apply to pools using the 'fixed_times' strategy. "
                          "This pool uses '$_selectedStrategy'.",
                          style: TextStyle(
                              color: Colors.grey.shade600),
                        ),
                      )
                    else if (_loadingSlots)
                      const CircularProgressIndicator()
                    else
                      _buildFixedSlotsGrid(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOperatingHoursGrid() {
    final hoursMap = <int, Map<String, dynamic>>{};
    for (final h in _operatingHours) {
      hoursMap[h['day_of_week_int'] as int] = h;
    }
    return Column(
      children: _dayOrder.map((dayInt) {
        final dayName = _dayNames[dayInt] ?? 'Day';
        final existing = hoursMap[dayInt];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                  width: 100,
                  child: Text(dayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500))),
              if (existing != null) ...[
                Expanded(
                  child: Text(
                    '${_displayTime(existing['open_time'] as String)}  –  ${_displayTime(existing['close_time'] as String)}',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  color: BrandColors.orange,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () => _showHoursDialog(
                      existing: existing, dayInt: dayInt),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: BrandColors.red,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: () =>
                      _deleteHours(dayInt, dayName),
                ),
              ] else ...[
                Expanded(
                    child: Text('Not configured',
                        style: TextStyle(
                            color: Colors.grey.shade500))),
                TextButton(
                  onPressed: () =>
                      _showHoursDialog(dayInt: dayInt),
                  child: const Text('Add'),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFixedSlotsGrid() {
    final slotsByDay = <int, List<Map<String, dynamic>>>{};
    for (final s in _fixedSlots) {
      final d = s['day_of_week_int'] as int;
      slotsByDay.putIfAbsent(d, () => []).add(s);
    }
    return Column(
      children: _dayOrder.map((dayInt) {
        final dayName = _dayNames[dayInt] ?? 'Day';
        final slots = slotsByDay[dayInt] ?? [];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 12),
            title: Text('$dayName (${slots.length} slot${slots.length == 1 ? '' : 's'})'),
            children: [
              ...slots.map((s) {
                final slotTime =
                    _displayTime(s['slot_time'] as String);
                final visible = s['visible'] as bool? ?? true;
                return ListTile(
                  dense: true,
                  title: Text(slotTime),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Visible',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600)),
                      Switch(
                        value: visible,
                        onChanged: (v) =>
                            _toggleSlotVisible(s, v),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        color: BrandColors.red,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 28, minHeight: 28),
                        onPressed: () =>
                            _deleteSlot(s, dayName),
                      ),
                    ],
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add slot time'),
                    onPressed: () =>
                        _showAddSlotDialog(dayInt),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — OPERATING HOURS
// ═══════════════════════════════════════════════════════════════════════════════

class _OperatingHoursTab extends StatefulWidget {
  const _OperatingHoursTab();

  @override
  State<_OperatingHoursTab> createState() => _OperatingHoursTabState();
}

class _OperatingHoursTabState extends State<_OperatingHoursTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sites = [];
  int? _selectedSiteId;
  bool _loadingHours = false;
  String? _hoursError;
  List<Map<String, dynamic>> _hours = [];

  @override
  void initState() {
    super.initState();
    _loadSites();
  }

  Future<void> _loadSites() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await withRetry(() => supabase
          .from('sites')
          .select('site_id, site_name')
          .eq('active', true)
          .order('site_name'));
      if (!mounted) return;
      setState(() {
        _sites = List<Map<String, dynamic>>.from(result);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load sites — please try again";
      });
    }
  }

  Future<void> _loadHours(int siteId) async {
    setState(() { _loadingHours = true; _hoursError = null; _hours = []; });
    try {
      final result = await withRetry(() => supabase
          .from('site_operating_hours')
          .select(
              'site_id, day_of_week_int, day_of_week_text, open_time, close_time')
          .eq('site_id', siteId));
      if (!mounted) return;
      setState(() {
        _hours = List<Map<String, dynamic>>.from(result);
        _loadingHours = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHours = false;
        _hoursError = "Couldn't load operating hours — $e";
      });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showHoursDialog(
      {Map<String, dynamic>? existing, required int dayInt}) async {
    final dayName = _dayNames[dayInt] ?? 'Day';
    TimeOfDay open = existing != null
        ? _parseTime(existing['open_time'] as String)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay close = existing != null
        ? _parseTime(existing['close_time'] as String)
        : const TimeOfDay(hour: 17, minute: 0);
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: BrandColors.background,
          title: Text(
              '${existing != null ? 'Edit' : 'Add'} Hours — $dayName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Open time')),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: open,
                      );
                      if (picked != null) setLocal(() => open = picked);
                    },
                    child: Text(
                        '${open.hour.toString().padLeft(2, '0')}:${open.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              Row(
                children: [
                  const Expanded(child: Text('Close time')),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: close,
                      );
                      if (picked != null)
                        setLocal(() => close = picked);
                    },
                    child: Text(
                        '${close.hour.toString().padLeft(2, '0')}:${close.minute.toString().padLeft(2, '0')}'),
                  ),
                ],
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: TextStyle(
                          color: BrandColors.red, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final openMins = open.hour * 60 + open.minute;
                final closeMins = close.hour * 60 + close.minute;
                if (closeMins <= openMins) {
                  setLocal(() =>
                      err = 'Close time must be after open time.');
                  return;
                }
                try {
                  if (existing != null) {
                    await supabase
                        .from('site_operating_hours')
                        .update({
                          'open_time': _formatTimeOfDay(open),
                          'close_time': _formatTimeOfDay(close),
                        })
                        .eq('site_id', _selectedSiteId!)
                        .eq('day_of_week_int', dayInt);
                  } else {
                    await supabase
                        .from('site_operating_hours')
                        .insert({
                      'site_id': _selectedSiteId,
                      'day_of_week_int': dayInt,
                      'day_of_week_text': _dayNames[dayInt],
                      'open_time': _formatTimeOfDay(open),
                      'close_time': _formatTimeOfDay(close),
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadHours(_selectedSiteId!);
                } on PostgrestException catch (e) {
                  setLocal(() => err = _friendlyDbError(e));
                } catch (_) {
                  setLocal(() =>
                      err = "Couldn't save — please try again.");
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHours(int dayInt, String dayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Delete Operating Hours'),
        content: Text('Delete hours for $dayName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase
          .from('site_operating_hours')
          .delete()
          .eq('site_id', _selectedSiteId!)
          .eq('day_of_week_int', dayInt);
      await _loadHours(_selectedSiteId!);
    } catch (_) {
      _snack("Couldn't delete hours — please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Operating Hours:',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          SizedBox(
            width: 340,
            child: DropdownButtonFormField2<int>(
              isExpanded: true,
              value: _selectedSiteId,
              decoration: _fieldDecoration('Select site'),
              items: _sites
                  .map((s) => DropdownMenuItem<int>(
                        value: s['site_id'] as int,
                        child: Text(s['site_name'] as String,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              dropdownStyleData: const DropdownStyleData(
                maxHeight: 260,
                decoration:
                    BoxDecoration(color: BrandColors.background),
              ),
              menuItemStyleData:
                  const MenuItemStyleData(height: 32),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedSiteId = v);
                _loadHours(v);
              },
            ),
          ),
          const SizedBox(height: 24),
          if (_selectedSiteId == null)
            const Text('Select a site above to view operating hours.')
          else if (_loadingHours)
            const Center(child: CircularProgressIndicator())
          else if (_hoursError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _hoursError!,
                style: TextStyle(color: BrandColors.red),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: _dayOrder.map((dayInt) {
                    final dayName = _dayNames[dayInt] ?? 'Day';
                    final hoursMap = <int, Map<String, dynamic>>{};
                    for (final h in _hours) {
                      hoursMap[h['day_of_week_int'] as int] = h;
                    }
                    final existing = hoursMap[dayInt];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(dayName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ),
                          if (existing != null) ...[
                            Expanded(
                              child: Text(
                                '${_displayTime(existing['open_time'] as String)}  –  ${_displayTime(existing['close_time'] as String)}',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              color: BrandColors.orange,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              onPressed: () => _showHoursDialog(
                                  existing: existing,
                                  dayInt: dayInt),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              color: BrandColors.red,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 28, minHeight: 28),
                              onPressed: () =>
                                  _deleteHours(dayInt, dayName),
                            ),
                          ] else ...[
                            Expanded(
                              child: Text('Not configured',
                                  style: TextStyle(
                                      color: Colors.grey.shade500)),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _showHoursDialog(dayInt: dayInt),
                              child: const Text('Add'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
