import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../layouts/app_scaffold.dart';
import '../pages/booking_form_page.dart';
import '../services/supabase_service.dart';
import '../theme/brand_colors.dart';
import '../widgets/compact_date_range_picker.dart';

// ─── Internal helpers ─────────────────────────────────────────────────────────

class _UnavailableRange {
  final DateTime start;
  final DateTime end; // exclusive
  const _UnavailableRange({required this.start, required this.end});
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class InboundOverviewPage extends StatefulWidget {
  const InboundOverviewPage({super.key});

  @override
  State<InboundOverviewPage> createState() => _InboundOverviewPageState();
}

class _InboundOverviewPageState extends State<InboundOverviewPage> {
  // ── State ──────────────────────────────────────────────────────────────────

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _todayBookings = [];
  List<Map<String, dynamic>> _weekBookings = [];
  List<Map<String, dynamic>> _allUpcomingBookings = [];
  Map<DateTime, List<_UnavailableRange>> _unavailableByDay = {};

  bool _didHandleRouteArgs = false;

  final _arrivalsCtrl = ScrollController();

  late DateTime _ganttStart;
  late DateTime _ganttEnd;
  List<Map<String, dynamic>> _ganttBookings = [];

  // ── Derived metrics ────────────────────────────────────────────────────────

  int get _totalToday => _todayBookings.length;

  int get _totalPalletsToday => _todayBookings.fold(
        0,
        (s, b) => s + ((b['qty_pallets'] as num?)?.toInt() ?? 0),
      );

  String get _nextArrivalTime {
    if (_allUpcomingBookings.isEmpty) return '—';
    final t = DateTime.tryParse(
        _allUpcomingBookings.first['start_time']?.toString() ?? '');
    return t != null ? DateFormat('HH:mm').format(t) : '—';
  }

  String? get _nextArrivalDateLabel {
    if (_allUpcomingBookings.isEmpty) return null;
    final t = DateTime.tryParse(
        _allUpcomingBookings.first['start_time']?.toString() ?? '');
    if (t == null) return null;
    final today = _today;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final day = DateTime(t.year, t.month, t.day);
    if (day == today) return null;
    if (day == tomorrow) return 'Tomorrow';
    return DateFormat('EEE d MMM').format(t);
  }

  int get _totalThisWeek => _weekBookings.length;

  // ── Calendar helpers ───────────────────────────────────────────────────────

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<DateTime> get _ganttDays {
    final days = <DateTime>[];
    var d = _ganttStart;
    while (!d.isAfter(_ganttEnd)) {
      days.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return days;
  }

  Map<DateTime, List<Map<String, dynamic>>> get _weekBookingsByDay {
    final out = <DateTime, List<Map<String, dynamic>>>{};
    for (final b in _weekBookings) {
      final t = DateTime.tryParse(b['start_time']?.toString() ?? '');
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      out.putIfAbsent(day, () => []).add(b);
    }
    return out;
  }

  Map<DateTime, List<Map<String, dynamic>>> get _ganttBookingsByDay {
    final out = <DateTime, List<Map<String, dynamic>>>{};
    for (final b in _ganttBookings) {
      final t = DateTime.tryParse(b['start_time']?.toString() ?? '');
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      out.putIfAbsent(day, () => []).add(b);
    }
    return out;
  }

  String get _ganttRangeLabel =>
      '${DateFormat('d MMM').format(_ganttStart)} – '
      '${DateFormat('d MMM').format(_ganttEnd)}';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final t = _today;
    _ganttStart = DateTime(t.year, t.month, t.day + 1);
    _ganttEnd = DateTime(t.year, t.month, t.day + 7);
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didHandleRouteArgs) return;
    _didHandleRouteArgs = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args?['booking_confirmed'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final wasEdit = args!['was_edit'] == true;
        final ref = args['booking_ref'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(wasEdit
              ? 'Booking updated successfully'
              : 'Booking confirmed. Booking ID: ${ref ?? ''}'),
        ));
      });
    }
  }

  @override
  void dispose() {
    _arrivalsCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day + 1);
      final weekEnd = DateTime(now.year, now.month, now.day + 7);
      final ganttEndQ = _ganttEnd.add(const Duration(days: 1));

      final results = await Future.wait([
        withRetry(() => supabase
            .from('bookings')
            .select('booking_id,booking_ref,start_time,status,qty_pallets,'
                'qty_cases,vehicle_types(name),customers(customer_code),'
                'sites(site_name)')
            .gte('start_time', todayStart.toIso8601String())
            .lt('start_time', todayEnd.toIso8601String())
            .neq('status', 'cancelled')
            .neq('status', 'draft')
            .order('start_time', ascending: true)),
        withRetry(() => supabase
            .from('bookings')
            .select('booking_id,booking_ref,start_time,end_time,status,'
                'qty_pallets,site_id,customers(customer_code),sites(site_name)')
            .gte('start_time', todayStart.toIso8601String())
            .lt('start_time', weekEnd.toIso8601String())
            .neq('status', 'cancelled')
            .neq('status', 'draft')
            .order('start_time', ascending: true)),
        withRetry(() => supabase
            .from('bookings')
            .select('booking_id,booking_ref,start_time,status')
            .eq('status', 'booked')
            .gt('start_time', now.toIso8601String())
            .order('start_time', ascending: true)),
        withRetry(() => supabase
            .from('bookings')
            .select('booking_id,booking_ref,start_time,end_time,status,'
                'qty_pallets,site_id,customers(customer_code),sites(site_name),'
                'vehicle_types(name,load_type)')
            .gte('start_time', _ganttStart.toIso8601String())
            .lt('start_time', ganttEndQ.toIso8601String())
            .neq('status', 'cancelled')
            .neq('status', 'draft')
            .order('start_time', ascending: true)),
      ]);

      if (!mounted) return;

      final ganttBookings = List<Map<String, dynamic>>.from(results[3]);

      final ownStarts = ganttBookings
          .map((b) => b['start_time']?.toString())
          .where((s) => s != null)
          .map((s) => DateTime.parse(s!))
          .toSet();

      final siteIds = ganttBookings
          .map((b) => b['site_id'])
          .where((id) => id != null)
          .map((id) => id as int)
          .toSet();

      final unavailableByDay = <DateTime, List<_UnavailableRange>>{};

      for (final siteId in siteIds) {
        try {
          final slotResp = await withRetry(() => supabase
              .from('slot_availability_projection')
              .select('slot_start,slot_status')
              .eq('site_id', siteId)
              .gte('slot_start', _ganttStart.toIso8601String())
              .lt('slot_start', ganttEndQ.toIso8601String())
              .neq('slot_status', 'available')
              .order('slot_start', ascending: true));

          final nonOwn = List<Map<String, dynamic>>.from(slotResp).where((r) {
            final t = DateTime.tryParse(r['slot_start']?.toString() ?? '');
            return t != null && !ownStarts.contains(t);
          }).toList();

          _groupSlotsIntoRanges(nonOwn, unavailableByDay);
        } catch (_) {
          // Non-critical — own bookings still render correctly.
        }
      }

      setState(() {
        _todayBookings = List<Map<String, dynamic>>.from(results[0]);
        _weekBookings = List<Map<String, dynamic>>.from(results[1]);
        _allUpcomingBookings = List<Map<String, dynamic>>.from(results[2]);
        _ganttBookings = ganttBookings;
        _unavailableByDay = unavailableByDay;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load dashboard — please try again";
      });
    }
  }

  void _groupSlotsIntoRanges(
    List<Map<String, dynamic>> slots,
    Map<DateTime, List<_UnavailableRange>> out,
  ) {
    DateTime? runStart;
    DateTime? runLast;

    void flush() {
      if (runStart == null || runLast == null) return;
      final day = DateTime(runStart!.year, runStart!.month, runStart!.day);
      out.putIfAbsent(day, () => []).add(_UnavailableRange(
        start: runStart!,
        end: runLast!.add(const Duration(minutes: 30)),
      ));
      runStart = null;
      runLast = null;
    }

    for (final r in slots) {
      final t = DateTime.tryParse(r['slot_start']?.toString() ?? '');
      if (t == null) continue;
      if (runStart == null) {
        runStart = runLast = t;
      } else if (t.difference(runLast!).inMinutes == 30 &&
          t.day == runStart!.day) {
        runLast = t;
      } else {
        flush();
        runStart = runLast = t;
      }
    }
    flush();
  }

  Future<void> _pickGanttRange() async {
    final tomorrow = _today.add(const Duration(days: 1));
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => CompactDateRangePicker(
        initialStart: _ganttStart,
        initialEnd: _ganttEnd,
        firstDate: tomorrow,
      ),
    );
    if (picked == null || !mounted) return;

    final rangeDays = picked.end.difference(picked.start).inDays + 1;
    final clampedEnd = rangeDays > 60
        ? picked.start.add(const Duration(days: 59))
        : picked.end;

    if (rangeDays > 60 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Range capped at 60 days')),
      );
    }

    setState(() {
      _ganttStart = picked.start;
      _ganttEnd = clampedEnd;
    });
    _loadData();
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  String _formatStatus(String? s) {
    if (s == null) return '—';
    return s
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'booked':
        return BrandColors.lightBlue;
      case 'arrived':
        return BrandColors.green;
      case 'received':
        return BrandColors.green;
      case 'no_show':
      case 'no-show':
        return BrandColors.red;
      default:
        return BrandColors.grey;
    }
  }

  static Color statusTextColor(String status) =>
      (status == 'arrived' || status == 'received')
          ? BrandColors.charcoal
          : Colors.white;

  static Color loadTypeColor(String? loadType, String? vehicleTypeName) {
    final name = vehicleTypeName?.toLowerCase() ?? '';
    if (loadType?.toLowerCase() == 'container' || name.contains('container')) {
      return BrandColors.deepBlue;
    }
    return BrandColors.lightBlue;
  }

  void _navigateToBooking(String bookingId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFormPage(
          mode: BookingFormMode.view,
          returnRoute: '/inbound-overview',
        ),
        settings: RouteSettings(arguments: {'booking_id': bookingId}),
      ),
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: BrandColors.lightBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      ),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookingFormPage(
            mode: BookingFormMode.create,
            returnRoute: '/inbound-overview',
          ),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text(
        'Book a Delivery',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Inbound Overview',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildMetricsStrip()),
                          const SizedBox(width: 16),
                          _buildCreateButton(),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildTodayArrivals(),
                      const SizedBox(height: 24),
                      _buildCalendar(),
                    ],
                  ),
                ),
    );
  }

  // ─── 1. Metrics Strip ──────────────────────────────────────────────────────

  Widget _buildMetricsStrip() {
    final metrics = [
      _MetricData(
          label: 'Bookings Today',
          value: '$_totalToday',
          icon: Icons.today),
      _MetricData(
          label: 'Pallets Inbound Today',
          value: '$_totalPalletsToday',
          icon: Icons.inventory_2_outlined),
      _MetricData(
          label: 'Next Arrival',
          value: _nextArrivalTime,
          subValue: _nextArrivalDateLabel,
          icon: Icons.schedule),
      _MetricData(
          label: 'Bookings This Week',
          value: '$_totalThisWeek',
          icon: Icons.date_range),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              _MetricCard(data: metrics[i]),
            ],
          ],
        ),
      ),
    );
  }

  // ─── 2. Today's Arrivals ───────────────────────────────────────────────────

  Widget _buildTodayArrivals() {
    final timeFmt = DateFormat('HH:mm');

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  "Today's Arrivals",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Text(
                  '(${_todayBookings.length})',
                  style: const TextStyle(fontSize: 18, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_todayBookings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No arrivals scheduled for today',
                  style: TextStyle(color: Colors.black45),
                ),
              )
            else
              Scrollbar(
                controller: _arrivalsCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _arrivalsCtrl,
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (int i = 0; i < _todayBookings.length; i++) ...[
                          if (i > 0) const SizedBox(width: 12),
                          Builder(builder: (_) {
                            final b = _todayBookings[i];
                            final t = DateTime.tryParse(
                                b['start_time']?.toString() ?? '');
                            final st = b['status']?.toString() ?? '';
                            return _ArrivalCard(
                              bookingRef:
                                  b['booking_ref']?.toString() ?? '—',
                              customerCode: b['customers']?['customer_code']
                                      ?.toString() ??
                                  '—',
                              arrivalTime:
                                  t != null ? timeFmt.format(t) : '—',
                              statusColor: statusColor(st),
                              statusTextColor: statusTextColor(st),
                              formattedStatus: _formatStatus(st),
                              onTap: b['booking_id'] != null
                                  ? () => _navigateToBooking(
                                      b['booking_id'].toString())
                                  : null,
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 3. Gantt Calendar ─────────────────────────────────────────────────────

  Widget _buildCalendar() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Schedule: $_ganttRangeLabel',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickGanttRange,
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(_ganttRangeLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BrandColors.deepBlue,
                    side: const BorderSide(color: BrandColors.deepBlue),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a booking to view details',
              style: TextStyle(fontSize: 13, color: Colors.black45),
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                _LegendDot(color: BrandColors.deepBlue, label: 'Container'),
                SizedBox(width: 16),
                _LegendDot(color: BrandColors.lightBlue, label: 'Palletised'),
              ],
            ),
            const SizedBox(height: 16),
            _GanttView(
              days: _ganttDays,
              bookingsByDay: _ganttBookingsByDay,
              unavailableByDay: _unavailableByDay,
              onBookingTap: _navigateToBooking,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Gantt View ───────────────────────────────────────────────────────────────

class _GanttView extends StatefulWidget {
  final List<DateTime> days;
  final Map<DateTime, List<Map<String, dynamic>>> bookingsByDay;
  final Map<DateTime, List<_UnavailableRange>> unavailableByDay;
  final void Function(String bookingId) onBookingTap;

  const _GanttView({
    required this.days,
    required this.bookingsByDay,
    required this.unavailableByDay,
    required this.onBookingTap,
  });

  @override
  State<_GanttView> createState() => _GanttViewState();
}

class _GanttViewState extends State<_GanttView> {
  static const double _labelW = 88;
  static const double _rulerH = 30;
  static const double _laneH = 42;
  static const double _laneGap = 4;
  static const double _emptyDayH = 48;
  static const double _dayPadV = 5;
  static const double _dayGap = 7;

  // Recomputed each build from the actual container width so that all
  // hour columns share the space equally and the grid fills edge-to-edge.
  double _effectivePxPerMin = 1.8;

  // One controller per day row so each row is its own scrollable.
  // All are synced together, plus the passive ruler and the user-facing
  // scrollbar at the bottom.
  late List<ScrollController> _dayCtrl;
  final _rulerCtrl = ScrollController();
  final _scrollbarCtrl = ScrollController();
  bool _syncing = false;

  late int _winStartMin;
  late int _winEndMin;

  @override
  void initState() {
    super.initState();
    _computeWindow();
    _initDayControllers();
    _scrollbarCtrl.addListener(_onScrollbarScroll);
  }

  @override
  void didUpdateWidget(_GanttView old) {
    super.didUpdateWidget(old);
    _computeWindow();
    if (old.days.length != widget.days.length) {
      _disposeDayControllers();
      _initDayControllers();
    }
  }

  @override
  void dispose() {
    _disposeDayControllers();
    _rulerCtrl.dispose();
    _scrollbarCtrl.dispose();
    super.dispose();
  }

  void _initDayControllers() {
    _dayCtrl =
        List.generate(widget.days.length, (_) => ScrollController());
    for (final c in _dayCtrl) {
      c.addListener(() => _onDayScroll(c));
    }
  }

  void _disposeDayControllers() {
    for (final c in _dayCtrl) {
      c.dispose();
    }
  }

  // When any day row scrolls, push the new offset to every other day row,
  // the ruler, and the scrollbar — guarded by a flag to prevent re-entry.
  void _onDayScroll(ScrollController source) {
    if (_syncing || !source.hasClients) return;
    _syncing = true;
    final offset = source.offset;
    for (final c in _dayCtrl) {
      if (c != source && c.hasClients) {
        c.jumpTo(offset.clamp(0.0, c.position.maxScrollExtent));
      }
    }
    if (_rulerCtrl.hasClients) {
      _rulerCtrl.jumpTo(
          offset.clamp(0.0, _rulerCtrl.position.maxScrollExtent));
    }
    if (_scrollbarCtrl.hasClients) {
      _scrollbarCtrl.jumpTo(
          offset.clamp(0.0, _scrollbarCtrl.position.maxScrollExtent));
    }
    _syncing = false;
  }

  // When the user drags the bottom scrollbar, push to all day rows + ruler.
  void _onScrollbarScroll() {
    if (_syncing || !_scrollbarCtrl.hasClients) return;
    _syncing = true;
    final offset = _scrollbarCtrl.offset;
    for (final c in _dayCtrl) {
      if (c.hasClients) {
        c.jumpTo(offset.clamp(0.0, c.position.maxScrollExtent));
      }
    }
    if (_rulerCtrl.hasClients) {
      _rulerCtrl.jumpTo(
          offset.clamp(0.0, _rulerCtrl.position.maxScrollExtent));
    }
    _syncing = false;
  }

  void _computeWindow() {
    int? minStart;
    int? maxEnd;

    for (final bookings in widget.bookingsByDay.values) {
      for (final b in bookings) {
        final s = DateTime.tryParse(b['start_time']?.toString() ?? '');
        final e = DateTime.tryParse(b['end_time']?.toString() ?? '');
        if (s != null) {
          final m = s.hour * 60 + s.minute;
          minStart = minStart == null ? m : min(minStart!, m);
        }
        if (e != null) {
          final m = e.hour * 60 + e.minute;
          maxEnd = maxEnd == null ? m : max(maxEnd!, m);
        }
      }
    }

    if (minStart == null) {
      // No bookings — show a default window.
      _winStartMin = 7 * 60;
      _winEndMin = 18 * 60;
      return;
    }

    // Start at the earliest booking, floored to the whole hour.
    _winStartMin = (minStart! ~/ 60) * 60;

    // End at the latest booking end, ceiled to the whole hour.
    // Fall back to start + 1 h if end_time data is absent.
    final rawEnd = maxEnd ?? (minStart! + 60);
    _winEndMin = ((rawEnd + 59) ~/ 60) * 60;

    // Guarantee a minimum 3-hour visible span.
    _winEndMin = max(_winEndMin, _winStartMin + 3 * 60);
  }

  double _xFor(int minutesFromMidnight) =>
      (minutesFromMidnight - _winStartMin) * _effectivePxPerMin;

  List<List<Map<String, dynamic>>> _packLanes(
      List<Map<String, dynamic>> bookings) {
    final sorted = [...bookings]
      ..sort((a, b) {
        final ta =
            DateTime.tryParse(a['start_time']?.toString() ?? '') ?? DateTime(0);
        final tb =
            DateTime.tryParse(b['start_time']?.toString() ?? '') ?? DateTime(0);
        return ta.compareTo(tb);
      });

    final lanes = <List<Map<String, dynamic>>>[];
    final ends = <DateTime>[];

    for (final b in sorted) {
      final start = DateTime.tryParse(b['start_time']?.toString() ?? '');
      if (start == null) continue;
      final end = DateTime.tryParse(b['end_time']?.toString() ?? '') ??
          start.add(const Duration(hours: 1));

      int idx = -1;
      for (int i = 0; i < lanes.length; i++) {
        if (!ends[i].isAfter(start)) {
          idx = i;
          break;
        }
      }
      if (idx == -1) {
        lanes.add([b]);
        ends.add(end);
      } else {
        lanes[idx].add(b);
        ends[idx] = end;
      }
    }
    return lanes;
  }

  double _rowHeight(List<Map<String, dynamic>> bookings) {
    if (bookings.isEmpty) return _emptyDayH;
    return _packLanes(bookings).length * _laneH + _dayPadV * 2;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;

    final lanesByDay = <DateTime, List<List<Map<String, dynamic>>>>{};
    final rowHeights = <DateTime, double>{};
    for (final d in days) {
      final bookings = widget.bookingsByDay[d] ?? [];
      lanesByDay[d] = _packLanes(bookings);
      rowHeights[d] = _rowHeight(bookings);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Distribute available width equally across all hour columns.
        // Each column is (contentW / numHours) wide, and together they
        // fill the container exactly — no dead space on the right.
        if (constraints.maxWidth.isFinite) {
          _effectivePxPerMin =
              (constraints.maxWidth - _labelW) / (_winEndMin - _winStartMin);
        }
        final contentW = (_winEndMin - _winStartMin) * _effectivePxPerMin;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Ruler row: blank corner + hour markers ───────────────────────
            // The blank SizedBox(width: _labelW) is in the same Row as the ruler,
            // so ruler always starts at exactly the same x-offset as day content.
            SizedBox(
              height: _rulerH,
              child: Row(
                children: [
                  SizedBox(width: _labelW),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _rulerCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(width: contentW, child: _buildRuler()),
                    ),
                  ),
                ],
              ),
            ),

            // ── Day rows: label and lanes in the same Row ────────────────────
            // Because label and content share the same Row widget, their vertical
            // alignment is guaranteed by Flutter's layout — no computed offsets.
            for (int i = 0; i < days.length; i++) ...[
              if (i > 0) SizedBox(height: _dayGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Day label — explicit height matches content SizedBox exactly.
                  Container(
                    width: _labelW,
                    height: rowHeights[days[i]] ?? _emptyDayH,
                    color: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('EEE').format(days[i]),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: BrandColors.charcoal,
                          ),
                        ),
                        Text(
                          DateFormat('d MMM').format(days[i]),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  // Booking lanes — independently scrollable, all synced via
                  // _onDayScroll so dragging any row moves every other row.
                  Expanded(
                    child: SizedBox(
                      height: rowHeights[days[i]] ?? _emptyDayH,
                      child: SingleChildScrollView(
                        controller: _dayCtrl[i],
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentW,
                          child: _buildDayContent(
                            lanesByDay[days[i]] ?? [],
                            widget.unavailableByDay[days[i]] ?? [],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // ── Scrollbar row: unified scroll indicator below all day rows ───
            Row(
              children: [
                SizedBox(width: _labelW),
                Expanded(
                  child: Scrollbar(
                    controller: _scrollbarCtrl,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollbarCtrl,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: contentW, height: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildRuler() {
    final firstHour = _winStartMin ~/ 60;
    final lastHour = _winEndMin ~/ 60;

    return Stack(
      children: [
        Container(
          color: BrandColors.background,
          foregroundDecoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.black12)),
          ),
        ),
        for (int h = firstHour; h <= lastHour; h++) ...[
          Positioned(
            left: _xFor(h * 60),
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: Colors.black12),
          ),
          Positioned(
            left: _xFor(h * 60) + 4,
            top: 7,
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
          ),
        ],
      ],
    );
  }

  // Returns the Stack content for one day — height is owned by the parent
  // SizedBox in the Row, so no Container wrapper is needed here.
  Widget _buildDayContent(
    List<List<Map<String, dynamic>>> lanes,
    List<_UnavailableRange> unavailable,
  ) {
    final firstHour = _winStartMin ~/ 60;
    final lastHour = _winEndMin ~/ 60;

    return ColoredBox(
      color: Colors.white,
      child: Stack(
        children: [
          // Subtle hour grid lines
          for (int h = firstHour; h <= lastHour; h++)
            Positioned(
              left: _xFor(h * 60),
              top: 0,
              bottom: 0,
              child: Container(
                  width: 1, color: Colors.black.withOpacity(0.04)),
            ),

          // Unavailable ranges — silent grey shading only.
          for (final u in unavailable)
            Positioned(
              left: _xFor(u.start.hour * 60 + u.start.minute)
                  .clamp(0.0, (_winEndMin - _winStartMin) * _effectivePxPerMin),
              top: 0,
              bottom: 0,
              width: (u.end.difference(u.start).inMinutes * _effectivePxPerMin)
                  .clamp(0.0, (_winEndMin - _winStartMin) * _effectivePxPerMin),
              child: ColoredBox(color: Colors.black.withOpacity(0.06)),
            ),

          // Booking blocks
          for (int laneIdx = 0; laneIdx < lanes.length; laneIdx++)
            for (final b in lanes[laneIdx])
              _bookingBlock(b, laneIdx),
        ],
      ),
    );
  }

  Widget _bookingBlock(Map<String, dynamic> b, int laneIdx) {
    final start = DateTime.tryParse(b['start_time']?.toString() ?? '');
    if (start == null) return const SizedBox.shrink();
    final end = DateTime.tryParse(b['end_time']?.toString() ?? '') ??
        start.add(const Duration(hours: 1));

    final startMin = start.hour * 60 + start.minute;
    final endMin = end.hour * 60 + end.minute;
    final x = _xFor(startMin);
    final w = max(48.0, (endMin - startMin) * _effectivePxPerMin - _laneGap);
    final top = _dayPadV + laneIdx * _laneH;

    final loadType = b['vehicle_types']?['load_type']?.toString();
    final vehicleTypeName = b['vehicle_types']?['name']?.toString();
    final bg = _InboundOverviewPageState.loadTypeColor(loadType, vehicleTypeName);
    final ref = b['booking_ref']?.toString() ?? '—';
    final customer = b['customers']?['customer_code']?.toString() ?? '—';
    final bookingId = b['booking_id']?.toString();

    // bg uses alpha on the background colour only; text is painted separately
    // at full opacity so it is never affected by the background transparency.
    return Positioned(
      left: x,
      top: top,
      width: w,
      height: _laneH - _laneGap,
      child: GestureDetector(
        onTap: bookingId != null ? () => widget.onBookingTap(bookingId) : null,
        child: MouseRegion(
          cursor: bookingId != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Stack(
            children: [
              // Background layer: semi-transparent fill, no children.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              // Text layer: painted independently at full opacity.
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ref,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text(
                      customer,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Supporting Widgets ───────────────────────────────────────────────────────

class _MetricData {
  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  const _MetricData(
      {required this.label,
      required this.value,
      this.subValue,
      required this.icon});
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;
  const _MetricCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(data.icon, color: BrandColors.lightBlue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: BrandColors.deepBlue,
            ),
          ),
          if (data.subValue != null) ...[
            const SizedBox(height: 2),
            Text(
              data.subValue!,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _ArrivalCard extends StatelessWidget {
  final String bookingRef;
  final String customerCode;
  final String arrivalTime;
  final Color statusColor;
  final Color statusTextColor;
  final String formattedStatus;
  final VoidCallback? onTap;

  const _ArrivalCard({
    required this.bookingRef,
    required this.customerCode,
    required this.arrivalTime,
    required this.statusColor,
    required this.statusTextColor,
    required this.formattedStatus,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      bookingRef,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      formattedStatus,
                      style: TextStyle(
                        color: statusTextColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                customerCode,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.black45),
                  const SizedBox(width: 4),
                  Text(
                    arrivalTime,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

