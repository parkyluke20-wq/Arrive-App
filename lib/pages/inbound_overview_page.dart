import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';
import 'dart:html' as html;
import '../pages/booking_form_page.dart';

class InboundOverviewPage extends StatefulWidget {
  const InboundOverviewPage({super.key});

  @override
  State<InboundOverviewPage> createState() =>
      _InboundOverviewPageState();
}

class _InboundOverviewPageState
    extends State<InboundOverviewPage> {
  final supabase = Supabase.instance.client;

  final ScrollController _horizontalController =
      ScrollController();

  bool _loading = true;
  List<Map<String, dynamic>> _bookings = [];
  bool _didHandleRouteArgs = false;
  String _formatStatus(String? status) {
    if (status == null) return '—';
    return status.replaceAll('_', ' ').split(' ')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didHandleRouteArgs) return;
    _didHandleRouteArgs = true;

    final args =
    ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      if (args != null && args['booking_confirmed'] == true) {
      final wasEdit = args['was_edit'] == true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              wasEdit
                  ? 'Booking updated successfully'
                  : 'Booking confirmed successfully',
            ),
          ),
        );
      });
    } 
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  void _confirmCancel(int index) {
    final booking = _bookings[index];
    final bookingId = booking['booking_id'];

    if (bookingId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking'),
        content: const Text(
          'Are you sure you want to cancel this booking?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              await supabase
                  .from('bookings')
                  .update({
                    'status': 'cancelled',
                    'updated_at': DateTime.now().toIso8601String(),
                  })
                  .eq('booking_id', bookingId);

              await _loadBookings();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadBookings() async {
    if (!mounted) return;

    setState(() => _loading = true);

    final now = DateTime.now();

    final response = await supabase
        .from('bookings')
        .select(
            'booking_id,start_time,reference,status,carrier,qty_pallets,qty_cases,packing_list_path,vehicle_types(name),customers(customer_code),sites(site_name)')
        .eq('status', 'booked')
        .gt('start_time', now.toIso8601String())
        .order('start_time', ascending: true);

    if (!mounted) return;

    setState(() {
      _bookings = List<Map<String, dynamic>>.from(response);
      _loading = false;
    });
  }

  Future<void> _downloadPackingList(String path) async {
    final signedUrl = await supabase.storage
        .from('booking-documents')
        .createSignedUrl(path, 60);

    final anchor = html.AnchorElement(href: signedUrl)
      ..setAttribute('download', '')
      ..click();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Inbound Overview',
      body: Padding(
        padding:
            const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _buildTable(),
                  ),
                ],
              ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // HEADER (Overflow Safe)
  // ─────────────────────────────────────────────

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight =
            constraints.maxWidth < 900;

        if (tight) {
          return Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Upcoming Deliveries:',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight:
                        FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildCreateButton(),
            ],
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1530),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Upcoming Deliveries:',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildCreateButton(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateButton() {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            BrandColors.lightBlue,
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(
                horizontal: 26,
                vertical: 20),
      ),
      onPressed: () =>
          Navigator.pushNamed(
              context, '/booking-form'),
      icon: const Icon(Icons.add),
      label: Text(
        'Book a Delivery',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TABLE (Fixed Width + Horizontal Scroll)
  // ─────────────────────────────────────────────

  Widget _buildTable() {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');

    const actionW = 150.0;
    const refW = 200.0;
    const statusW = 110.0;
    const siteW = 120.0;
    const customerW = 150.0;
    const typeW = 220.0;
    const carrierW = 180.0;
    const dateW = 110.0;
    const timeW = 90.0;
    const palletsW = 90.0;
    const casesW = 90.0;

    const tableWidth =
        actionW + 
        refW +
        statusW +
        siteW +
        customerW +
        typeW +
        carrierW +
        dateW +
        timeW +
        palletsW +
        casesW +
        24;

    Widget headerCell(
            String text, double width) =>
        SizedBox(
          width: width,
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight:
                  FontWeight.w500,
            ),
          ),
        );

    Widget dataCell(
            String text, double width) =>
        SizedBox(
          width: width,
          child: Text(
            text,
            overflow:
                TextOverflow.ellipsis,
          ),
        );

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

              // HEADER ROW
              Container(
                color:
                    BrandColors.lightBlue,
                padding:
                    const EdgeInsets
                        .symmetric(
                            vertical: 10,
                            horizontal: 12),
                child: Row(
                  children: [
                    headerCell(
                        'Actions',
                        actionW),
                    headerCell(
                        'Reference',
                        refW),
                    headerCell(
                        'Status',
                        statusW),
                    headerCell(
                        'Site', siteW),
                    headerCell(
                        'Customer',
                        customerW),
                    headerCell(
                        'Type', typeW),
                    headerCell(
                        'Carrier',
                        carrierW),
                    headerCell(
                        'Date', dateW),
                    headerCell(
                        'Time', timeW),
                    headerCell(
                        'Pallets',
                        palletsW),
                    headerCell(
                        'Cases',
                        casesW),
                  ],
                ),
              ),

              // BODY
              Expanded(
                child:
                    SingleChildScrollView(
                  child: Column(
                    children:
                        List.generate(
                      _bookings.length,
                      (index) {
                        final booking =
                            _bookings[index];
                        final startTime =
                            DateTime.parse(
                                    booking[
                                        'start_time']);

                        return Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                                      vertical:
                                          4,
                                      horizontal:
                                          12),
                          decoration:
                              const BoxDecoration(
                            border: Border(
                              bottom:
                                  BorderSide(
                                color: Colors
                                    .black12,
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
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          '/booking-form',
                                          arguments: {
                                            'booking_id': booking['booking_id'],
                                            'mode': BookingFormMode.view,
                                          },
                                        ),
                                      ),
                                    ),
                                    // CANCEL
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
                                    // DOWNLOAD
                                    if (booking['packing_list_path'] != null &&
                                        booking['packing_list_path'].toString().isNotEmpty)
                                      Tooltip(
                                        message: 'Download Packing List',
                                        child: IconButton(
                                          icon: const Icon(Icons.download),
                                          color: BrandColors.green,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                            minHeight: 28,
                                          ),
                                          onPressed: () => _downloadPackingList(
                                            booking['packing_list_path'],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              dataCell(
                                  booking['reference'] ??
                                      '',
                                  refW),
                              dataCell(
                                  _formatStatus(booking['status']),
                                  statusW),
                              dataCell(
                                  booking[
                                          'sites']
                                      ?[
                                          'site_name'] ??
                                      '—',
                                  siteW),
                              dataCell(
                                  booking[
                                          'customers']
                                      ?[
                                          'customer_code'] ??
                                      '—',
                                  customerW),
                              dataCell(
                                  booking[
                                          'vehicle_types']
                                      ?['name'] ??
                                      '—',
                                  typeW),
                              dataCell(
                                  booking[
                                          'carrier']
                                      ?.toString() ??
                                      '',
                                  carrierW),
                              dataCell(
                                  dateFmt.format(
                                      startTime),
                                  dateW),
                              dataCell(
                                  timeFmt.format(
                                      startTime),
                                  timeW),
                              dataCell(
                                  booking['qty_pallets']
                                      ?.toString() ??
                                      '',
                                  palletsW),
                              dataCell(
                                  booking['qty_cases']
                                      ?.toString() ??
                                      '',
                                  casesW),
                            ],
                          ),
                        );
                      },
                    ),
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
