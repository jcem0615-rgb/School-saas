import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../payments/presentation/screens/payment_review_screen.dart';
import '../../../payments/presentation/screens/payment_settings_screen.dart';
import 'student_list_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';

/// Landing screen for the Registrar/Cashier role. Student Registration
/// and Student Records/History are new this module. Payment Collection,
/// Receipts, and Balances reuse the screens built in the Payments module
/// directly from Student Detail -- no separate "Payments" entry point is
/// needed here since payments are always keyed by student. TOR, Form 137,
/// and printable Student IDs require PDF generation and are deferred to
/// the Documents module.
class RegistrarDashboardScreen extends StatelessWidget {
  const RegistrarDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'My Activity',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyActivityScreen())),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickLinkTile(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Student Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StudentListScreen())),
                ),
                _QuickLinkTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan Attendance',
                  onTap: () => context.push('/scan-attendance'),
                ),

                _QuickLinkTile(

                  icon: Icons.fact_check_outlined,

                  label: 'Online Payments',

                  onTap: () => Navigator.of(context)

                      .push(MaterialPageRoute(builder: (_) => const PaymentReviewScreen())),

                ),

                _QuickLinkTile(

                  icon: Icons.qr_code_2,

                  label: 'Payment Setup',

                  onTap: () => Navigator.of(context)

                      .push(MaterialPageRoute(builder: (_) => const PaymentSettingsScreen())),

                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickLinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
