import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PackingListWidget extends StatefulWidget {
  final String? bookingId;
  final bool isView;
  final SupabaseClient supabase;
  final void Function(List<PlatformFile> files) onChanged;

  const PackingListWidget({
    super.key,
    this.bookingId,
    required this.isView,
    required this.supabase,
    required this.onChanged,
  });

  @override
  State<PackingListWidget> createState() => _PackingListWidgetState();
}

class _PackingListWidgetState extends State<PackingListWidget> {
  final List<PlatformFile> _queued = [];
  final Map<String, String> _fileErrors = {};
  List<Map<String, dynamic>> _existingFiles = [];
  bool _loadingExisting = false;

  static const int _maxBytes = 10 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) _loadExistingFiles();
  }

  // ---------------------------------------------------------------------------
  // Existing-files loader
  // ---------------------------------------------------------------------------

  Future<void> _loadExistingFiles() async {
    setState(() => _loadingExisting = true);
    try {
      final rows = await widget.supabase
          .from('booking_packing_lists')
          .select('id, storage_path, file_name, uploaded_at')
          .eq('booking_id', widget.bookingId!)
          .order('uploaded_at');
      if (mounted) {
        setState(() {
          _existingFiles = List<Map<String, dynamic>>.from(rows);
          _loadingExisting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // File management
  // ---------------------------------------------------------------------------

  void _addFiles(List<PlatformFile> candidates) {
    if (!mounted) return;
    final errors = <String, String>{};
    final valid = <PlatformFile>[];

    for (final f in candidates) {
      if (f.size > _maxBytes) {
        errors[f.name] = '${f.name}: exceeds 10 MB limit';
      } else {
        valid.add(f);
      }
    }

    setState(() {
      _queued.addAll(valid);
      _fileErrors
        ..clear()
        ..addAll(errors);
    });
    widget.onChanged(List.unmodifiable(_queued));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
    );
    if (result != null) _addFiles(result.files);
  }

  void _removeQueued(int index) {
    setState(() => _queued.removeAt(index));
    widget.onChanged(List.unmodifiable(_queued));
  }

  Future<void> _openExisting(Map<String, dynamic> row) async {
    try {
      final signedUrl = await widget.supabase.storage
          .from('booking-documents')
          .createSignedUrl(row['storage_path'] as String, 60);
      await launchUrl(Uri.parse(signedUrl));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open file — please try again")),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Packing List *',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),

        if (_loadingExisting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_existingFiles.isNotEmpty) ...[
          for (final f in _existingFiles) _existingFileTile(f),
          const SizedBox(height: 8),
        ],

        if (!widget.isView) ...[
          _pickButton(),

          if (_queued.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (int i = 0; i < _queued.length; i++) _queuedFileTile(i),
          ],

          if (_fileErrors.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final msg in _fileErrors.values)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  msg,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _pickButton() {
    return OutlinedButton.icon(
      icon: const Icon(Icons.folder_open, size: 18),
      label: const Text('Choose Files'),
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: _pickFiles,
    );
  }

  Widget _queuedFileTile(int index) {
    final f = _queued[index];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file, size: 18),
      title: Text(f.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${(f.size / 1024).toStringAsFixed(1)} KB',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        onPressed: () => _removeQueued(index),
        tooltip: 'Remove',
      ),
    );
  }

  Widget _existingFileTile(Map<String, dynamic> row) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.insert_drive_file, size: 18, color: Colors.green),
      title: Text(
        row['file_name'] as String? ?? '—',
        style: const TextStyle(fontSize: 13),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download, size: 16),
        onPressed: () => _openExisting(row),
        tooltip: 'Download',
      ),
    );
  }
}
