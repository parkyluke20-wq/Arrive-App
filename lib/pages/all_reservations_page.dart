import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../layouts/app_scaffold.dart';
import '../services/user_session.dart';
import '../theme/brand_colors.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../services/supabase_service.dart';

class AllReservationsPage extends StatefulWidget {
  const AllReservationsPage({super.key});

  @override
  State<AllReservationsPage> createState() => _AllReservationsPageState();
}

class _AllReservationsPageState extends State<AllReservationsPage> {
  final ScrollController _horizontalController = ScrollController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reservations = [];
  List<Map<String, dynamic>> _allReservations = [];
  final TextEditingController _searchController = TextEditingController();
  String _reasonSearch = '';
  Timer? _searchDebounce;
  List<String> _siteFilter = ['all'];
  List<String> _siteOptions = ['all'];
  DateTime _fromDate = _defaultFromDate();
  DateTime? _toDate;
  final _filterNotifier = ValueNotifier<int>(0);
  String? _sortColumn;
  bool _sortAscending = true;

  static DateTime _defaultFromDate() {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 14));
  }

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _horizontalController.dispose();
    _searchController.dispose();
    _filterNotifier.dispose();
    super.dispose();
  }

  Future<void> _initialise() async {
    try {
      await _checkAccess();
      await _loadReservations();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Couldn't load reservations — please try again";
        });
      }
    }
  }

  Future<void> _checkAccess() async {
    final role = await UserSession.instance.getRole();
    if (role != 'internal_admin' && role != 'internal_user' && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _loadReservations() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var query = supabase
          .from('outbound_reservations')
          .select(
            'reservation_id, site_id, pool_id, start_time, end_time, reason, reserved_by, sites(site_name), capacity_pools(pool_name)',
          )
          .gte('start_time', _fromDate.toIso8601String());

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

      final response = await withRetry(
        () => query.order('start_time', ascending: false),
      );

      if (!mounted) return;

      final reservations = List<Map<String, dynamic>>.from(response);

      final sitesInData = reservations
          .map((r) => r['sites']?['site_name'] as String?)
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _allReservations = reservations;
        if (sitesInData.length == 1) {
          _siteOptions = sitesInData;
          _siteFilter = [sitesInData.first];
        } else {
          _siteOptions = ['all', ...sitesInData];
          if (!_siteFilter.every((s) => _siteOptions.contains(s))) {
            _siteFilter = ['all'];
          }
        }
        _applyFilters();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't load reservations — please try again"),
        ),
      );
    }
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allReservations);

    if (!_siteFilter.contains('all')) {
      filtered = filtered.where((r) {
        final siteName = r['sites']?['site_name'] as String? ?? '';
        return _siteFilter.contains(siteName);
      }).toList();
    }

    if (_reasonSearch.isNotEmpty) {
      final search = _reasonSearch.toLowerCase();
      filtered = filtered.where((r) {
        final reason = (r['reason'] ?? '').toString().toLowerCase();
        return reason.contains(search);
      }).toList();
    }

    _reservations = filtered;
    _applySorting();
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

    _reservations.sort((a, b) {
      dynamic aVal;
      dynamic bVal;

      switch (_sortColumn) {
        case 'site':
          aVal = a['sites']?['site_name'] ?? '';
          bVal = b['sites']?['site_name'] ?? '';
          break;
        case 'pool':
          aVal = a['capacity_pools']?['pool_name'] ?? '';
          bVal = b['capacity_pools']?['pool_name'] ?? '';
          break;
        case 'date':
        case 'start_time':
          aVal = DateTime.parse(a['start_time']);
          bVal = DateTime.parse(b['start_time']);
          break;
        case 'end_time':
          aVal = DateTime.parse(a['end_time']);
          bVal = DateTime.parse(b['end_time']);
          break;
        case 'reason':
          aVal = a['reason'] ?? '';
          bVal = b['reason'] ?? '';
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

  ThemeData _datePickerTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(
        surface: BrandColors.background,
        surfaceContainerHigh: BrandColors.background,
      ),
    );
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: _datePickerTheme(context),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
      _loadReservations();
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: _datePickerTheme(context),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _toDate = picked);
      _loadReservations();
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> reservation) async {
    final reasonController = TextEditingController(
      text: reservation['reason'] ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Edit Reservation'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await supabase
                    .from('outbound_reservations')
                    .update({'reason': reasonController.text.trim()})
                    .eq('reservation_id', reservation['reservation_id']);
                if (context.mounted) Navigator.pop(context, true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Couldn't update reservation — please try again",
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    reasonController.dispose();

    if (result == true && mounted) {
      await _loadReservations();
    }
  }

  void _confirmDelete(int index) {
    final reservation = _reservations[index];
    final id = reservation['reservation_id'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BrandColors.background,
        title: const Text('Delete Reservation'),
        content: const Text(
          'Are you sure you want to delete this reservation? This will release the reserved slots.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandColors.red,
            ),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await supabase
                    .from('outbound_reservations')
                    .delete()
                    .eq('id', id);
                await _loadReservations();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Couldn't delete reservation — please try again",
                    ),
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
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'All Reservations',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderActions(),
            const SizedBox(height: 24),
            Expanded(
              child: _buildReservationsTable(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderActions() {
    final dateFmt = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All Reservations:',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 1,
          runSpacing: 1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [

            // ───────── SITE FILTER ─────────
            const Text(
              'Filter by Site:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),

            SizedBox(
              width: 220,
              child: DropdownButtonHideUnderline(
                child: DropdownButton2<String>(
                  isExpanded: true,
                  hint: Text(
                    _siteFilter.contains('all')
                        ? 'All'
                        : _siteFilter.join(', '),
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
                  menuItemStyleData: const MenuItemStyleData(height: 32),
                  items: _siteOptions.map((site) {
                    return DropdownMenuItem<String>(
                      value: site,
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, menuSetState) {
                          return ValueListenableBuilder<int>(
                            valueListenable: _filterNotifier,
                            builder: (context, _, __) {
                              final isSelected = _siteFilter.contains(site);
                              return InkWell(
                                onTap: () {
                                  if (site == 'all') {
                                    setState(() => _siteFilter = ['all']);
                                  } else {
                                    setState(() {
                                      _siteFilter.remove('all');
                                      if (isSelected) {
                                        _siteFilter.remove(site);
                                      } else {
                                        _siteFilter.add(site);
                                      }
                                      if (_siteFilter.isEmpty) {
                                        _siteFilter = ['all'];
                                      }
                                    });
                                  }
                                  _filterNotifier.value++;
                                  _applyFilters();
                                  setState(() {});
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
                                        site == 'all' ? 'All' : site,
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

            // ───────── DATE FROM ─────────
            OutlinedButton(
              onPressed: _pickFromDate,
              child: Text('Date From: ${dateFmt.format(_fromDate)}'),
            ),

            const SizedBox(width: 16),

            // ───────── DATE TO ─────────
            OutlinedButton(
              onPressed: _pickToDate,
              child: Text(
                _toDate == null
                    ? 'Date To:'
                    : 'Date To: ${dateFmt.format(_toDate!)}',
              ),
            ),

            const SizedBox(width: 16),

            // ───────── SEARCH ─────────
            SizedBox(
              width: 260,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search reason...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      setState(() {
                        _reasonSearch = value;
                        _applyFilters();
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

  Widget _buildReservationsTable() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    const double actionW = 100;
    const double siteW = 150;
    const double poolW = 200;
    const double dateW = 120;
    const double startTimeW = 100;
    const double endTimeW = 100;
    const double reasonW = 350;

    const double tableWidth =
        actionW + siteW + poolW + dateW + startTimeW + endTimeW + reasonW;

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
          child: Text(text, overflow: TextOverflow.ellipsis),
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

              // ─── HEADER ───
              Container(
                color: BrandColors.lightBlue,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    headerCell('Action', actionW, 'action'),
                    headerCell('Site', siteW, 'site'),
                    headerCell('Pool', poolW, 'pool'),
                    headerCell('Date', dateW, 'date'),
                    headerCell('Start Time', startTimeW, 'start_time'),
                    headerCell('End Time', endTimeW, 'end_time'),
                    headerCell('Reason', reasonW, 'reason'),
                  ],
                ),
              ),

              // ─── BODY ───
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(_reservations.length, (index) {
                      final reservation = _reservations[index];
                      final startTime = DateTime.parse(
                        reservation['start_time'],
                      );
                      final endTime = DateTime.parse(reservation['end_time']);
                      final siteName =
                          reservation['sites']?['site_name'] as String? ?? '—';
                      final poolName =
                          reservation['capacity_pools']?['pool_name']
                              as String? ??
                          '—';

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.black12),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: actionW,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Tooltip(
                                    message: 'Edit',
                                    child: IconButton(
                                      icon: const Icon(Icons.edit),
                                      color: BrandColors.orange,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: () =>
                                          _openEditDialog(reservation),
                                    ),
                                  ),
                                  Tooltip(
                                    message: 'Delete',
                                    child: IconButton(
                                      icon: const Icon(Icons.delete),
                                      color: BrandColors.red,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(index),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            dataCell(siteName, siteW),
                            dataCell(_formatPool(poolName), poolW),
                            dataCell(dateFmt.format(startTime), dateW),
                            dataCell(timeFmt.format(startTime), startTimeW),
                            dataCell(timeFmt.format(endTime), endTimeW),
                            dataCell(
                              reservation['reason'] as String? ?? '—',
                              reasonW,
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

  String _formatPool(String raw) =>
      raw.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
}
