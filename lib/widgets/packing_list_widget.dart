import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PackingListWidget extends StatefulWidget {
  final String? initialExistingPath;
  final bool isView;
  final SupabaseClient supabase;
  final void Function(PlatformFile? file, bool removed) onChanged;

  const PackingListWidget({
    super.key,
    this.initialExistingPath,
    required this.isView,
    required this.supabase,
    required this.onChanged,
  });

  @override
  State<PackingListWidget> createState() => _PackingListWidgetState();
}

class _PackingListWidgetState extends State<PackingListWidget> {
  PlatformFile? _file;
  bool _removed = false;

  bool get _hasExisting => widget.initialExistingPath != null && !_removed;
  bool get _hasNew => _file != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _mainButton(),
        if (_hasExisting) ...[
          const SizedBox(height: 12),
          _secondaryActions(),
        ],
      ],
    );
  }

  Widget _mainButton() {
    final String label;
    if (_hasNew) {
      label = _file!.name;
    } else if (_hasExisting) {
      label = 'Replace Packing List';
    } else {
      label = 'Upload Packing List *';
    }

    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.upload_file, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        onPressed: () async {
          if (widget.isView) return;

          final result = await FilePicker.platform.pickFiles(withData: true);

          if (result != null) {
            setState(() {
              _file = result.files.first;
              _removed = false;
            });
            widget.onChanged(_file, _removed);
          }
        },
      ),
    );
  }

  Widget _secondaryActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_hasNew)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton(
              onPressed: () async {
                try {
                  final signedUrl = await widget.supabase.storage
                      .from('booking-documents')
                      .createSignedUrl(widget.initialExistingPath!, 60);

                  await launchUrl(Uri.parse(signedUrl));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Couldn't open packing list — please try again"),
                    ),
                  );
                }
              },
              child: const Text('View Existing Packing List'),
            ),
          ),

        if (!widget.isView)
          TextButton(
            onPressed: () {
              setState(() {
                _removed = true;
                _file = null;
              });
              widget.onChanged(null, true);
            },
            child: const Text('Remove Packing List'),
          ),
      ],
    );
  }
}
