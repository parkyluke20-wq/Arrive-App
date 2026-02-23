import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';

class ReserveSlotsPage extends StatefulWidget {
  const ReserveSlotsPage({super.key});

  @override
  State<ReserveSlotsPage> createState() => _ReserveSlotsPageState();
}

class _ReserveSlotsPageState extends State<ReserveSlotsPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  bool loading = true;

  List<Map<String, dynamic>> sites = [];
  List<Map<String, dynamic>> pools = [];
  List<DateTime> availableSlots = [];

  int? selectedSite;
  String? selectedPool;
  DateTime? selectedDate;

  final TextEditingController dateController = TextEditingController();
  final TextEditingController reasonController = TextEditingController();

  final List<DateTime> selectedSlots = [];

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    await _checkAccess();
    await _loadSites();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _checkAccess() async {
    final user = supabase.auth.currentUser!;
    final roles = await supabase
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id)
        .inFilter('role', ['internal_admin', 'internal_user']);

    if (roles.isEmpty && mounted) {
      Navigator.pop(context);
    }
  }

  // ==========================================================
  // DATA LOADERS
  // ==========================================================

  Future<void> _loadSites() async {
    final rows = await supabase
        .from('sites')
        .select('site_id, site_name')
        .eq('active', true)
        .order('site_name');

    sites = rows;

    if (sites.length == 1) {
      selectedSite = sites.first['site_id'] as int;
      await _loadPools();
    }
  }

  Future<void> _loadPools() async {
    if (selectedSite == null) return;

    final rows = await supabase
        .from('capacity_pools')
        .select('pool_id, pool_name')
        .eq('site_id', selectedSite!)
        .eq('active', true)
        .order('pool_name');

    pools = rows;
    setState(() {});
  }

  Future<void> _loadAvailableSlots() async {
    if (selectedPool == null || selectedDate == null) return;

    final start = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
    );

    final end = start.add(const Duration(days: 1));

    final rows = await supabase
        .from('time_slot_availability')
        .select('slot_start')
        .eq('pool_id', selectedPool!)
        .eq('slot_status', 'available')
        .gte('slot_start', start.toUtc().toIso8601String())
        .lt('slot_start', end.toUtc().toIso8601String())
        .order('slot_start');

    availableSlots = rows
        .map<DateTime>((r) => DateTime.parse(r['slot_start']).toUtc())
        .toList()
      ..sort();

    selectedSlots.clear();
    setState(() {});
  }

  // ==========================================================
  // SLOT GROUPING
  // ==========================================================

  List<List<DateTime>> _groupContiguous(List<DateTime> slots) {
    slots.sort();
    final groups = <List<DateTime>>[];
    List<DateTime> current = [];

    for (final slot in slots) {
      if (current.isEmpty) {
        current.add(slot);
        continue;
      }

      final prev = current.last;

      if (slot.difference(prev) == const Duration(minutes: 30)) {
        current.add(slot);
      } else {
        groups.add(current);
        current = [slot];
      }
    }

    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  // ==========================================================
  // VALIDATION
  // ==========================================================

  bool _validate() {
    if (selectedSite == null) {
      _snack('Site is required');
      return false;
    }
    if (selectedPool == null) {
      _snack('Pool is required');
      return false;
    }
    if (selectedDate == null) {
      _snack('Date is required');
      return false;
    }
    if (selectedSlots.isEmpty) {
      _snack('Select at least one time slot');
      return false;
    }
    return true;
  }

  // ==========================================================
  // SAVE
  // ==========================================================

  Future<void> _confirmReservation() async {
    if (!_validate()) return;

    try {
      final groups = _groupContiguous(List.from(selectedSlots));
      final userId = supabase.auth.currentUser!.id;

      for (final group in groups) {
        await supabase.from('outbound_reservations').insert({
          'site_id': selectedSite,
          'pool_id': selectedPool,
          'start_time': group.first.toUtc().toIso8601String(),
          'end_time': group.last
              .add(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
          'reason': reasonController.text.trim(),
          'reserved_by': userId,
        });
      }

      if (!mounted) return;

      _snack('Reservation confirmed');

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/inbound-overview',
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _snack('Reservation failed: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ==========================================================
  // DIALOGS
  // ==========================================================

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Reservation?'),
        content: const Text(
            'Are you sure you want to confirm this reservation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _confirmReservation();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Reservation?'),
        content:
            const Text('Are you sure you want to cancel the reservation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/inbound-overview',
                (route) => false,
              );
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final timeFmt = DateFormat('HH:mm');

    return AppScaffold(
      title: 'Reserve Slots',
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reservation Details',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 24),

                      // SITE
                      _buildSiteDropdown(),
                      const SizedBox(height: 16),

                      // POOL
                      _buildPoolDropdown(),
                      const SizedBox(height: 16),

                      // DATE
                      _buildDatePicker(),
                      const SizedBox(height: 24),

                      // TIME SLOTS
                      if (selectedDate != null)
                        _buildSlotsSection(timeFmt),

                      const SizedBox(height: 16),

                      TextField(
                        controller: reasonController,
                        decoration: _decoration('Reason (optional)'),
                        maxLines: 2,
                      ),

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BrandColors.red,
                            ),
                            onPressed: _showCancelDialog,
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BrandColors.green,
                            ),
                            onPressed: _showConfirmDialog,
                            child:
                                const Text('Confirm Reservation'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ==========================================================
  // UI COMPONENTS
  // ==========================================================

  Widget _buildSiteDropdown() {
    return DropdownButtonFormField2<int>(
      value: selectedSite,
      decoration: _decoration('Site *'),
      dropdownStyleData:
          const DropdownStyleData(maxHeight: 260),
      menuItemStyleData:
          const MenuItemStyleData(height: 32),
      items: sites
          .map(
            (s) => DropdownMenuItem<int>(
              value: s['site_id'] as int,
              child: Text(
                s['site_name'] as String,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: (v) async {
        selectedSite = v;
        selectedPool = null;
        selectedDate = null;
        dateController.clear();
        await _loadPools();
        setState(() {});
      },
    );
  }

  Widget _buildPoolDropdown() {
    return DropdownButtonFormField2<String>(
      value: selectedPool,
      decoration: _decoration('Pool *'),
      dropdownStyleData:
          const DropdownStyleData(maxHeight: 260),
      menuItemStyleData:
          const MenuItemStyleData(height: 32),
      items: pools
          .map(
            (p) => DropdownMenuItem<String>(
              value: p['pool_id'] as String,
              child: Text(
                _formatPool(p['pool_name'] as String),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: selectedSite == null
          ? null
          : (v) {
              selectedPool = v;
              selectedDate = null;
              dateController.clear();
              availableSlots.clear();
              setState(() {});
            },
    );
  }

  Widget _buildDatePicker() {
    return InkWell(
      onTap: selectedPool == null
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate:
                    DateTime.now().add(const Duration(days: 90)),
              );

              if (picked != null) {
                selectedDate = picked;
                dateController.text =
                    '${picked.day}/${picked.month}/${picked.year}';
                await _loadAvailableSlots();
              }
            },
      child: IgnorePointer(
        child: TextField(
          controller: dateController,
          decoration: _decoration('Date *'),
        ),
      ),
    );
  }

  Widget _buildSlotsSection(DateFormat timeFmt) {
    if (availableSlots.isEmpty) {
      return const Text(
        'No available slots for this date',
        style: TextStyle(color: Colors.grey),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.builder(
        itemCount: availableSlots.length,
        itemBuilder: (_, index) {
          final slot = availableSlots[index];

          final label =
              '${timeFmt.format(slot)} - ${timeFmt.format(slot.add(const Duration(minutes: 30)))}';

          return Row(
            children: [
              Checkbox(
                materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(
                  horizontal: -4,
                  vertical: -4,
                ),
                value: selectedSlots.contains(slot),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      selectedSlots.add(slot);
                    } else {
                      selectedSlots.remove(slot);
                    }
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(fontSize: 13)),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _decoration(String label) =>
      const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label);

  String _formatPool(String raw) =>
      raw.split('_').map((w) =>
          w[0].toUpperCase() + w.substring(1)).join(' ');

  @override
  void dispose() {
    dateController.dispose();
    reasonController.dispose();
    super.dispose();
  }
}