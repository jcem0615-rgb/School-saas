import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/audit_log_entry.dart';
import '../controllers/audit_trail_controller.dart';

final _dateTimeFormat = DateFormat.yMMMd().add_jm();

const _moduleOptions = [
  'users',
  'announcements',
  'meetings',
  'approvals',
  'expenses',
  'attendance',
  'payments',
  'subscription',
];

/// Every write this build makes to a tenant CRUD collection is captured
/// automatically by the generic `onAnyTenantDocWrite` trigger (Module 6)
/// or by a dedicated callable's explicit `writeAuditLog` call (Auth,
/// Owner Portal, Payments). This screen is the read/search surface over
/// that data -- PDF/Excel export and restore-from-soft-delete are Reports
/// & Documents module concerns, not duplicated here.
class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  String? _moduleFilter;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final logAsync = ref.watch(auditLogStreamProvider(AuditTrailFilter(module: _moduleFilter)));

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Trail')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by user or remarks...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Modules'),
                    selected: _moduleFilter == null,
                    onSelected: (_) => setState(() => _moduleFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ..._moduleOptions.map((m) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(m),
                          selected: _moduleFilter == m,
                          onSelected: (_) => setState(() => _moduleFilter = m),
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load audit trail: $err')),
              data: (entries) {
                final filtered = _searchQuery.isEmpty
                    ? entries
                    : entries
                        .where((e) =>
                            e.userName.toLowerCase().contains(_searchQuery) ||
                            (e.remarks?.toLowerCase().contains(_searchQuery) ?? false))
                        .toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No matching audit entries.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _AuditTile(entry: filtered[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final AuditLogEntry entry;
  const _AuditTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        entry.success ? Icons.check_circle_outline : Icons.error_outline,
        color: entry.success ? Colors.green : Colors.red,
      ),
      title: Text('${entry.userName} · ${entry.action}'),
      subtitle: Text(
        '${entry.module} / ${entry.targetId}\n${_dateTimeFormat.format(entry.timestamp)}'
        '${entry.remarks != null ? '\n${entry.remarks}' : ''}',
      ),
      isThreeLine: entry.remarks != null,
      trailing: Text(entry.userRole, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
