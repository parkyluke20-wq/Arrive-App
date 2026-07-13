import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
// Intentionally web-only: dart:html is used for CSV blob download and packing list anchor clicks.
import 'dart:html' as html;
import '../layouts/app_scaffold.dart';
import '../services/user_session.dart';
import '../theme/brand_colors.dart';
import 'package:csv/csv.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../pages/booking_form_page.dart';
import '../services/supabase_service.dart';
import '../widgets/compact_date_range_picker.dart';

class AllBookingsPage extends StatefulWidget {
  const AllBookingsPage({super.key});

  @override
  State<AllBookingsPage> createState() => _AllBookingsPageState();
}

class _AllBookingsPageState extends State<AllBookingsPage> {
  final ScrollController _horizontalController = ScrollController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _allBookings = [];
  final TextEditingController _referenceSearchController = TextEditingController();
  String _referenceSearch = '';
  Timer? _referenceSearchDebounce;
  List<String> _statusFilter = ['all'];
  List<String> _customerFilter = ['all'];
  List<String> _customerOptions = ['all'];
  DateTime _fromDate = _defaultFromDate();
  DateTime? _toDate;

  static DateTime _defaultFromDate() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 14));
  }
  final _filterNotifier = ValueNotifier<int>(0);
  String? _sortColumn;
  bool _sortAscending = true;
  String? _effectiveRole;
  bool _isGlobalScope = false;
  String _siteFilter = 'all';
  List<String> _siteOptions = ['all'];
  String _formatStatus(String? status) {
    if (status == null) return '—';
    switch (status) {
      case 'all':
        return 'All';
      case 'draft':
        return 'Draft';
      case 'booked':
        return 'Booked';
      case 'cancelled':
        return 'Cancelled';
      case 'received':
        return 'Received';
      case 'no_show':
        return 'No Show';
      default:
        return status;
    }
  }
  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  @override
  void dispose() {
    _referenceSearchDebounce?.cancel();
    _horizontalController.dispose();
    _referenceSearchController.dispose();
    _filterNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var query = supabase
        .from('bookings')
        .select(
          'booking_id,booking_ref,start_time,reference,status,vehicle_types(name),customers!inner(customer_code),sites(site_name),qty_cases,qty_pallets',
        );

      if (!_statusFilter.contains('all')) {
        query = query.inFilter('status', _statusFilter);
      }

      if (_siteFilter != 'all') {
        final siteRow = await supabase
            .from('sites')
            .select('site_id')
            .eq('site_name', _siteFilter)
            .maybeSingle();
        if (siteRow == null) {
          debugPrint('_loadBookings: no site found for name "$_siteFilter"');
          if (mounted) setState(() { _loading = false; _allBookings = []; });
          return;
        }
        query = query.eq('site_id', siteRow['site_id'] as int);
      }

      if (!_customerFilter.contains('all')) {
        query = query.inFilter(
            'customers.customer_code', _customerFilter);
      }

      query = query.gte('start_time', _fromDate.toIso8601String());

      if (_toDate != null) {
        final endOfDay = DateTime(
          _toDate!.year,
          _toDate!.month,
          _toDate!.day,
          23,
          59,
          59,
        );
        query = query.lte('start_time', endOfDay.toIso8601String());
      }

      final response = await withRetry(() => query.order('start_time', ascending: false));

      if (!mounted) return;

      final bookings = List<Map<String, dynamic>>.from(response);

      final customersInBookings = bookings
          .map((b) => b['customers']?['customer_code'] as String?)
          .where((c) => c != null && c.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()
        ..sort();

      final sitesInBookings = bookings
          .map((b) => b['sites']?['site_name'] as String?)
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _allBookings = bookings;
        _applyReferenceSearch();
        if (_siteFilter == 'all') {
          _siteOptions = ['all', ...sitesInBookings];
        }
        if (customersInBookings.length == 1) {
          // Only one customer available → hard lock to it
          _customerOptions = customersInBookings;
          _customerFilter = [customersInBookings.first];
        } else {
          _customerOptions = ['all', ...customersInBookings];

          if (!_customerFilter.every((c) => _customerOptions.contains(c))) {
            _customerFilter = ['all'];
          }
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load bookings — please try again")),
      );
    }
  }

  void _exportToCsv() {
    if (_bookings.isEmpty) return;
    if (!kIsWeb) return;

    final List<List<String>> rows = [];

    // Header row
    rows.add([
      'Site',
      'Customer',
      'Type',
      'Date',
      'Time',
      'Booking Ref',
      'Reference',
      'Status',
      'Pallets',
      'Cases'
    ]);

    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    for (final booking in _bookings) {
      final startTime =
          DateTime.parse(booking['start_time']);

      rows.add([
        booking['sites']?['site_name'] ?? '',
        booking['customers']?['customer_code'] ?? '',
        booking['vehicle_types']?['name'] ?? '',
        dateFmt.format(startTime),
        timeFmt.format(startTime),
        (booking['booking_ref'] ?? '').toString(),
        booking['reference'] ?? '',
        _formatStatus(booking['status']),
        booking['qty_pallets'] ?? '',
        booking['qty_cases'] ?? '',
      ]);
    }

    final csv = ListToCsvConverter().convert(rows);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', 'bookings_export.csv')
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn != column) {
        _sortColumn = column;
        _sortAscending = true;
      } else if (_sortAscending) {
        _sortAscending = false;
      } else {
        _sortColumn = null; 
      }

      _applySorting();
    });
  }

  void _applySorting() {
    if (_sortColumn == null) return;

    _bookings.sort((a, b) {
      dynamic aVal;
      dynamic bVal;

      switch (_sortColumn) {
        case 'site':
          aVal = a['sites']?['site_name'] ?? '';
          bVal = b['sites']?['site_name'] ?? '';
          break;
        case 'customer':
          aVal = a['customers']?['customer_code'] ?? '';
          bVal = b['customers']?['customer_code'] ?? '';
          break;
        case 'type':
          aVal = a['vehicle_types']?['name'] ?? '';
          bVal = b['vehicle_types']?['name'] ?? '';
          break;
        case 'date':
          aVal = DateTime.parse(a['start_time']);
          bVal = DateTime.parse(b['start_time']);
          break;
        case 'time':
          aVal = DateTime.parse(a['start_time']);
          bVal = DateTime.parse(b['start_time']);
          break;
        case 'reference':
          aVal = a['reference'] ?? '';
          bVal = b['reference'] ?? '';
          break;
        case 'status':
          aVal = a['status'] ?? '';
          bVal = b['status'] ?? '';
          break;
        case 'pallets':
          aVal = a['qty_pallets'] ?? '';
          bVal = b['qty_pallets'] ?? '';
          break;
        case 'cases':
          aVal = a['qty_cases'] ?? '';
          bVal = b['qty_cases'] ?? '';
          break;
        default:
          return 0;
      }

      int result;

      if (aVal is Comparable && bVal is Comparable) {
        result = aVal.compareTo(bVal);
      } else {
        result = 0;
      }

      return _sortAscending ? result : -result;
    });
  }

  void _applyReferenceSearch() {
    if (_referenceSearch.isEmpty) {
      _bookings = List<Map<String, dynamic>>.from(_allBookings);
    } else {
      final search = _referenceSearch.toLowerCase();

      _bookings = _allBookings.where((b) {
        final ref = (b['reference'] ?? '').toString().toLowerCase();
        final bookingRef = (b['booking_ref'] ?? '').toString().toLowerCase();

        return ref.contains(search) || bookingRef.contains(search);
      }).toList();
    }

    _applySorting();
  }

  String get _dateRangeLabel {
    final fmt = DateFormat('dd/MM/yyyy');
    if (_toDate == null) return 'From ${fmt.format(_fromDate)}';
    return '${fmt.format(_fromDate)} — ${fmt.format(_toDate!)}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => CompactDateRangePicker(
        initialStart: _fromDate,
        initialEnd: _toDate ?? DateTime.now(),
        firstDate: DateTime(2000),
      ),
    );
    if (picked == null) return;
    setState(() {
      _fromDate = picked.start;
      _toDate = picked.end;
    });
    _loadBookings();
  }

  Future<void> _openCreateBooking() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFormPage(
          mode: BookingFormMode.create,
        ),
      ),
    );

    if (!mounted) return;

    if (result == 'confirmed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking confirmed successfully.'),
        ),
      );
    } else if (result == 'draft') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking saved to drafts.'),
        ),
      );
    } else if (result == 'discarded') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking discarded.'),
        ),
      );
    }

    await _loadBookings();
  }

  Future<void> _openEditBooking(String bookingId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFormPage(
          mode: BookingFormMode.edit,
        ),
        settings: RouteSettings(
          arguments: {'booking_id': bookingId},
        ),
      ),
    );

    if (!mounted) return;

    if (result == 'confirmed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking updated successfully.'),
        ),
      );
    } else if (result == 'draft') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft updated successfully.'),
        ),
      );
    } else if (result == 'discarded') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes discarded.'),
        ),
      );
    }

    await _loadBookings();
  }

  Future<void> _openViewBooking(String bookingId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFormPage(
          mode: BookingFormMode.view,
        ),
        settings: RouteSettings(
          arguments: {
            'booking_id': bookingId,
          },
        ),
      ),
    );

    if (!mounted) return;

    await _loadBookings();
  }

  void _showPackingListsDialog(String bookingId, String? bookingRef) {
    showDialog(
      context: context,
      builder: (ctx) => _PackingListsDialog(
        bookingId: bookingId,
        bookingRef: bookingRef,
      ),
    );
  }

  Future<void> _loadUserRole() async {
    if (supabase.auth.currentSession == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final role = await UserSession.instance.getRole();
      final globalScope = await UserSession.instance.isGlobalScope();

      if (mounted) setState(() {
        _effectiveRole = role;
        _isGlobalScope = globalScope;
      });

      await _loadBookings();
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = "Couldn't load bookings — please try again"; });
    }
  }

  bool get _canUpdateStatus =>
    _effectiveRole == 'internal_admin' ||
    _effectiveRole == 'internal_user';
  
  List<String> _availableStatuses() {
    final statuses = [
      'all',
      'booked',
      'cancelled',
      'draft',
      'received',
      'no_show',
    ];
    if (_effectiveRole == 'internal_admin' ||
        _effectiveRole == 'internal_user') {
      statuses.remove('draft');
    }
    return statuses;
  }

  Future<void> _openUpdateStatusDialog(
      Map<String, dynamic> booking) async {
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
                      DropdownMenuItem(
                          value: 'received',
                          child: Text('Received')),
                      DropdownMenuItem(
                          value: 'no_show',
                          child: Text('No Show')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() {
                        selectedStatus = value;
                      });
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
                            setLocalState(() {
                              arrivalDate = picked;
                            });
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
                            setLocalState(() {
                              arrivalTime = picked;
                            });
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
              onPressed: () =>
                  Navigator.pop(context),
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
                        'arrived_at':
                            arrivedAt?.toIso8601String(),
                      })
                      .eq('booking_id',
                          booking['booking_id']);

                  if (!mounted) return;

                  Navigator.pop(context);
                  await _loadBookings();
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

  void _confirmCancel(int index) {
    final booking = _bookings[index];
    final bookingId = booking['booking_id'];

    if (bookingId == null) {
      throw Exception('booking_id missing from booking row: $booking');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Cancel Booking'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              try {
                await supabase
                    .from('bookings')
                    .update({
                      'status': 'cancelled',
                      'updated_at': DateTime.now().toIso8601String(),
                    })
                    .eq('booking_id', bookingId);

                await _loadBookings();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Couldn't cancel booking — please try again")),
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
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'All Bookings',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderActions(),
            const SizedBox(height: 24),
            Expanded(
              child: _buildBookingsTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All Deliveries:',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 1,
          runSpacing: 1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [

            // ───────── STATUS FILTER ─────────
            const Text(
              'Filter by Status:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),

            SizedBox(
              width: 220,
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isExpanded: true,
                  hint: Text(
                    _statusFilter.contains('all')
                        ? 'All'
                        : _statusFilter.map(_formatStatus).join(', '),
                    overflow: TextOverflow.ellipsis,
                  ),
                  buttonStyleData: const ButtonStyleData(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 300,
                    decoration: BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                  ),
                  items: _availableStatuses().map((status) {
                    return DropdownMenuItem<String>(
                      value: status,
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, menuSetState) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _filterNotifier,
                            builder: (context, _, __) {
                              final isSelected = _statusFilter.contains(status);
                              return InkWell(
                                onTap: () {
                                  if (status == 'all') {
                                    setState(() {
                                      _statusFilter = ['all'];
                                    });
                                  } else {
                                    setState(() {
                                      _statusFilter.remove('all');
                                      if (isSelected) {
                                        _statusFilter.remove(status);
                                      } else {
                                        _statusFilter.add(status);
                                      }
                                      if (_statusFilter.isEmpty) {
                                        _statusFilter = ['all'];
                                      }
                                    });
                                  }
                                  _filterNotifier.value++;
                                  _loadBookings();
                                  menuSetState(() {});
                                },
                                child: Row(
                                  children: [
                                    IgnorePointer(
                                      child: Checkbox(
                                        value: isSelected,
                                        onChanged: (_) {},
                                      ),
                                    ),
                                    Text(_formatStatus(status)),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  }).toList(),
                  value: null,
                  onChanged: (_) {},
                ),
              ),
            ),

            const SizedBox(width: 24),

            // ───────── SITE FILTER (global scope users only) ─────────
            if (_isGlobalScope) ...[
              const Text(
                'Site:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 200,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isExpanded: true,
                    hint: Text(
                      _siteFilter == 'all' ? 'All' : _siteFilter,
                      overflow: TextOverflow.ellipsis,
                    ),
                    buttonStyleData: const ButtonStyleData(
                      height: 36,
                      padding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                    dropdownStyleData: const DropdownStyleData(
                      maxHeight: 300,
                      decoration:
                          BoxDecoration(color: BrandColors.background),
                    ),
                    menuItemStyleData:
                        const MenuItemStyleData(height: 32),
                    value: _siteFilter,
                    items: _siteOptions
                        .map((site) => DropdownMenuItem<String>(
                              value: site,
                              child: Text(
                                site == 'all' ? 'All' : site,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _siteFilter = v;
                        _customerFilter = ['all'];
                      });
                      _loadBookings();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
            ],

            // ───────── CUSTOMER FILTER ─────────
            const Text(
              'Customer:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),

            SizedBox(
              width: 220,
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isExpanded: true,
                  hint: Text(
                    _customerFilter.contains('all')
                        ? 'All'
                        : _customerFilter.join(', '),
                    overflow: TextOverflow.ellipsis,
                  ),
                  buttonStyleData: const ButtonStyleData(
                    height: 36,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  dropdownStyleData: const DropdownStyleData(
                    maxHeight: 300,
                    decoration: BoxDecoration(color: BrandColors.background),
                  ),
                  menuItemStyleData: const MenuItemStyleData(
                    height: 32,
                  ),
                  items: _customerOptions.map((customer) {
                    return DropdownMenuItem<String>(
                      value: customer,
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, menuSetState) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _filterNotifier,
                            builder: (context, _, __) {
                              final isSelected = _customerFilter.contains(customer);
                              return InkWell(
                                onTap: () {
                                  if (customer == 'all') {
                                    setState(() {
                                      _customerFilter = ['all'];
                                    });
                                  } else {
                                    setState(() {
                                      _customerFilter.remove('all');
                                      if (isSelected) {
                                        _customerFilter.remove(customer);
                                      } else {
                                        _customerFilter.add(customer);
                                      }
                                      if (_customerFilter.isEmpty) {
                                        _customerFilter = ['all'];
                                      }
                                    });
                                  }
                                  _filterNotifier.value++;
                                  _loadBookings();
                                  menuSetState(() {});
                                },
                                child: Row(
                                  children: [
                                    IgnorePointer(
                                      child: Checkbox(
                                        value: isSelected,
                                        onChanged: (_) {},
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        customer == 'all' ? 'All' : customer,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    );
                  }).toList(),
                  value: null,
                  onChanged: (_) {},
                ),
              ),
            ),

            const SizedBox(width: 24),

            // ───────── DATE RANGE ─────────
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range, size: 16),
              label: Text(_dateRangeLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.deepBlue,
                side: const BorderSide(color: BrandColors.deepBlue),
              ),
            ),

            const SizedBox(width: 16),

            // ───────── EXPORT ─────────
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.lightBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: _exportToCsv,
              icon: const Icon(Icons.download),
              label: const Text('Export CSV'),
            ),

            const SizedBox(width: 16),

            // ───────── SEARCH ─────────
            SizedBox(
              width: 260,
              child: TextField(
                controller: _referenceSearchController,
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _referenceSearchDebounce?.cancel();
                  _referenceSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      setState(() {
                        _referenceSearch = value;
                        _applyReferenceSearch();
                      });
                    },
                  );
                },
              ),
            ),

          ],
        ),
      ],
    );
  }

  Widget _buildBookingsTable() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    const double actionW = 180;
    const double bookingRefW = 120;
    const double refW = 200;
    const double statusW = 110;
    const double siteW = 120;
    const double customerW = 150;
    const double typeW = 220;
    const double dateW = 120;
    const double timeW = 90;
    const double palletsW = 90.0;
    const double casesW = 90.0;

    const double tableWidth =
    actionW +
    bookingRefW +
    refW +
    statusW +
    siteW +
    customerW +
    typeW +
    dateW +
    timeW +
    palletsW +
    casesW;

    Widget headerCell(String text, double width, String columnKey) {
      final isActive = _sortColumn == columnKey;

      return SizedBox(
        width: width,
        child: InkWell(
          onTap: () => _toggleSort(columnKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isActive)
                  Icon(
                    _sortAscending
                        ? Icons.arrow_drop_up
                        : Icons.arrow_drop_down,
                    color: Colors.white,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget dataCell(String text, double width) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    Widget linkCell(String? text, String? bookingId, double width) {
      final label = (text ?? '—').toString();
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: bookingId != null && text != null
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openViewBooking(bookingId),
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1558D6),
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFF1558D6),
                      ),
                    ),
                  ),
                )
              : Text(label, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    Widget statusCell(String? status, double width) {
      final text = _formatStatus(status);
      Color? bgColor;
      if (status == 'received') bgColor = BrandColors.green;
      if (status == 'cancelled') bgColor = BrandColors.red;
      if (status == 'booked') bgColor = BrandColors.orange;

      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: bgColor == null
              ? Text(text, overflow: TextOverflow.ellipsis)
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(text, overflow: TextOverflow.ellipsis),
                ),
        ),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [

              // 🔹 HEADER
              Container(
                color: BrandColors.lightBlue,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                ), 
                child: Row(
                  children: [
                    headerCell('Action', actionW, 'action'),
                    headerCell('Booking Ref', bookingRefW, 'booking_ref'),
                    headerCell('Reference', refW, 'reference'),
                    headerCell('Status', statusW, 'status'),
                    headerCell('Site', siteW, 'site'),
                    headerCell('Customer', customerW, 'customer'),
                    headerCell('Type', typeW, 'type'),
                    headerCell('Date', dateW, 'date'),
                    headerCell('Time', timeW, 'time'),
                    headerCell('Pallets', palletsW, 'pallets'),
                    headerCell('Cases', casesW, 'cases'),
                  ],
                ),
              ),

              // 🔹 BODY
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(_bookings.length, (index) {
                      final booking = _bookings[index];
                      final startTime =
                          DateTime.parse(booking['start_time']);

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                        ), // removed horizontal padding (fixes 24px overflow)
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.black12,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: actionW,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [

                                  // UPDATE STATUS
                                  if (_canUpdateStatus &&
                                      booking['status'] != 'received' &&
                                      booking['status'] != 'cancelled' &&
                                      booking['status'] != 'draft')
                                    Tooltip(
                                      message: 'Update Status',
                                      child: IconButton(
                                        icon: const Icon(Icons.update),
                                        color: BrandColors.orange,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _openUpdateStatusDialog(booking),
                                      ),
                                    ),

                                  // VIEW
                                  Tooltip(
                                    message: 'View',
                                    child: IconButton(
                                      icon: const Icon(Icons.visibility),
                                        color: BrandColors.orange,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () =>
                                            _openViewBooking(booking['booking_id']),
                                      ),
                                    ),

                                  // CANCEL
                                  if (booking['status'] != 'received' &&
                                      booking['status'] != 'cancelled')
                                    Tooltip(
                                      message: 'Cancel',
                                      child: IconButton(
                                        icon: const Icon(Icons.cancel),
                                        color: BrandColors.red,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _confirmCancel(index),
                                      ),
                                    ),

                                  // PACKING LISTS
                                  if (booking['status'] != 'cancelled')
                                    Tooltip(
                                      message: 'View Packing Lists',
                                      child: IconButton(
                                        icon: const Icon(Icons.folder_open),
                                        color: BrandColors.green,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        onPressed: () => _showPackingListsDialog(
                                          booking['booking_id'].toString(),
                                          booking['booking_ref']?.toString(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            linkCell(
                              booking['booking_ref']?.toString(),
                              booking['booking_id']?.toString(),
                              bookingRefW,
                            ),
                            dataCell(
                                booking['reference'] ?? '—',
                                refW),
                            statusCell(booking['status'], statusW),
                            dataCell(
                                booking['sites']?['site_name'] ?? '—',
                                siteW),
                            dataCell(
                                booking['customers']?['customer_code'] ?? '—',
                                customerW),
                            dataCell(
                                booking['vehicle_types']?['name'] ?? '—',
                                typeW),
                            dataCell(
                                dateFmt.format(startTime),
                                dateW),
                            dataCell(
                                timeFmt.format(startTime),
                                timeW),
                            dataCell(
                              (booking['qty_pallets'] ?? '—').toString(),
                              palletsW,
                            ),
                            dataCell(
                              (booking['qty_cases'] ?? '—').toString(),
                              casesW,
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackingListsDialog extends StatefulWidget {
  final String bookingId;
  final String? bookingRef;

  const _PackingListsDialog({
    required this.bookingId,
    required this.bookingRef,
  });

  @override
  State<_PackingListsDialog> createState() => _PackingListsDialogState();
}

class _PackingListsDialogState extends State<_PackingListsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('booking_packing_lists')
          .select('id, storage_path, file_name, uploaded_at')
          .eq('booking_id', widget.bookingId)
          .order('uploaded_at');
      if (mounted) {
        setState(() {
          _files = List<Map<String, dynamic>>.from(rows);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(Map<String, dynamic> row) async {
    try {
      final signedUrl = await supabase.storage
          .from('booking-documents')
          .createSignedUrl(row['storage_path'] as String, 60);
      (html.AnchorElement(href: signedUrl)
        ..setAttribute('download', row['file_name'] as String? ?? ''))
        .click();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.bookingRef != null
        ? 'Packing Lists — ${widget.bookingRef}'
        : 'Packing Lists';

    return AlertDialog(
      backgroundColor: BrandColors.background,
      title: Text(title),
      content: SizedBox(
        width: 400,
        child: _loading
            ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            : _files.isEmpty
                ? const Text('No packing lists found for this booking.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _files
                        .map(
                          (f) => ListTile(
                            leading: const Icon(Icons.insert_drive_file),
                            title: Text(f['file_name'] as String? ?? '—'),
                            trailing: IconButton(
                              icon: const Icon(Icons.download),
                              onPressed: () => _download(f),
                              tooltip: 'Download',
                            ),
                          ),
                        )
                        .toList(),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
