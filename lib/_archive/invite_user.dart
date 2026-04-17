// 1. State

  final TextEditingController inviteEmailController = TextEditingController();

// 2. Invite Method


  Future<void> _inviteUser() async {
    final email = inviteEmailController.text.trim();
    if (email.isEmpty) return;

    int? inviteCustomerId;

    if (effectiveRole == EffectiveRole.customerAdmin ||
        effectiveRole == EffectiveRole.customerUser) {
      inviteCustomerId =
          customers.isNotEmpty ? customers.first['customer_id'] : null;
    } else {
      inviteCustomerId = selectedCustomerId;
    }

    if (inviteCustomerId == null) return;

    final customerName = customers
        .firstWhere((c) => c['customer_id'] == inviteCustomerId)['customer_name'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Invite'),
        content: Text('Invite $email to $customerName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Invite'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await supabase.from('invites').upsert(
      {
        'email': email,
        'role': 'customer_user',
        'scope_type': 'customer',
        'scope_type_id': inviteCustomerId,
        'created_by': currentUserId,
      },
      onConflict: 'email',
    );

    inviteEmailController.clear();
    _snack('Invite sent');
  }



// 3. UI Block

if (effectiveRole != EffectiveRole.supplierUser) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Invite User',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),