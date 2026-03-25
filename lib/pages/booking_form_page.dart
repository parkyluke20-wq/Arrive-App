import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:url_launcher/url_launcher.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';
import '../controllers/booking_controller.dart';
import '../services/booking_service.dart';

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

class BookingFormPage extends StatefulWidget {
  const BookingFormPage({super.key});

  @override
  State<BookingFormPage> createState() => _BookingFormPageState();
}

class _BookingFormPageState extends State<BookingFormPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  late final BookingController bookingController;
  late final BookingService bookingService;

  // ---- text fields ----
  final referenceController = TextEditingController();
  final carrierController = TextEditingController();
  final vehicleRegController = TextEditingController();
  final containerController = TextEditingController();
  final qtyPalletsController = TextEditingController();
  final dateController = TextEditingController();

  PlatformFile? packingListFile;
  String? existingPackingListPath;
  bool packingListRemoved = false;
  String? editingBookingId;
  bool _didLoadRouteArgs = false;
  bool loading = true;

  // ---- reference data ----
  List<CustomerOption> customers = [];
  List<SiteOption> sites = [];
  List<VehicleTypeOption> vehicleTypes = [];

  // ---------------- INIT ----------------

  @override
  void initState() {
    super.initState();
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

    if (args != null && args['booking_id'] != null) {
      editingBookingId = args['booking_id'];
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

  Future<void> _init() async {
    await Future.wait([
      _loadCustomers(),
      _loadVehicleTypes(),
    ]);

    if (editingBookingId != null) {
      final row = await supabase
          .from('bookings')
          .select(
            'booking_id, customer_id, site_id, vehicle_type_id, '
            'start_time, end_time, reference, carrier, vehicle_reg, '
            'container_number, qty_pallets, qty_cases, booking_date, '
            'status, packing_list_path'
          )
          .eq('booking_id', editingBookingId!)
          .single();

      // ---- restore packing list state ----
      existingPackingListPath = row['packing_list_path'];
      packingListRemoved = false;
      packingListFile = null;

      // ---- restore site list first ----
      await _loadSitesForCustomer(row['customer_id']);

      // ---- restore controller state ----
      bookingController.selectedCustomer = row['customer_id'];
      bookingController.selectedSite = row['site_id'];

      bookingController.selectedVehicleType = vehicleTypes.firstWhere(
        (v) => v.vehicleTypeId == row['vehicle_type_id'],
      );

      final DateTime storedStart =
          DateTime.parse(row['start_time']);

      final DateTime restoredDate = DateTime(
        storedStart.year,
        storedStart.month,
        storedStart.day,
      );

      bookingController.selectedDate = restoredDate;

      bookingController.availableStartTimes
        ..clear()
        ..add(storedStart);

      bookingController.selectedStartTime = storedStart;

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

      dateController.text =
          '${restoredDate.day}/${restoredDate.month}/${restoredDate.year}';
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  // ---------------- DATA LOAD ----------------

  Future<void> _loadCustomers() async {
    final user = supabase.auth.currentUser!;

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
  }


  Future<void> _loadSitesForCustomer(int customerId) async {
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
  }

  Future<void> _loadVehicleTypes() async {
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Booking Slot'),
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
                              Expanded(child: _packingListMainButton()),
                            ],
                          ),

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              const Spacer(),
                              Expanded(
                                child: _packingListSecondaryActions(),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          _actionButtons(),

                          // 👇 prevents edge overflow on tight screens
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
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
      items: customers
          .map((c) => DropdownMenuItem(
                value: c.customerId,
                child: Text(c.name, style: const TextStyle(fontSize: 13)),
              ))
          .toList(),
      dropdownStyleData: const DropdownStyleData(maxHeight: 260),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: (v) async {
        await bookingController.selectCustomer(v);
        sites.clear();
        dateController.clear();
        packingListFile = null;
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
      dropdownStyleData: const DropdownStyleData(maxHeight: 260),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: (v) async {
        await bookingController.selectSite(v);
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
      dropdownStyleData: const DropdownStyleData(maxHeight: 260),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: (v) async {
        await bookingController.selectVehicleType(v);
        bookingController.clearSelectedDateAndTime();
        dateController.clear();
        qtyPalletsController.clear();
        await bookingController.computeBookableDates();
        setState(() {});
      },
    );
  }

  Widget _timeDropdown() {
    final times = bookingController.availableStartTimes
    .where((t) => bookingController.isSlotVisible(t))
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
      dropdownStyleData: const DropdownStyleData(maxHeight: 260),
      menuItemStyleData: const MenuItemStyleData(height: 32),
      onChanged: bookingController.selectStartTime,
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
      onTap: !enabled
          ? null
          : () async {
              await bookingController.computeBookableDates();

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
          decoration: const InputDecoration(
            labelText: 'Date *',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    );
  }


  Widget _deliveryReferenceField() =>
      TextField(controller: referenceController, decoration: _desktopDropdownDecoration('Delivery Reference *'));

  Widget _carrierField() =>
      TextField(controller: carrierController, decoration: _desktopDropdownDecoration('Carrier *'));

  Widget _qtyPallets() {
    final loadType = bookingController.selectedVehicleType?.loadType;

    final label =
        loadType == 'container' ? 'Qty Cases *' : 'Qty Pallets *';

    return TextField(
      controller: qtyPalletsController,
      keyboardType: TextInputType.number,
      decoration: _desktopDropdownDecoration(label),
    );
  }

  Widget _vehicleReg() =>
      TextField(controller: vehicleRegController, decoration: _desktopDropdownDecoration('Vehicle Reg'));

  Widget _container() =>
      TextField(controller: containerController, decoration: _desktopDropdownDecoration('Container Number'));

  Widget _packingListMainButton() {
    final hasExisting =
        existingPackingListPath != null && !packingListRemoved;

    final hasNew = packingListFile != null;

    String label;

    if (hasNew) {
      label = packingListFile!.name;
    } else if (hasExisting) {
      label = 'Replace Packing List';
    } else {
      label = 'Upload Packing List';
    }

    return SizedBox(
      height: 44, // matches TextField visual height
      child: OutlinedButton.icon(
        icon: const Icon(Icons.upload_file, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4), // same as OutlineInputBorder default
          ),
        ),
        onPressed: () async {
          final result =
              await FilePicker.platform.pickFiles(withData: true);

          if (result != null) {
            setState(() {
              packingListFile = result.files.first;
              packingListRemoved = false;
            });
          }
        },
      ),
    );
  }

  Widget _packingListSecondaryActions() {
    final hasExisting =
        existingPackingListPath != null && !packingListRemoved;

    final hasNew = packingListFile != null;

    if (!hasExisting) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        if (hasExisting && !hasNew)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton(
              onPressed: () async {
                final signedUrl = await supabase.storage
                    .from('booking-documents')
                    .createSignedUrl(
                      existingPackingListPath!,
                      60,
                    );

                await launchUrl(Uri.parse(signedUrl));
              },
              child: const Text('View Existing Packing List'),
            ),
          ),

        TextButton(
          onPressed: () {
            setState(() {
              packingListRemoved = true;
              packingListFile = null;
            });
          },
          child: const Text('Remove Packing List'),
        ),
      ],
    );
  }

  // ---------------- ACTIONS ----------------
  void _refreshConfirmState() {
    setState(() {});
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

    // ---- packing list validation ----
    final hasExisting =existingPackingListPath != null && !packingListRemoved;
    final hasNew = packingListFile != null;
    if (!hasExisting && !hasNew) {return 'Packing list is required';}
    return null;
  }

  bool _canConfirmBooking() {
    final qty = int.tryParse(qtyPalletsController.text);
    final hasQty = qty != null && qty > 0;
    final hasExisting = existingPackingListPath != null && !packingListRemoved;
    final hasNew = packingListFile != null;

    return bookingController.selectedCustomer != null &&
        bookingController.selectedSite != null &&
        bookingController.selectedVehicleType != null &&
        bookingController.selectedDate != null &&
        bookingController.selectedStartTime != null &&
        referenceController.text.trim().isNotEmpty &&
        carrierController.text.trim().isNotEmpty &&
        hasQty &&
        (hasExisting || hasNew);
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
  }

  Widget _actionButtons() {
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
              Navigator.of(context).pushNamedAndRemoveUntil(
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

  void _showCancelBookingDialog() {
    if (editingBookingId == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
                  SnackBar(
                    content: Text('Cancellation failed: $e'),
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
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Update booking' : 'Confirm booking'),
        content: Text(
          isEditing
              ? 'Are you sure you want to update the booking?'
              : 'Are you sure you want to confirm the booking?\n\n'
                'Once confirmed, the delivery slot will be reserved.',
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

              try {
                await bookingService.confirmBooking(
                  controller: bookingController,
                  bookingId: editingBookingId,
                  vehicleTypeId:
                      bookingController.selectedVehicleType!.vehicleTypeId,
                  slotUnitsRequired:
                      bookingController.selectedVehicleType!.slotUnitsRequired,
                  reference: referenceController.text,
                  carrier: carrierController.text,
                  vehicleReg: vehicleRegController.text,
                  container: containerController.text,
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
                  packingListFile: packingListFile,
                  existingPackingListPath: existingPackingListPath,
                  packingListRemoved: packingListRemoved,
                );

                if (!mounted) return;

                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/inbound-overview',
                  (route) => false,
                  arguments: {
                    'booking_confirmed': true,
                    'was_edit': editingBookingId != null,
                  },
                );

              } catch (e) {
                if (!mounted) return;

                Navigator.of(dialogContext).pop(); // CLOSE POPUP

                ScaffoldMessenger.of(pageContext).showSnackBar(
                  SnackBar(
                    content: Text('Booking confirmation failed: $e'),
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
    super.dispose();
  }
}
