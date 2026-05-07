import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/brand_colors.dart';

class BookingActivityPanel extends StatefulWidget {
  final String? bookingId;
  final SupabaseClient supabase;

  const BookingActivityPanel({
    super.key,
    required this.bookingId,
    required this.supabase,
  });

  @override
  State<BookingActivityPanel> createState() => BookingActivityPanelState();
}

class BookingActivityPanelState extends State<BookingActivityPanel> {
  Future<List<Map<String, dynamic>>>? _eventsFuture;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      _eventsFuture = _fetchBookingEvents();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBookingEvents() async {
    if (widget.bookingId == null) return [];

    try {
      final response = await widget.supabase
          .from('booking_events_view')
          .select()
          .eq('booking_id', widget.bookingId!)
          .order('event_timestamp', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (!mounted) return [];
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Couldn't load booking activity — please try again")),
      );
      return [];
    }
  }

  void _refreshEventsPanel() {
    setState(() {
      _eventsFuture = _fetchBookingEvents();
    });
  }

  Future<void> addComment() async {
    if (widget.bookingId == null) return;

    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: BrandColors.background,
          title: const Text('Add Comment'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Enter comment...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(dialogContext).pop(text);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    await _insertComment(result);
  }

  Future<void> _insertComment(String comment) async {
    final user = widget.supabase.auth.currentUser;

    if (user == null || widget.bookingId == null) return;

    try {
      await widget.supabase.from('booking_events').insert({
        'booking_id': widget.bookingId,
        'event_type': 'comment_added',
        'user_id': user.id,
        'audit_text': comment,
      });

      _refreshEventsPanel();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't add comment — please try again")),
      );
    }
  }

  Widget _eventRow(Map<String, dynamic> e) {
    final timestamp = DateTime.parse(e['event_timestamp']);
    final isComment = e['event_type'] == 'comment_added';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                e['user_name'] ?? 'System',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                DateFormat('dd/MM/yyyy HH:mm').format(timestamp),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),

          const SizedBox(height: 4),

          if (isComment)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'COMMENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),

          Text(
            e['audit_text'] ?? '',
            overflow: TextOverflow.visible,
            softWrap: true,
          ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bookingId == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Booking Activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _eventsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final events = snapshot.data!;

                if (events.isEmpty) {
                  return const Center(child: Text('No activity recorded'));
                }

                return ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) => _eventRow(events[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
