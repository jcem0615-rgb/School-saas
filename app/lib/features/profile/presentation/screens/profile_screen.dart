import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/profile_controller.dart';

/// Every role's Profile screen (General Requirement). Shows identity
/// fields as read-only (name, role, email -- these are staff/admin-
/// managed, not self-editable, per the firestore.rules field boundary
/// established in Module 4) and allows editing only what the rules
/// actually permit: phone number and photo URL.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _phoneController = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final success =
        await ref.read(profileActionControllerProvider.notifier).updateProfile(phone: _phoneController.text);
    if (!mounted) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Profile updated.' : 'Failed to update profile.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
              child: user.photoUrl == null ? const Icon(Icons.person, size: 40) : null,
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.fullName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text(user.role.displayName, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: 32),
          _InfoTile(label: 'Email', value: user.email),
          const SizedBox(height: 8),
          if (_editing)
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
            )
          else
            _InfoTile(label: 'Phone', value: _phoneController.text.isEmpty ? 'Not set' : _phoneController.text),
          const SizedBox(height: 16),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          const Divider(height: 40),
          Text('More', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('My QR ID'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/qr-id'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('My Activity History'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/my-activity'),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('My Attendance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/my-attendance'),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
