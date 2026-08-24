import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controllers/audit_trail_controller.dart';

final _dateTimeFormat = DateFormat.yMMMd().add_jm();

/// Every role's personal "Activity History" (General Requirement, spec
/// section "Every user must have..."). Distinct from [AuditTrailScreen],
/// which shows the whole school's activity and is restricted to
/// Owner/Director/Admin.
class MyActivityScreen extends ConsumerWidget {
  const MyActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(myActivityStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Activity History')),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load activity: $err')),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(child: Text('No activity recorded yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final e = entries[index];
              return ListTile(
                leading: Icon(
                  e.success ? Icons.check_circle_outline : Icons.error_outline,
                  color: e.success ? Colors.green : Colors.red,
                ),
                title: Text('${e.module} · ${e.action}'),
                subtitle: Text(_dateTimeFormat.format(e.timestamp)),
              );
            },
          );
        },
      ),
    );
  }
}
