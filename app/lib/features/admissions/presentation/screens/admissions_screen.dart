import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../domain/entities/applicant.dart';
import '../controllers/admissions_controller.dart';
import 'applicant_detail_screen.dart';

final _dateFormat = DateFormat.yMMMd();

/// The admissions pipeline.
///
/// A private school's year is won or lost between January and June, and
/// what loses it is not a decision -- it is a family who enquired in
/// February, was never rung back, and enrolled somewhere else in April.
/// So the first thing on this screen is not the list: it is the count of
/// families nobody has spoken to in a week.
class AdmissionsScreen extends ConsumerStatefulWidget {
  const AdmissionsScreen({super.key});

  @override
  ConsumerState<AdmissionsScreen> createState() => _AdmissionsScreenState();
}

class _AdmissionsScreenState extends ConsumerState<AdmissionsScreen> {
  /// Null means every open applicant. The two endings are behind their
  /// own filter rather than mixed in: a list that shows the families who
  /// went elsewhere alongside the ones still in play is a list that
  /// overstates the pipeline every time somebody looks at it.
  AdmissionStage? _stageFilter;
  bool _showClosed = false;
  bool _followUpOnly = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applicantsAsync = ref.watch(applicantsStreamProvider);
    final funnel = ref.watch(admissionFunnelProvider);
    final followUp = ref.watch(applicantsNeedingFollowUpProvider);
    final followUpIds = {for (final a in followUp) a.id};

    ref.listen(admissionsActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Admissions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ApplicantDetailScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New enquiry'),
      ),
      body: applicantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load enquiries: $error')),
        data: (applicants) {
          final visible = applicants.where((a) {
            if (_followUpOnly) return followUpIds.contains(a.id);
            if (_stageFilter != null) return a.stage == _stageFilter;
            return _showClosed ? a.stage.isClosed : a.stage.isOpen;
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _FunnelCard(funnel: funnel),
              const SizedBox(height: 12),
              if (followUp.isNotEmpty)
                Card(
                  color: theme.colorScheme.tertiaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.phone_in_talk_outlined),
                    title: Text('${followUp.length} to ring back'),
                    subtitle: Text(
                      'Open enquiries nobody has moved in '
                      '$admissionFollowUpDays days or more.',
                    ),
                    trailing: Switch(
                      value: _followUpOnly,
                      onChanged: (value) => setState(() {
                        _followUpOnly = value;
                        if (value) _stageFilter = null;
                      }),
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Stage filters, with the count on each. The counts are the
              // point: a chip reading "Offered 0" tells the office where
              // the pipeline has dried up.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  FilterChip(
                    label: Text('Open ${funnel.open}'),
                    selected: !_showClosed && _stageFilter == null && !_followUpOnly,
                    onSelected: (_) => setState(() {
                      _stageFilter = null;
                      _showClosed = false;
                      _followUpOnly = false;
                    }),
                  ),
                  const SizedBox(width: 8),
                  for (final stage in admissionPipeline) ...[
                    FilterChip(
                      label: Text('${stage.displayLabel} ${funnel.nowIn[stage] ?? 0}'),
                      selected: _stageFilter == stage && !_followUpOnly,
                      onSelected: (_) => setState(() {
                        _stageFilter = stage;
                        _showClosed = false;
                        _followUpOnly = false;
                      }),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilterChip(
                    label: Text(
                      'Closed ${funnel.declined + funnel.withdrawn}',
                    ),
                    selected: _showClosed && !_followUpOnly,
                    onSelected: (_) => setState(() {
                      _showClosed = true;
                      _stageFilter = null;
                      _followUpOnly = false;
                    }),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    applicants.isEmpty
                        ? 'No enquiries yet. Take the next phone call down here '
                            'and the family stops being a note on paper.'
                        : 'Nothing in this part of the pipeline.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              else
                for (final applicant in visible)
                  _ApplicantTile(
                    applicant: applicant,
                    needsFollowUp: followUpIds.contains(applicant.id),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _FunnelCard extends StatelessWidget {
  final AdmissionFunnel funnel;
  const _FunnelCard({required this.funnel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = funnel.conversionRate;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rate == null ? 'No enquiries yet' : '$rate% enrol',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${funnel.enrolled} enrolled of ${funnel.total} enquiries · '
              '${funnel.open} still open',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 4),
            // Said apart, because "we turned down forty" and "forty
            // walked away" are different problems and only one of them
            // is the school's doing.
            Text(
              '${funnel.declined} not accepted · ${funnel.withdrawn} went elsewhere',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicantTile extends StatelessWidget {
  final Applicant applicant;
  final bool needsFollowUp;

  const _ApplicantTile({required this.applicant, required this.needsFollowUp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = applicant.daysInStage(DateTime.now());

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: needsFollowUp
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(child: Text(applicant.firstName.characters.first)),
        title: Text(applicant.fullName),
        subtitle: Text(
          '${applicant.referenceNumber} · ${applicant.gradeLevel} '
          '${applicant.educationLevel.shortLabel}\n'
          '${applicant.stage.displayLabel}'
          '${days == 0 ? ' today' : ' for $days day${days == 1 ? '' : 's'}'}'
          '${applicant.examPercentage == null ? '' : ' · exam ${applicant.examPercentage}%'}',
        ),
        isThreeLine: true,
        trailing: needsFollowUp
            ? Icon(Icons.phone_in_talk_outlined, color: theme.colorScheme.tertiary)
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApplicantDetailScreen(applicant: applicant),
          ),
        ),
      ),
    );
  }
}

/// Formats a date for the detail screen, kept here so both screens agree.
String formatAdmissionDate(DateTime value) => _dateFormat.format(value);
