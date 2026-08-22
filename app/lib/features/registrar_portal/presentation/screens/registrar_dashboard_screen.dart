import 'package:flutter/material.dart';

import '../../../payments/presentation/screens/payment_review_screen.dart';
import '../../../payments/presentation/screens/payment_settings_screen.dart';
import 'student_list_screen.dart';
import '../../../audit_trail/presentation/screens/my_activity_screen.dart';
import '../../../../core/widgets/glass_tile.dart';

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
                GlassTile(
                  icon: Icons.how_to_reg_outlined,
                  label: 'Student Records',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const StudentListScreen())),
                ),
                GlassTile(
                  icon: Icons.fact_check_outlined,
                  label: 'Online Payments',
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const PaymentReviewScreen())),
                ),
                GlassTile(
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
