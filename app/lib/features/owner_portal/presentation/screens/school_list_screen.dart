import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/school_summary.dart';
import '../controllers/owner_controller.dart';
import '../widgets/school_status_badge.dart';

/// Owner's "School Management" screen: every tenant on the platform, with
/// status filter tabs (All / Active / Grace Period / Suspended) and a
/// search box. Tapping a row drills into SchoolDetailScreen for
/// pause/resume actions and that school's billing history.
class SchoolListScreen extends ConsumerStatefulWidget {
  const SchoolListScreen({super.key});

  @override
  ConsumerState<SchoolListScreen> createState() => _SchoolListScreenState();
}

class _SchoolListScreenState extends ConsumerState<SchoolListScreen> {
  SchoolSubscriptionStatus? _filter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final schoolsAsync = ref.watch(schoolsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('School Management')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search schools...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(label: 'All', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Active',
                    selected: _filter == SchoolSubscriptionStatus.active,
                    onTap: () => setState(() => _filter = SchoolSubscriptionStatus.active),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Grace Period',
                    selected: _filter == SchoolSubscriptionStatus.gracePeriod,
                    onTap: () => setState(() => _filter = SchoolSubscriptionStatus.gracePeriod),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Suspended',
                    selected: _filter == SchoolSubscriptionStatus.suspended,
                    onTap: () => setState(() => _filter = SchoolSubscriptionStatus.suspended),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: schoolsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load schools: $err')),
              data: (schools) {
                final filtered = schools.where((s) {
                  final matchesFilter = _filter == null || s.status == _filter;
                  final matchesQuery = _query.isEmpty || s.name.toLowerCase().contains(_query);
                  return matchesFilter && matchesQuery;
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No schools match your filters.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final school = filtered[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: school.logoUrl != null ? NetworkImage(school.logoUrl!) : null,
                          child: school.logoUrl == null ? const Icon(Icons.school_outlined) : null,
                        ),
                        title: Text(school.name),
                        subtitle: Text('${school.activeStudentCount} active students'),
                        trailing: SchoolStatusBadge(status: school.status),
                        onTap: () => context.push('/owner/schools/${school.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}
