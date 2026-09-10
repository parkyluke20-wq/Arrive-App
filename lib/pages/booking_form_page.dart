import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';
import '../controllers/booking_controller.dart';
import '../services/booking_service.dart';
import '../services/supabase_service.dart';
import '../services/user_session.dart';
import '../widgets/packing_list_widget.dart';
import '../widgets/booking_activity_panel.dart';

// ---------------- MODELS ----------------

class CustomerOption {
  final int customerId;
  final String name;
  CustomerOption({required this.customerId, required this.name});
}

class SiteOption {
  final int siteId;
  final String label;
  SiteOption({required this.siteId, required this.label});
}

class VehicleTypeOption {
  final int vehicleTypeId;
  final String name;
  final int slotUnitsRequired;
  final String loadType;

  VehicleTypeOption({
    required this.vehicleTypeId,
    required this.name,
    required this.slotUnitsRequired,
    required this.loadType,
  });
}

// ---------------- PAGE ----------------
enum BookingFormMode { create, edit, view }

class BookingFormPage extends StatefulWidget {
  final BookingFormMode mode;
  final String? returnRoute;

  const BookingFormPage({
    super.key,
    this.mode = BookingFormMode.create,
    this.returnRoute,
  });

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  late BookingFormMode mode;
  bool get isView => mode == BookingFormMode.view;
  bool get isEdit => mode == BookingFormMode.edit;
  bool get isCreate => mode == BookingFormMode.create;
  late final BookingController bookingController;
  late final BookingService bookingService;

  // ---- text fields ----
  final referenceController = TextEditingController();
  final carrierController = TextEditingController();
  final vehicleRegController = TextEditingController();
  final containerController = TextEditingController();
  final qtyPalletsController = TextEditingController();
  final dateController = TextEditingController();
  final _commentController = TextEditingController();
  final _customerSearchCtrl = TextEditingController();

  List<PlatformFile> _packingListFiles = [];
  bool _hasExistingPackingLists = false;
  Key _packingListKey = UniqueKey();
  String? editingBookingId;
  String? _bookingRef;
  bool _didLoadRouteArgs = false;
  bool loading = true;
  String? bookingStatus;
  String? _effectiveRole;

  bool get _canUpdateStatus =>
      _effectiveRole == 'internal_admin' || _effectiveRole == 'internal_user';
  String? _reportToPool;
  final _activityPanelKey = GlobalKey<BookingActivityPanelState>();

  // ---- reference data ----
  List<CustomerOption> customers = [];
  List<SiteOption> sites = [];
  List<VehicleTypeOption> vehicleTypes = [];

  // ---------------- INIT ----------------


  @override
  void initState() {
    super.initState();
    mode = widget.mode;
    referenceController.addListener(_refreshConfirmState);
    carrierController.addListener(_refreshConfirmState);
    qtyPalletsController.addListener(_refreshConfirmState);
    bookingController = BookingController(supabase: supabase);
    bookingService = BookingService(supabase);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadRouteArgs) return;
    _didLoadRouteArgs = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
        if (args != null && args['mode'] != null) {
          mode = args['mode'];
        }

    if (args != null && args['booking_id'] != null) {
      editingBookingId = args['booking_id'];

      // Only set edit if not explicitly view
      if (mode != BookingFormMode.view) {
        mode = BookingFormMode.edit;
      }
    }

    _init();
  }

    // ---------------- DECORATIONS ----------------

  InputDecoration _denseDecoration(String label) {
      return InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      );
    }

    InputDecoration _desktopDropdownDecoration(String label) {
      return InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      );
    }

  Future<void> _resolveReportToPool() async {
    final customerId = bookingController.selectedCustomer;
    final siteId = bookingController.selectedSite;
    final vehicleType = bookingController.selectedVehicleType;

    if (customerId == null || siteId == null || vehicleType == null) {
      if (mounted) setState(() => _reportToPool = null);
      return;
    }

    try {
      final eligibleRows = await supabase
          .from('eligible_capacity_pools')
          .select('pool_id')
          .eq('customer_id', customerId)
          .eq('site_id', siteId)
          .eq('load_type', vehicleType.loadType)
          .eq('is_allowed', true);

      final eligibleIds =
          eligibleRows.map((r) => r['pool_id'].toString()).toList();

      if (eligibleIds.isEmpty) {
        if (mounted) setState(() => _reportToPool = null);
        return;
      }

      final poolRows = await supabase
          .from('capacity_pools')
          .select('display_name')
          .inFilter('pool_id', eligibleIds)
          .eq('active', true)
          .order('priority', ascending: false)
          .limit(1);

      if (!mounted) return;

      if (poolRows.isEmpty) {
        setState(() => _reportToPool = null);
        return;
      }

      setState(() => _reportToPool = poolRows.first['display_name'].toString());
    } catch (_) {
      if (mounted) setState(() => _reportToPool = null);
    }
  }

  Future<void> _init() async {
    await Future.wait([
      _loadCustomers(),
      _loadVehicleTypes(),
    ]);

    try {
      _effectiveRole = await UserSession.instance.getRole();
    } catch (_) {}

    if (editingBookingId != null) {
      try {
        final row = await supabase
            .from('bookings')
            .select(
              'booking_id, booking_ref, customer_id, site_id, vehicle_type_id, '
              'pool_id, start_time, end_time, reference, carrier, vehicle_reg, '
              'container_number, qty_pallets, qty_cases, booking_date, status'
            )
            .eq('booking_id', editingBookingId!)
            .single();

        // ---- check for existing packing lists ----
        final existingPLs = await supabase
            .from('booking_packing_lists')
            .select('id')
            .eq('booking_id', editingBookingId!)
            .limit(1);
        _hasExistingPackingLists = existingPLs.isNotEmpty;
        _packingListFiles = [];
        bookingStatus = row['status'];
        _bookingRef = row['booking_ref']?.toString();

        // ---- restore site list first ----
        await _loadSitesForCustomer(row['customer_id']);

        // ---- restore controller state ----
        bookingController.selectedCustomer = row['customer_id'];
        bookingController.selectedSite = row['site_id'];

        bookingController.selectedVehicleType = vehicleTypes.firstWhere(
          (v) => v.vehicleTypeId == row['vehicle_type_id'],
        );

        final DateTime storedStart =
            DateTime.parse(row['start_time']).toLocal();

        final DateTime restoredDate = DateTime(
          storedStart.year,
          storedStart.month,
          storedStart.day,
        );

        bookingController.selectedDate = restoredDate;
        bookingController.selectedStartTime = storedStart;

        // Pull real availability for this date, same as create mode, so the
        // Time dropdown offers every open slot instead of just the stored one.
        // computeStartTimes() re-inserts selectedStartTime at index 0 if the
        // fetched list doesn't contain it, so the booking's current slot stays
        // selectable even if slot_availability_projection doesn't independently
        // mark it "available" (see note on self-exclusion below).
        await bookingController.computeStartTimes();

        // Restore pool mapping so selectedPoolId is correct when saving.
        // Applied AFTER computeStartTimes(), because that call replaces the
        // whole pool map with the query results — if the view doesn't exclude
        // this booking's own row and reports its slot as taken, it won't be in
        // that map, and this restores it so saving still uses the right pool.
        final restoredPoolId = row['pool_id']?.toString();
        if (restoredPoolId != null) {
          bookingController.restorePoolForTime(storedStart, restoredPoolId);
        }

        bookingController.notifyListeners();

        // ---- restore text fields ----
        referenceController.text = row['reference'] ?? '';
        carrierController.text = row['carrier'] ?? '';
        vehicleRegController.text = row['vehicle_reg'] ?? '';
        containerController.text = row['container_number'] ?? '';

        if (row['qty_pallets'] != null) {
          qtyPalletsController.text = row['qty_pallets'].toString();
        } else if (row['qty_cases'] != null) {
          qtyPalletsController.text = row['qty_cases'].toString();
        }

        dateController.text = DateFormat('dd/MM/yyyy').format(restoredDate);

        await _resolveReportToPool();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load booking — please try again")),
        );
      }
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  // ---------------- DATA LOAD ----------------

  Future<void> _loadCustomers() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired, please log in again')),
        );
      }
      return;
    }

    try {
      final roles = await supabase
          .from('user_roles')
          .select('scope_type, scope_type_id')
          .eq('user_id', user.id);

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

      List<Map<String, dynamic>> rows;
      if (isGlobal) {
        rows = await supabase
            .from('customers')
            .select('customer_id, customer_name')
            .eq('active', true)
            .order('customer_name');
      } else {
        // If site scoped → derive customers from customer_sites
        if (siteIds.isNotEmpty) {
          final cs = await supabase
              .from('customer_sites')
              .select('customer_id')
              .inFilter('site_id', siteIds.toList());
          customerIds.addAll(
            cs.map((r) => r['customer_id'] as int),
          );
        }
        if (customerIds.isEmpty) {
          rows = [];
        } else {
          rows = await supabase
              .from('customers')
              .select('customer_id, customer_name')
              .inFilter('customer_id', customerIds.toList())
              .eq('active', true)
              .order('customer_name');
        }
      }

      customers = rows
          .map((c) => CustomerOption(
                customerId: c['customer_id'],
                name: c['customer_name'],
              ))
          .toList();

      // ---- AUTO SELECT IF ONLY ONE CUSTOMER ----
      if (customers.length == 1) {
        final singleCustomerId = customers.first.customerId;

        await bookingController.selectCustomer(singleCustomerId);
        await _loadSitesForCustomer(singleCustomerId);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load customers — please try again")),
      );
    }
  }


  Future<void> _loadSitesForCustomer(int customerId) async {
    try {
      final cs = await supabase
          .from('customer_sites')
          .select('site_id')
          .eq('customer_id', customerId);

      final siteIds = cs.map((r) => r['site_id']).toList();

      if (siteIds.isEmpty) {
        sites = [];
        return;
      }

      final rows = await supabase
          .from('sites')
          .select('site_id, site_name, site_address')
          .inFilter('site_id', siteIds)
          .eq('active', true)
          .order('site_name');

      sites = rows
          .map((s) => SiteOption(
                siteId: s['site_id'],
                label: '${s['site_name']} – ${s['site_address']}',
              ))
          .toList();

      // ---- AUTO SELECT IF ONLY ONE SITE ----
      if (sites.length == 1) {
        await bookingController.selectSite(sites.first.siteId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load sites — please try again")),
      );
    }
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final rows = await supabase
          .from('vehicle_types')
          .select('vehicle_type_id, name, slot_units_required, load_type')
          .eq('active', true)
          .order('name');

      vehicleTypes = rows
          .map((v) => VehicleTypeOption(
                vehicleTypeId: v['vehicle_type_id'],
                name: v['name'],
                slotUnitsRequired: v['slot_units_required'],
                loadType: v['load_type'],
              ))
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load vehicle types — please try again")),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: bookingController,
      builder: (context, _) {
        return AppScaffold(
          title: 'Booking Form',
          body: Padding(
            padding: const EdgeInsets.all(24),

            child: loading
                ? const Center(child: CircularProgressIndicator())

                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // 🔹 LEFT: FORM
                      Expanded(
                        flex: 3,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _sectionTitle('Booking Slot'),

                                    Row(
                                      children: [
                                        if (!isCreate)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.close, size: 18),
                                          label: const Text('Close'),
                                          onPressed: _handleClose,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: BrandColors.red,
                                            foregroundColor: BrandColors.charcoal,
                                          ),
                                        ),
                                        if (editingBookingId != null) const SizedBox(width: 12),
                                        if (editingBookingId != null) ...[
                                          if (isView &&
                                              bookingStatus != 'received' &&
                                              bookingStatus != 'cancelled')
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.edit, size: 18),
                                              label: const Text('Edit'),
                                              onPressed: _switchToEditMode,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: BrandColors.orange,
                                                foregroundColor: BrandColors.darkcharcoal,
                                              ),
                                            ),

                                          if (isView &&
                                              _canUpdateStatus &&
                                              bookingStatus != 'received' &&
                                              bookingStatus != 'cancelled' &&
                                              bookingStatus != 'draft') ...[
                                            const SizedBox(width: 12),
                                            ElevatedButton.icon(
                                              icon: const Icon(Icons.check_circle_outline, size: 18),
                                              label: const Text('Update Status'),
                                              onPressed: _openUpdateStatusDialog,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green.shade50,
                                                foregroundColor: Colors.green,
                                              ),
                                            ),
                                          ],

                                          const SizedBox(width: 12),

                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.comment, size: 18),
                                            label: const Text('Comment'),
                                            onPressed: () => _activityPanelKey.currentState?.addComment(),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.blue.shade50,
                                              foregroundColor: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                _customerDropdown(),
                                const SizedBox(height: 16),

                                Row(
                                  children: [
                                    Expanded(child: _siteDropdown()),
                                    const SizedBox(width: 24),
                                    Expanded(child: _dateField()),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  children: [
                                    Expanded(child: _vehicleDropdown()),
                                    const SizedBox(width: 24),
                                    Expanded(child: _timeDropdown()),
                                  ],
                                ),

                                if (_reportToPool != null) ...[
                                  const SizedBox(height: 16),
                                  InputDecorator(
                                    decoration: _denseDecoration('Report To'),
                                    child: Text(
                                      _reportToPool!,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 32),
                                _sectionTitle('Booking Details'),
                                const SizedBox(height: 20),

                                Row(
                                  children: [
                                    Expanded(child: _deliveryReferenceField()),
                                    const SizedBox(width: 24),
                                    Expanded(child: _carrierField()),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  children: [
                                    Expanded(child: _qtyPallets()),
                                    const SizedBox(width: 24),
                                    Expanded(child: _vehicleReg()),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _container()),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: PackingListWidget(
                                        key: _packingListKey,
                                        bookingId: editingBookingId,
                                        isView: isView,
                                        supabase: supabase,
                                        onChanged: (files) => setState(() {
                                          _packingListFiles = files;
                                        }),
                                      ),
                                    ),
                                  ],
                                ),

                                if (isCreate) ...[
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _commentController,
                                    maxLines: 4,
                                    minLines: 3,
                                    decoration: _denseDecoration('Add a comment (optional)'),
                                  ),
                                ],

                                const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              ),
                              _actionButtons(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 24),

                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isCreate && _bookingRef != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Booking Ref: ',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _bookingRef!,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          color: Color(0xFF1558D6),
                                          decoration: TextDecoration.underline,
                                          decorationColor: Color(0xFF1558D6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: (!isCreate && _bookingRef != null) ? 0 : 48,
                                ),
                                child: BookingActivityPanel(
                                  key: _activityPanelKey,
                                  bookingId: editingBookingId,
                                  supabase: supabase,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
  // ---------------- DROPDOWNS ----------------

  Widget _customerDropdown() {
    customers.sort((a, b) => a.name.compareTo(b.name));

    return DropdownButtonFormField2<int>(
      isExpanded: true,
      value: bookingController.selectedCustomer,
      decoration: _denseDecoration('Customer *'),
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
        searchMatchFn: (item, searchValue) {
          final customer = customers.firstWhere(
            (c) => c.customerId == item.value,
            orElse: () => CustomerOption(customerId: -1, name: ''),
          );
          return customer.name
              .toLowerCase()
              .contains(searchValue.toLowerCase());
        },
      ),
      onMenuStateChange: (isOpen) {
        if (!isOpen) _customerSearchCtrl.clear();
      },
      items: customers
          .map((c) => DropdownMenuItem(
                value: c.customerId,
                child: Text(c.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(
        maxHeight: 320,
        decoration: BoxDecoration(color: BrandColors.background),
      ),
      menuItemStyleData: const MenuItemStyleData(height: 36),
      onChanged: isView ? null : (v) async {
        await bookingController.selectCustomer(v);
        sites.clear();
        dateController.clear();
        _packingListFiles = [];
        _hasExistingPackingLists = false;
        _packingListKey = UniqueKey();
        _reportToPool = null;
        if (v != null) {
          await _loadSitesForCustomer(v);
        }
        setState(() {});
      },
    );
  }

  Widget _siteDropdown() {
    sites.sort((a, b) => a.label.compareTo(b.label));

    return DropdownButtonFormField2<int>(
      isExpanded: true,
      value: bookingController.selectedSite,
      decoration: _denseDecoration('Delivery Site *'),
      items: sites
          .map((s) => DropdownMenuItem(
                value: s.siteId,
                child: Text(s.label, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(maxHeight: 260, decoration: BoxDecoration(color: BrandColors.background)),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: isView ? null : (v) async {
        await bookingController.selectSite(v);
        await _resolveReportToPool();
      },
    );
  }

  Widget _vehicleDropdown() {
    vehicleTypes.sort((a, b) => a.name.compareTo(b.name));

    return DropdownButtonFormField2<VehicleTypeOption>(
      isExpanded: true,
      value: bookingController.selectedVehicleType,
      decoration: _denseDecoration('Delivery Type *'),
      items: vehicleTypes
          .map((v) => DropdownMenuItem(
                value: v,
                child: Text(v.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(maxHeight: 260, decoration: BoxDecoration(color: BrandColors.background)),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: isView ? null : (v) async {
        await bookingController.selectVehicleType(v);
        bookingController.clearSelectedDateAndTime();
        dateController.clear();
        qtyPalletsController.clear();
        await _resolveReportToPool();
      },
    );
  }

  Widget _timeDropdown() {
    final selected = bookingController.selectedStartTime;
    final times = bookingController.availableStartTimes
        .where((t) =>
            bookingController.isSlotVisible(t) ||
            (selected != null && t.isAtSameMomentAs(selected)))
        .toList();

    return DropdownButtonFormField2<DateTime>(
      isExpanded: true,
      value: bookingController.selectedStartTime,
      decoration: _denseDecoration('Time *'),
      items: times
          .map((t) => DropdownMenuItem(
                value: t,
                child: Text(
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 13),
                ),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(maxHeight: 260, decoration: BoxDecoration(color: BrandColors.background)),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: isView ? null : bookingController.selectStartTime,
    );
  }

  // ---------------- OTHER FIELDS ----------------

  Widget _sectionTitle(String text) =>
      Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold));

  Widget _dateField() {
    final enabled =
        bookingController.selectedCustomer != null &&
        bookingController.selectedSite != null &&
        bookingController.selectedVehicleType != null;

    return InkWell(
      onTap: (!enabled || isView)
          ? null
          : () async {
              if (!isView) {
                await bookingController.computeBookableDates();
              }
              if (bookingController.bookableDates.isEmpty) {
                return;
              }

              // IMPORTANT: derive dates from availability, not DateTime.now()
              final dates = bookingController.bookableDates
                  .map((d) => DateTime(d.year, d.month, d.day)) // normalise
                  .toList()
                ..sort();

              final firstDate = dates.first;
              final lastDate = dates.last;

              final picked = await showDatePicker(
                context: context,
                initialDate: firstDate,
                firstDate: firstDate,
                lastDate: lastDate,
                selectableDayPredicate: (d) {
                  return bookingController.bookableDates.any(
                    (b) =>
                        b.year == d.year &&
                        b.month == d.month &&
                        b.day == d.day,
                  );
                },
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
                await bookingController.pickDate(picked);
                dateController.text =
                    '${picked.day}/${picked.month}/${picked.year}';
              }
            },
      child: IgnorePointer(
      child: TextField(
        controller: dateController,
        readOnly: true,
        showCursor: false,
        decoration: const InputDecoration(
          labelText: 'Date *',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      ),
    );
  }


  Widget _deliveryReferenceField() => TextField(
    controller: referenceController,
    readOnly: isView,
    showCursor: !isView,
    decoration: _desktopDropdownDecoration('Delivery Reference *'),
    inputFormatters: [LengthLimitingTextInputFormatter(100)],
  );

  Widget _carrierField() => TextField(
    controller: carrierController,
    readOnly: isView,
    showCursor: !isView,
    decoration: _desktopDropdownDecoration('Carrier *'),
    inputFormatters: [LengthLimitingTextInputFormatter(100)],
  );

  Widget _qtyPallets() {
    final loadType = bookingController.selectedVehicleType?.loadType;
    final label =
        loadType == 'container' ? 'Qty Cases *' : 'Qty Pallets *';
    return TextField(
      controller: qtyPalletsController,
      readOnly: isView,
      showCursor: !isView,
      keyboardType: TextInputType.number,
      decoration: _desktopDropdownDecoration(label),
    );
  }

  Widget _vehicleReg() => TextField(
    controller: vehicleRegController,
    readOnly: isView,
    showCursor: !isView,
    decoration: _desktopDropdownDecoration('Vehicle Reg'),
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [LengthLimitingTextInputFormatter(20)],
  );

  Widget _container() => TextField(
    controller: containerController,
    readOnly: isView,
    showCursor: !isView,
    decoration: _desktopDropdownDecoration('Container Number'),
    textCapitalization: TextCapitalization.characters,
    inputFormatters: [LengthLimitingTextInputFormatter(30)],
  );

  // ---------------- ACTIONS ----------------

  Future<void> _openUpdateStatusDialog() async {
    String selectedStatus = 'received';
    DateTime? arrivalDate;
    TimeOfDay? arrivalTime;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: BrandColors.background,
          title: const Text('Update Booking Status'),
          content: StatefulBuilder(
            builder: (context, setLocalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    value: selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'received', child: Text('Received')),
                      DropdownMenuItem(value: 'no_show', child: Text('No Show')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() { selectedStatus = value; });
                    },
                  ),
                  if (selectedStatus == 'received') ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: today,
                            firstDate: today.subtract(const Duration(days: 365)),
                            lastDate: today,
                          );
                          if (picked != null) {
                            setLocalState(() { arrivalDate = picked; });
                          }
                        },
                        child: Text(
                          arrivalDate == null
                              ? 'Select Arrival Date'
                              : 'Date: ${arrivalDate!.day}/${arrivalDate!.month}/${arrivalDate!.year}',
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ElevatedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) {
                            setLocalState(() { arrivalTime = picked; });
                          }
                        },
                        child: Text(
                          arrivalTime == null
                              ? 'Select Arrival Time'
                              : 'Arrival: ${arrivalTime!.format(context)}',
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedStatus == 'received' &&
                    (arrivalDate == null || arrivalTime == null)) {
                  return;
                }

                DateTime? arrivedAt;
                if (selectedStatus == 'received') {
                  final pickedDate = arrivalDate!;
                  final pickedTime = arrivalTime!;
                  arrivedAt = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  if (arrivedAt.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Arrival time cannot be in the future")),
                    );
                    return;
                  }
                }

                try {
                  await supabase
                      .from('bookings')
                      .update({
                        'status': selectedStatus,
                        'arrived_at': arrivedAt?.toIso8601String(),
                      })
                      .eq('booking_id', editingBookingId!);

                  if (!mounted) return;

                  Navigator.pop(context);
                  setState(() => bookingStatus = selectedStatus);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Booking status updated')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Couldn't update booking status — please try again")),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _handleClose() {
    // Priority 1: return to previous page (preserves state)
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      return;
    }

    // Fallback (direct URL / no stack)
    Navigator.pushReplacementNamed(context, '/inbound-overview');
  }

  void _refreshConfirmState() {
    setState(() {});
  }

  void _switchToEditMode() {
    if (bookingStatus == 'received' || bookingStatus == 'cancelled') return;

    setState(() {
      mode = BookingFormMode.edit;
    });
  }
  String? _validateMandatoryFields() {
    final qty = int.tryParse(qtyPalletsController.text);
    if (bookingController.selectedCustomer == null) {return 'Customer is required';}
    if (bookingController.selectedSite == null) {return 'Delivery site is required';}
    if (bookingController.selectedVehicleType == null) {return 'Delivery type is required';}
    if (bookingController.selectedDate == null) {return 'Date is required';}
    if (bookingController.selectedStartTime == null) {return 'Time is required';}
    if (referenceController.text.trim().isEmpty) {return 'Delivery reference is required';}
    if (carrierController.text.trim().isEmpty) {return 'Carrier is required';}
    if (qty == null || qty <= 0) {return 'Quantity is required';}
    if (qty > 9999) {return 'Quantity cannot exceed 9999';}

    // ---- packing list validation ----
    if (!_hasExistingPackingLists && _packingListFiles.isEmpty) {
      return 'Packing list is required';
    }
    return null;
  }

  bool _canConfirmBooking() {
    final qty = int.tryParse(qtyPalletsController.text);
    final hasQty = qty != null && qty > 0;

    return bookingController.selectedCustomer != null &&
        bookingController.selectedSite != null &&
        bookingController.selectedVehicleType != null &&
        bookingController.selectedDate != null &&
        bookingController.selectedStartTime != null &&
        referenceController.text.trim().isNotEmpty &&
        carrierController.text.trim().isNotEmpty &&
        hasQty &&
        (_hasExistingPackingLists || _packingListFiles.isNotEmpty);
  }

  Future<String?> _checkCustomerDailyQuota() async {
    final vehicleType = bookingController.selectedVehicleType;

    // Only applies to pallet bookings
    if (vehicleType?.loadType != 'pallet') {
      return null;
    }

    final qty = int.tryParse(qtyPalletsController.text);
    if (qty == null || qty <= 0) {
      return null;
    }

    final customerId = bookingController.selectedCustomer;
    final siteId = bookingController.selectedSite;
    final date = bookingController.selectedDate;

    if (customerId == null || siteId == null || date == null) {
      return null;
    }

    final bookingDate =
        DateTime(date.year, date.month, date.day).toIso8601String().split('T').first;

    try {
      // 1️⃣ Get quota
      final quotaRow = await supabase
          .from('customer_daily_quota')
          .select('max_daily_pallets')
          .eq('customer_id', customerId)
          .eq('site_id', siteId)
          .maybeSingle();

      if (quotaRow == null) {
        // No quota configured = no restriction
        return null;
      }

      final maxDaily = quotaRow['max_daily_pallets'] as int;

      // 2️⃣ Get current actuals
      final actualRow = await supabase
          .from('customer_daily_pallet_actuals')
          .select('total_pallets')
          .eq('customer_id', customerId)
          .eq('site_id', siteId)
          .eq('booking_date', bookingDate)
          .maybeSingle();

      final currentTotal =
          actualRow == null ? 0 : (actualRow['total_pallets'] as int);

      // 3️⃣ If editing, subtract original qty
      int originalQty = 0;
      if (editingBookingId != null) {
        final original = await supabase
            .from('bookings')
            .select('qty_pallets')
            .eq('booking_id', editingBookingId!)
            .maybeSingle();

        if (original != null && original['qty_pallets'] != null) {
          originalQty = original['qty_pallets'] as int;
        }
      }

      final adjustedTotal = currentTotal - originalQty + qty;

      if (adjustedTotal > maxDaily) {
        final remaining = maxDaily - (currentTotal - originalQty);

        return 'Daily pallet limit exceeded. '
              'Maximum allowed: $maxDaily. '
              'Remaining available: ${remaining < 0 ? 0 : remaining}.';
      }

      return null;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't check daily quota — please try again")),
      );
      return null;
    }
  }

  Widget _actionButtons() {
    if (isView) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: Row(
        children: [

          // LEFT SIDE — Discard Changes
          SizedBox(
            width: 200,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              onPressed: _showDiscardChangesDialog,
              child: const Text('Discard Changes'),
            ),
          ),

          const Spacer(),

          // RIGHT SIDE GROUP
          if (editingBookingId != null)
            SizedBox(
              width: 200,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BrandColors.red,
                ),
                onPressed: _showCancelBookingDialog,
                child: const Text('Cancel Booking'),
              ),
            ),

          if (editingBookingId != null)
            const SizedBox(width: 16),

          SizedBox(
            width: 200,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.green,
              ),
              onPressed: _canConfirmBooking() ? _showConfirmDialog : null,
              child: Text(
                editingBookingId != null
                    ? 'Update Booking'
                    : 'Confirm Booking',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDiscardChangesDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Discard Changes'),
        content: const Text(
          'Are you sure you want to discard any changes?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // just close dialog
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _handleClose();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  void _showCancelBookingDialog() {
    if (editingBookingId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await supabase
                    .from('bookings')
                    .update({'status': 'cancelled'})
                    .eq('booking_id', editingBookingId!);

                if (!mounted) return;

                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop('cancelled');

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Booking cancelled'),
                  ),
                );

              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Couldn't cancel booking — please try again"),
                  ),
                );
              }
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  void _showConfirmDialog() {
    final pageContext = context;
    final isEditing = editingBookingId != null;

    showDialog(
      context: context,
      builder: (dialogContext) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (_, setDialogState) => AlertDialog(
            backgroundColor: BrandColors.background,
            title: Text(isEditing ? 'Update booking' : 'Confirm booking'),
            content: Text(
              isEditing
                  ? 'Are you sure you want to update the booking?'
                  : 'Are you sure you want to confirm the booking?\n\n'
                    'Once confirmed, the delivery slot will be reserved.',
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('No'),
              ),
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final validationError = _validateMandatoryFields();
                        final quotaError = await _checkCustomerDailyQuota();

                        // ---- QUOTA FAIL ----
                        if (quotaError != null) {
                          if (!mounted) return;

                          Navigator.of(dialogContext).pop(); // CLOSE POPUP

                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(content: Text(quotaError)),
                          );
                          return;
                        }

                        // ---- VALIDATION FAIL ----
                        if (validationError != null) {
                          if (!mounted) return;

                          Navigator.of(dialogContext).pop(); // CLOSE POPUP

                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            SnackBar(content: Text(validationError)),
                          );
                          return;
                        }

                        setDialogState(() => isSubmitting = true);

                        try {
                          final booking = await bookingService.confirmBooking(
                            controller: bookingController,
                            bookingId: editingBookingId,
                            vehicleTypeId:
                                bookingController.selectedVehicleType!.vehicleTypeId,
                            slotUnitsRequired:
                                bookingController.selectedVehicleType!.slotUnitsRequired,
                            reference: referenceController.text.trim(),
                            carrier: carrierController.text.trim(),
                            vehicleReg: vehicleRegController.text.trim(),
                            container: containerController.text.trim(),
                            qtyPallets:
                                bookingController.selectedVehicleType?.loadType == 'pallet' &&
                                        qtyPalletsController.text.isNotEmpty
                                    ? int.parse(qtyPalletsController.text)
                                    : null,
                            qtyCases:
                                bookingController.selectedVehicleType?.loadType == 'container' &&
                                        qtyPalletsController.text.isNotEmpty
                                    ? int.parse(qtyPalletsController.text)
                                    : null,
                            packingListFiles: _packingListFiles,
                          );
                          final bookingRef = booking['booking_ref'];

                          if (!mounted) return;

                          final comment = _commentController.text.trim();
                          if (!isEditing && comment.isNotEmpty) {
                            final user = supabase.auth.currentUser;
                            if (user != null) {
                              try {
                                await supabase.from('booking_events').insert({
                                  'booking_id': booking['booking_id'].toString(),
                                  'event_type': 'comment_added',
                                  'user_id': user.id,
                                  'audit_text': comment,
                                });
                              } catch (_) {
                                if (mounted) {
                                  ScaffoldMessenger.of(pageContext).showSnackBar(
                                    const SnackBar(
                                      content: Text('Booking confirmed. Comment could not be saved.'),
                                    ),
                                  );
                                }
                              }
                            }
                            if (!mounted) return;
                          }

                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/inbound-overview',
                            (route) => false,
                            arguments: {
                              'booking_confirmed': true,
                              'was_edit': editingBookingId != null,
                              'booking_ref': bookingRef,
                            },
                          );
                        } catch (e) {
                          if (!mounted) return;

                          setDialogState(() => isSubmitting = false);
                          Navigator.of(dialogContext).pop(); // CLOSE POPUP

                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(
                              content: Text("Couldn't confirm booking — please try again"),
                            ),
                          );
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

  @override
  void dispose() {
    referenceController.removeListener(_refreshConfirmState);
    carrierController.removeListener(_refreshConfirmState);
    qtyPalletsController.removeListener(_refreshConfirmState);
    referenceController.dispose();
    carrierController.dispose();
    vehicleRegController.dispose();
    containerController.dispose();
    qtyPalletsController.dispose();
    dateController.dispose();
    _commentController.dispose();
    _customerSearchCtrl.dispose();
    super.dispose();
  }
}
