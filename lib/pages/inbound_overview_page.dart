import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../layouts/app_scaffold.dart';
import '../theme/brand_colors.dart';
import 'dart:html' as html;

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
                    'updated_at': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
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

    final now = DateTime.now().toUtc();

    final response = await supabase
        .from('bookings')
        .select(
            'booking_id,start_time,reference,status,carrier,qty_pallets,qty_cases,packing_list_path,vehicle_types(name),customers(customer_code),sites(site_name)')
        .eq('status', 'booked')
        .gt('start_time', now.toIso8601String())
        .order('start_time');

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

        return Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Upcoming Deliveries:',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold),
            ),
            _buildCreateButton(),
          ],
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

    const siteW = 120.0;
    const customerW = 150.0;
    const typeW = 220.0;
    const carrierW = 180.0;
    const dateW = 110.0;
    const timeW = 90.0;
    const refW = 200.0;
    const palletsW = 90.0;
    const casesW = 90.0;
    const statusW = 110.0;
    const actionW = 400.0;

    const tableWidth =
        siteW +
        customerW +
        typeW +
        carrierW +
        dateW +
        timeW +
        refW +
        palletsW +
        casesW +
        statusW +
        actionW + 
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
                        'Reference',
                        refW),
                    headerCell(
                        'Pallets',
                        palletsW),
                    headerCell(
                        'Cases',
                        casesW),
                    headerCell(
                        'Status',
                        statusW),
                    headerCell(
                        'Actions',
                        actionW),
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
                                        'start_time'])
                                .toUtc();

                        return Container(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                                      vertical:
                                          8,
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
                                  booking['reference'] ??
                                      '',
                                  refW),
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
                              dataCell(
                                  _formatStatus(booking['status']),
                                  statusW),
                              SizedBox(
                                width: actionW,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [

                                    // EDIT
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: BrandColors.orange,
                                        foregroundColor: BrandColors.charcoal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        textStyle: const TextStyle(fontSize: 12),
                                        minimumSize: const Size(0, 30),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        elevation: 0,
                                      ),
                                      onPressed: () =>
                                          Navigator.pushNamed(
                                            context,
                                            '/booking-form',
                                            arguments: {
                                              'booking_id': booking['booking_id'],
                                            },
                                          ),
                                      child: const Text('Edit'),
                                    ),

                                    // CANCEL
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: BrandColors.red,
                                        foregroundColor: BrandColors.charcoal,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 6,
                                        ),
                                        textStyle: const TextStyle(fontSize: 12),
                                        minimumSize: const Size(0, 30),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        elevation: 0,
                                      ),
                                      onPressed: () => _confirmCancel(index),
                                      child: const Text('Cancel'),
                                    ),

                                    // DOWNLOAD
                                    if (booking['packing_list_path'] != null &&
                                        booking['packing_list_path'].toString().isNotEmpty)
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: BrandColors.green,
                                          foregroundColor: BrandColors.charcoal,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                          textStyle: const TextStyle(fontSize: 12),
                                          minimumSize: const Size(0, 30),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          elevation: 0,
                                        ),
                                        onPressed: () =>
                                            _downloadPackingList(
                                              booking['packing_list_path'],
                                            ),
                                        child: const Text('Download'),
                                      ),
                                  ],
                                ),
                              ),
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
