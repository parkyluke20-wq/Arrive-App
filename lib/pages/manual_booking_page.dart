import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../layouts/app_scaffold.dart';
import '../services/supabase_service.dart';
import '../theme/brand_colors.dart';
import '../widgets/packing_list_widget.dart';

// ---------------- MODELS ----------------

class _Customer {
  final int id;
  final String name;
  _Customer(this.id, this.name);
}

class _Site {
  final int id;
  final String name;
  _Site(this.id, this.name);
}

class _VehicleType {
  final int id;
  final String name;
  final int slotUnitsRequired;
  final String loadType;
  _VehicleType(this.id, this.name, this.slotUnitsRequired, this.loadType);
}

// ---------------- PAGE ----------------

class ManualBookingPage extends StatefulWidget {
  const ManualBookingPage({super.key});

  @override
  State<ManualBookingPage> createState() => _ManualBookingPageState();
}

class _ManualBookingPageState extends State<ManualBookingPage> {
  // Reference data
  List<_Customer> _customers = [];
  List<_Site> _sites = [];
  List<_VehicleType> _vehicleTypes = [];

  // Form selections
  _Customer? _customer;
  _Site? _site;
  DateTime? _date;
  _VehicleType? _vehicleType;
  String? _startTime;

  // Text controllers
  final _carrierCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _qtyPalletsCtrl = TextEditingController();
  final _qtyCasesCtrl = TextEditingController();
  final _vehicleRegCtrl = TextEditingController();
  final _containerCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _customerSearchCtrl = TextEditingController();

  // Pool resolution state
  String? _poolId;
  bool _resolvingPool = false;
  String? _poolError;

  // Packing list
  List<PlatformFile> _packingListFiles = [];
  Key _packingListKey = UniqueKey();

  // Submit state
  bool _submitting = false;
  String? _submitError;

  bool _checking = true;
  bool _loading = true;

  static final List<String> _timeSlots = _buildTimeSlots();

  static List<String> _buildTimeSlots() {
    final slots = <String>[];
    for (int h = 6; h <= 20; h++) {
      slots.add('${h.toString().padLeft(2, '0')}:00');
      if (h < 20) slots.add('${h.toString().padLeft(2, '0')}:30');
    }
    return slots;
  }

  @override
  void initState() {
    super.initState();
    _carrierCtrl.addListener(_onFieldChanged);
    _referenceCtrl.addListener(_onFieldChanged);
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
          .select('role')
          .eq('user_id', user.id)
          .inFilter('role', ['internal_admin', 'internal_user']);
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
    _init();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  // ---------------- DATA LOAD ----------------

  Future<void> _init() async {
    await Future.wait([_loadCustomers(), _loadSites(), _loadVehicleTypes()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCustomers() async {
    try {
      final rows = await supabase
          .from('customers')
          .select('customer_id, customer_name')
          .eq('active', true)
          .order('customer_name');
      _customers =
          rows.map((r) => _Customer(r['customer_id'], r['customer_name'])).toList();
    } catch (_) {}
  }

  Future<void> _loadSites() async {
    try {
      final rows = await supabase
          .from('sites')
          .select('site_id, site_name')
          .eq('active', true)
          .order('site_name');
      _sites = rows.map((r) => _Site(r['site_id'], r['site_name'])).toList();
    } catch (_) {}
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final rows = await supabase
          .from('vehicle_types')
          .select('vehicle_type_id, name, slot_units_required, load_type')
          .eq('active', true)
          .order('name');
      _vehicleTypes = rows
          .map((r) => _VehicleType(
                r['vehicle_type_id'],
                r['name'],
                r['slot_units_required'],
                r['load_type'],
              ))
          .toList();
    } catch (_) {}
  }

  // ---------------- POOL RESOLUTION ----------------

  Future<void> _resolvePool() async {
    if (_customer == null || _site == null || _vehicleType == null) {
      if (mounted) setState(() { _poolId = null; _poolError = null; });
      return;
    }

    // 'loose' load type never uses a pool
    if (_vehicleType!.loadType == 'loose') {
      if (mounted) setState(() { _poolId = null; _poolError = null; _resolvingPool = false; });
      return;
    }

    if (mounted) setState(() { _resolvingPool = true; _poolError = null; _poolId = null; });

    try {
      // Step 1: Active pools for this site + load_type
      final poolRows = await supabase
          .from('capacity_pools')
          .select('pool_id, priority')
          .eq('site_id', _site!.id)
          .eq('load_type', _vehicleType!.loadType)
          .eq('active', true);

      if (poolRows.isEmpty) {
        if (mounted) {
          setState(() {
            _resolvingPool = false;
            _poolError = 'No eligible pool found for this customer and vehicle type.';
          });
        }
        return;
      }

      final poolIds = poolRows.map((r) => r['pool_id'].toString()).toList();

      // Step 2: All capacity_pool_customers rows for these pools
      final cpcRows = await supabase
          .from('capacity_pool_customers')
          .select('pool_id, customer_id, mode')
          .inFilter('pool_id', poolIds);

      // Steps 3 & 4: Filter pools by exclude/include rules
      final filteredPools = poolRows.where((pool) {
        final pid = pool['pool_id'].toString();
        final poolCpc =
            cpcRows.where((r) => r['pool_id'].toString() == pid).toList();

        // Step 3: Exclude if customer is explicitly excluded
        if (poolCpc.any((r) =>
            r['customer_id'] == _customer!.id && r['mode'] == 'exclude')) {
          return false;
        }

        // Step 4: If pool has include rows, customer must be in them
        final includeRows =
            poolCpc.where((r) => r['mode'] == 'include').toList();
        if (includeRows.isNotEmpty &&
            !includeRows.any((r) => r['customer_id'] == _customer!.id)) {
          return false;
        }

        return true;
      }).toList();

      if (filteredPools.isEmpty) {
        if (mounted) {
          setState(() {
            _resolvingPool = false;
            _poolError = 'No eligible pool found for this customer and vehicle type.';
          });
        }
        return;
      }

      // Step 5: Sort by priority ascending, take first
      filteredPools.sort((a, b) =>
          (a['priority'] as int).compareTo(b['priority'] as int));

      if (mounted) {
        setState(() {
          _resolvingPool = false;
          _poolId = filteredPools.first['pool_id'].toString();
          _poolError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resolvingPool = false;
          _poolError = 'Failed to resolve pool: ${e.toString()}';
        });
      }
    }
  }

  // ---------------- SUBMIT ----------------

  // Returns an error string on failure, null on success.
  Future<String?> _submit() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'Not authenticated';

    String? insertedBookingId;

    try {
      final timeParts = _startTime!.split(':');
      final startTime = DateTime(
        _date!.year, _date!.month, _date!.day,
        int.parse(timeParts[0]), int.parse(timeParts[1]),
      );
      final endTime = startTime.add(
        Duration(minutes: _vehicleType!.slotUnitsRequired * 30),
      );

      final row = await supabase.from('bookings').insert({
        'customer_id': _customer!.id,
        'site_id': _site!.id,
        'vehicle_type_id': _vehicleType!.id,
        'pool_id': _poolId,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'booking_date': DateFormat('yyyy-MM-dd').format(_date!),
        'lane_units_used': _vehicleType!.slotUnitsRequired,
        'carrier': _carrierCtrl.text.trim(),
        'reference': _referenceCtrl.text.trim(),
        'vehicle_reg': _vehicleRegCtrl.text.trim().isNotEmpty
            ? _vehicleRegCtrl.text.trim()
            : null,
        'container_number': _containerCtrl.text.trim().isNotEmpty
            ? _containerCtrl.text.trim()
            : null,
        'qty_pallets': _qtyPalletsCtrl.text.trim().isNotEmpty
            ? int.tryParse(_qtyPalletsCtrl.text.trim())
            : null,
        'qty_cases': _qtyCasesCtrl.text.trim().isNotEmpty
            ? int.tryParse(_qtyCasesCtrl.text.trim())
            : null,
        'status': 'booked',
        'created_by': user.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).select('booking_id').single();

      insertedBookingId = row['booking_id'].toString();

      // Upload packing list files
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _packingListFiles.length; i++) {
        final file = _packingListFiles[i];
        final storagePath =
            'booking_${insertedBookingId}_${ts + i}_${file.name}';

        await supabase.storage
            .from('booking-documents')
            .uploadBinary(storagePath, file.bytes!);

        await supabase.from('booking_packing_lists').insert({
          'booking_id': insertedBookingId,
          'storage_path': storagePath,
          'file_name': file.name,
          'uploaded_by': user.id,
        });
      }

      if (!mounted) return null;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual booking created')),
      );
      _clearForm();
      return null;
    } catch (e) {
      // Roll back the booking row if the packing list upload failed after insert
      if (insertedBookingId != null) {
        try {
          await supabase
              .from('bookings')
              .delete()
              .eq('booking_id', insertedBookingId);
        } catch (_) {}
      }
      return e is PostgrestException ? e.message : e.toString();
    }
  }

  void _setError(String msg) => setState(() => _submitError = msg);

  bool _canSubmit() =>
      _customer != null &&
      _site != null &&
      _date != null &&
      _vehicleType != null &&
      _startTime != null &&
      _carrierCtrl.text.trim().isNotEmpty &&
      _referenceCtrl.text.trim().isNotEmpty &&
      _packingListFiles.isNotEmpty &&
      !_resolvingPool;

  void _showConfirmDialog() {
    final pageContext = context;

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            backgroundColor: BrandColors.background,
            title: const Text('Confirm booking'),
            content: const Text(
              'Are you sure you want to confirm the booking?\n\n'
              'Once confirmed, the delivery slot will be reserved.',
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        final error = await _submit();
                        if (!mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (error != null) {
                          setState(() => _submitError = error);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Yes'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _clearForm() {
    _carrierCtrl.clear();
    _referenceCtrl.clear();
    _qtyPalletsCtrl.clear();
    _qtyCasesCtrl.clear();
    _vehicleRegCtrl.clear();
    _containerCtrl.clear();
    _dateCtrl.clear();
    _customerSearchCtrl.clear();
    setState(() {
      _customer = null;
      _site = null;
      _date = null;
      _vehicleType = null;
      _startTime = null;
      _poolId = null;
      _poolError = null;
      _resolvingPool = false;
      _submitting = false;
      _submitError = null;
      _packingListFiles = [];
      _packingListKey = UniqueKey();
    });
  }

  // ---------------- DECORATIONS ----------------

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return AppScaffold(
      title: 'Manual Booking',
      showFooter: false,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create Manual Booking',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bypasses availability rules. Use only when required.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 24),

                    // Customer (searchable)
                    _customerDropdown(),
                    const SizedBox(height: 16),

                    // Site — key forces reset when customer changes
                    _siteDropdown(),
                    const SizedBox(height: 16),

                    // Date
                    _dateField(),
                    const SizedBox(height: 16),

                    // Vehicle type
                    _vehicleTypeDropdown(),
                    const SizedBox(height: 16),

                    // Start time
                    _startTimeDropdown(),
                    const SizedBox(height: 16),

                    // Carrier
                    TextField(
                      controller: _carrierCtrl,
                      decoration: _fieldDecoration('Carrier *'),
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                    const SizedBox(height: 16),

                    // Reference
                    TextField(
                      controller: _referenceCtrl,
                      decoration: _fieldDecoration('Reference *'),
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                    ),
                    const SizedBox(height: 16),

                    // Qty pallets | Qty cases
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyPalletsCtrl,
                            decoration: _fieldDecoration('Qty Pallets'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _qtyCasesCtrl,
                            decoration: _fieldDecoration('Qty Cases'),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Vehicle reg | Container number
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _vehicleRegCtrl,
                            decoration: _fieldDecoration('Vehicle Reg'),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(20),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _containerCtrl,
                            decoration: _fieldDecoration('Container Number'),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(30),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Packing list
                    PackingListWidget(
                      key: _packingListKey,
                      isView: false,
                      supabase: supabase,
                      onChanged: (files) =>
                          setState(() => _packingListFiles = files),
                    ),

                    const SizedBox(height: 24),

                    // Pool warning (non-blocking — booking will still be created without a pool)
                    if (!_resolvingPool && _poolError != null) ...[
                      _warningBox('No pool matched — booking will be created without a pool assignment.'),
                      const SizedBox(height: 12),
                    ],

                    // Submit error (from Supabase)
                    if (_submitError != null) ...[
                      _errorBox(_submitError!),
                      const SizedBox(height: 12),
                    ],

                    // Submit area — loading indicator replaces button during pool resolution
                    if (_resolvingPool)
                      const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Resolving eligibility...'),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BrandColors.green,
                            foregroundColor: BrandColors.darkcharcoal,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _canSubmit() ? _showConfirmDialog : null,
                          child: const Text(
                            'Create Booking',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------------- FORM WIDGETS ----------------

  Widget _customerDropdown() {
    return DropdownButtonFormField2<_Customer>(
      isExpanded: true,
      value: _customer,
      decoration: _fieldDecoration('Customer *'),
      dropdownSearchData: DropdownSearchData(
        searchController: _customerSearchCtrl,
        searchInnerWidgetHeight: 52,
        searchInnerWidget: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            controller: _customerSearchCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: 'Search...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        searchMatchFn: (item, searchValue) => (item.value as _Customer)
            .name
            .toLowerCase()
            .contains(searchValue.toLowerCase()),
      ),
      onMenuStateChange: (isOpen) {
        if (!isOpen) _customerSearchCtrl.clear();
      },
      items: _customers
          .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(
        maxHeight: 320,
        decoration: BoxDecoration(color: BrandColors.background),
      ),
      menuItemStyleData: const MenuItemStyleData(height: 36),
      onChanged: (c) {
        setState(() {
          _customer = c;
          _site = null;
          _poolId = null;
          _poolError = null;
        });
        _resolvePool();
      },
    );
  }

  Widget _siteDropdown() {
    return DropdownButtonFormField2<_Site>(
      // Rebuild widget (resetting its internal state) when customer changes
      key: ValueKey('site_${_customer?.id}'),
      isExpanded: true,
      value: _site,
      decoration: _fieldDecoration('Site *'),
      items: _sites
          .map((s) => DropdownMenuItem(
                value: s,
                child: Text(s.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(
        maxHeight: 260,
        decoration: BoxDecoration(color: BrandColors.background),
      ),
      menuItemStyleData: const MenuItemStyleData(height: 36),
      onChanged: (s) {
        setState(() { _site = s; _poolId = null; _poolError = null; });
        _resolvePool();
      },
    );
  }

  Widget _vehicleTypeDropdown() {
    return DropdownButtonFormField2<_VehicleType>(
      isExpanded: true,
      value: _vehicleType,
      decoration: _fieldDecoration('Vehicle Type *'),
      items: _vehicleTypes
          .map((v) => DropdownMenuItem(
                value: v,
                child: Text(v.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(
        maxHeight: 260,
        decoration: BoxDecoration(color: BrandColors.background),
      ),
      menuItemStyleData: const MenuItemStyleData(height: 36),
      onChanged: (v) {
        setState(() { _vehicleType = v; _poolId = null; _poolError = null; });
        _resolvePool();
      },
    );
  }

  Widget _startTimeDropdown() {
    return DropdownButtonFormField2<String>(
      isExpanded: true,
      value: _startTime,
      decoration: _fieldDecoration('Start Time *'),
      items: _timeSlots
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(t, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(
        maxHeight: 320,
        decoration: BoxDecoration(color: BrandColors.background),
      ),
      menuItemStyleData: const MenuItemStyleData(height: 36),
      onChanged: (t) => setState(() => _startTime = t),
    );
  }

  Widget _dateField() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final picked = await showDatePicker(
          context: context,
          initialDate: _date ?? today,
          firstDate: today,
          lastDate: today.add(const Duration(days: 365)),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: BrandColors.background,
                    surfaceContainerHigh: BrandColors.background,
                  ),
            ),
            child: child!,
          ),
        );
        if (picked != null) {
          setState(() {
            _date = picked;
            _dateCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
          });
        }
      },
      child: IgnorePointer(
        child: TextField(
          controller: _dateCtrl,
          readOnly: true,
          showCursor: false,
          decoration: _fieldDecoration('Date *'),
        ),
      ),
    );
  }

  Widget _errorBox(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          message,
          style: TextStyle(color: Colors.red.shade800),
        ),
      );

  Widget _warningBox(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          message,
          style: TextStyle(color: Colors.amber.shade900),
        ),
      );

  // ---------------- DISPOSE ----------------

  @override
  void dispose() {
    _carrierCtrl.removeListener(_onFieldChanged);
    _referenceCtrl.removeListener(_onFieldChanged);
    _carrierCtrl.dispose();
    _referenceCtrl.dispose();
    _qtyPalletsCtrl.dispose();
    _qtyCasesCtrl.dispose();
    _vehicleRegCtrl.dispose();
    _containerCtrl.dispose();
    _dateCtrl.dispose();
    _customerSearchCtrl.dispose();
    super.dispose();
  }
}
