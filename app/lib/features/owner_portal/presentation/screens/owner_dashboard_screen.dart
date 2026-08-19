import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/school_summary.dart';
import '../controllers/owner_controller.dart';
import '../widgets/revenue_card.dart';
import '../widgets/school_status_badge.dart';
import 'school_list_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Landing screen for the Owner role. Shows platform-wide revenue at a
/// glance and surfaces schools that need attention (grace period /
/// suspended) without requiring a drill-down -- this is the screen an
/// Owner checks daily, so anything actionable should be visible without
/// scrolling on a typical tablet/desktop viewport.
class OwnerDashboardScreen extends ConsumerWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revenueAsync = ref.watch(revenueSummaryStreamProvider);
    final schoolsAsync = ref.watch(schoolsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Owner Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(revenueSummaryStreamProvider);
          ref.invalidate(schoolsStreamProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Revenue', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              revenueAsync.when(
                loading: () => const _RevenueSkeleton(),
                error: (err, _) => Text('Failed to load revenue: $err'),
                data: (summary) => LayoutBuilder(builder: (context, constraints) {
                  final columns = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 560 ? 2 : 1);
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.6,
                    children: [
                      RevenueCard(
                        label: 'Daily Revenue',
                        value: _currencyFormat.format(summary.dailyRevenue),
                        icon: Icons.today_outlined,
                      ),
                      RevenueCard(
                        label: 'Monthly Revenue',
                        value: _currencyFormat.format(summary.monthlyRevenue),
                        icon: Icons.calendar_month_outlined,
                      ),
                      RevenueCard(
                        label: 'Yearly Revenue',
                        value: _currencyFormat.format(summary.yearlyRevenue),
                        icon: Icons.trending_up,
                      ),
                      RevenueCard(
                        label: 'Active Students (all schools)',
                        value: NumberFormat.decimalPattern().format(summary.totalActiveStudents),
                        icon: Icons.groups_outlined,
                      ),
                    ],
                  );
                }),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Needs Attention', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SchoolListScreen()),
                    ),
                    child: const Text('View all schools'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              schoolsAsync.when(
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )),
                error: (err, _) => Text('Failed to load schools: $err'),
                data: (schools) {
                  final needsAttention = schools
                      .where((s) => s.status != SchoolSubscriptionStatus.active)
                      .toList();
                  if (needsAttention.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('All schools are in good standing.'),
                    );
                  }
                  return Column(
                    children: needsAttention.map((school) {
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(school.name),
                          subtitle: Text('${school.activeStudentCount} active students'),
                          trailing: SchoolStatusBadge(status: school.status),
                          onTap: () => context.push('/owner/schools/${school.id}'),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueSkeleton extends StatelessWidget {
  const _RevenueSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 100,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
