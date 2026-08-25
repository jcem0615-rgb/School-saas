import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../domain/entities/document_release.dart';
import '../../domain/entities/student_summary.dart';
import '../controllers/registrar_controller.dart';
import '../documents/academic_record_pdf.dart';

final _dateTimeFormat = DateFormat('d MMM y, h:mm a');

/// Printing a TOR or Form 137, and the record of every time one was.
///
/// The two live on one screen because they are one act. A registrar's
/// office is asked "when did we release this and to whom", and the only
/// way that question has an answer is if logging it is not a separate
/// thing somebody has to remember to do afterwards -- so the button that
/// prints the document is the button that writes the log.
class DocumentReleaseScreen extends ConsumerStatefulWidget {
  final StudentSummary student;
  const DocumentReleaseScreen({super.key, required this.student});

  @override
  ConsumerState<DocumentReleaseScreen> createState() => _DocumentReleaseScreenState();
}

class _DocumentReleaseScreenState extends ConsumerState<DocumentReleaseScreen> {
  SchoolDocument _document = SchoolDocument.transcriptOfRecords;
  final _purposeController = TextEditingController();
  final _releasedToController = TextEditingController();
  final _relationController = TextEditingController();
  final _remarksController = TextEditingController();
  int _copies = 1;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // The student is who collects their own document more often than
    // not, so that is what the field starts as -- still editable, and
    // still recorded as whatever it ends up saying.
    _releasedToController.text = widget.student.fullName;
  }

  @override
  void dispose() {
    _purposeController.dispose();
    _releasedToController.dispose();
    _relationController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  /// Records the release, then prints.
  ///
  /// In that order, deliberately. A print dialog that is cancelled
  /// leaves a logged release the registrar can see and annotate; a log
  /// written only after a successful print leaves no trace at all when
  /// the write is the thing that fails -- and a document that left the
  /// office with no record of it is the failure this screen exists to
  /// prevent.
  Future<void> _releaseAndPrint() async {
    final purpose = _purposeController.text.trim();
    final releasedTo = _releasedToController.text.trim();
    if (purpose.isEmpty || releasedTo.isEmpty) {
      _say('Fill in the purpose and who is collecting it.');
      return;
    }

    setState(() => _working = true);
    final recorded = await ref.read(registrarActionControllerProvider.notifier).recordDocumentRelease(
          studentId: widget.student.id,
          studentName: widget.student.fullName,
          document: _document,
          copies: _copies,
          purpose: purpose,
          releasedToName: releasedTo,
          releasedToRelation: _relationController.text,
          remarks: _remarksController.text,
        );
    if (!mounted) return;
    if (!recorded) {
      setState(() => _working = false);
      return; // The controller listener has already shown why.
    }

    await _print(purpose: purpose, releasedTo: releasedTo, copies: _copies);
    if (!mounted) return;
    setState(() => _working = false);

    _purposeController.clear();
    _remarksController.clear();
    _say('Released and logged.');
  }

  Future<void> _print({
    required String? purpose,
    required String? releasedTo,
    required int copies,
    SchoolDocument? document,
  }) async {
    // Read, not watched, because printing is an action -- but build()
    // watches both of these so that by the time this runs they have
    // arrived. brandingProvider in particular is not autoDispose and
    // would otherwise be subscribed for the first time right here,
    // returning nothing: the first document printed after opening the
    // screen would come out with no letterhead and no principal.
    final branding = ref.read(brandingProvider).valueOrNull ?? SchoolBranding.empty;
    final grades = ref.read(studentGradesStreamProvider(widget.student.id)).valueOrNull ??
        const <Grade>[];
    final registrarName = ref.read(authStateProvider).valueOrNull?.fullName ?? 'Registrar';

    await AcademicRecordPdf.print(
      document: document ?? _document,
      student: widget.student,
      branding: branding,
      grades: grades,
      registrarName: registrarName,
      purpose: purpose,
      releasedToName: releasedTo,
      copies: copies,
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gradesAsync = ref.watch(studentGradesStreamProvider(widget.student.id));
    final releasesAsync = ref.watch(documentReleasesStreamProvider(widget.student.id));
    // Watched purely so the letterhead and the principal's signature are
    // loaded before anybody presses print. See _print.
    final branding = ref.watch(brandingProvider).valueOrNull;

    ref.listen(registrarActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Records & Forms')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.student.fullName, style: theme.textTheme.titleLarge),
          Text(
            '${widget.student.studentNumber} · ${widget.student.classLabel}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),

          Text('Document', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<SchoolDocument>(
            segments: SchoolDocument.values
                .map((d) => ButtonSegment(value: d, label: Text(d.displayLabel)))
                .toList(),
            selected: {_document},
            onSelectionChanged: (v) => setState(() => _document = v.first),
          ),
          const SizedBox(height: 12),

          // What is actually on the sheet, said before it is printed
          // rather than discovered afterwards. A registrar handing over a
          // transcript with one quarter on it should know that is what
          // they are handing over.
          gradesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not read this student\'s marks: $e'),
            data: (grades) => _MarksSummary(grades: grades),
          ),
          const SizedBox(height: 20),

          Text('Release Details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _purposeController,
            decoration: const InputDecoration(
              labelText: 'Purpose',
              hintText: 'Transfer to Santa Rosa NHS, college application…',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _releasedToController,
            decoration: const InputDecoration(labelText: 'Released to'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _relationController,
            decoration: const InputDecoration(
              labelText: 'Relationship (optional)',
              hintText: 'Mother, guardian, authorised representative…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Copies'),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_copies', style: theme.textTheme.titleMedium),
              IconButton(
                onPressed: _copies < 20 ? () => setState(() => _copies++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _remarksController,
            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working ? null : _releaseAndPrint,
            icon: _working
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.print_outlined),
            label: Text('Release & print ${_document.displayLabel}'),
          ),
          const SizedBox(height: 6),
          Text(
            'The release is logged first, so a document never leaves this '
            'office without a record of it. Cancelling the print dialog '
            'does not undo the log — print it again from the history below.',
            style: theme.textTheme.bodySmall,
          ),
          // Said before printing, not discovered after. A document that
          // comes out with a blank signature line is one somebody has to
          // walk back to the office with.
          if (branding != null && !branding.hasPrincipalSignature)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                branding.principalName == null
                    ? 'No principal is set under Branding, so the document '
                        'will print with a blank signature line.'
                    : 'No signature scan is on file for '
                        '${branding.principalName}, so the document will print '
                        'with a blank line above their name to sign by hand.',
                style: theme.textTheme.bodySmall,
              ),
            ),

          const Divider(height: 40),
          Text('Release History', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Every time this student\'s records left the office.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          releasesAsync.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('Could not read the release history: $e'),
            data: (releases) => releases.isEmpty
                ? Text(
                    'Nothing has been released for this student yet.',
                    style: theme.textTheme.bodyMedium,
                  )
                : Column(
                    children: [
                      for (final r in releases)
                        _ReleaseTile(
                          release: r,
                          onReprint: _working
                              ? null
                              : () => _print(
                                    document: r.document,
                                    purpose: r.purpose,
                                    releasedTo: r.releasedToName,
                                    copies: r.copies,
                                  ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// What the printed record will contain, before it is printed.
class _MarksSummary extends StatelessWidget {
  final List<Grade> grades;
  const _MarksSummary({required this.grades});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (grades.isEmpty) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No marks have been encoded for this student. The document will '
            'print with an empty scholastic record.',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
        ),
      );
    }

    final terms = <String>{for (final g in grades) g.term};
    final subjects = <String>{for (final g in grades) g.subject};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.grading_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${grades.length} mark${grades.length == 1 ? '' : 's'} on file — '
                '${subjects.length} subject${subjects.length == 1 ? '' : 's'} '
                'across ${terms.length} term${terms.length == 1 ? '' : 's'} '
                '(${(terms.toList()..sort()).join(', ')}).',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  final DocumentRelease release;
  final VoidCallback? onReprint;

  const _ReleaseTile({required this.release, required this.onReprint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    release.copies > 1
                        ? '${release.document.displayLabel} × ${release.copies}'
                        : release.document.displayLabel,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  _dateTimeFormat.format(release.releasedAt),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('For: ${release.purpose}', style: theme.textTheme.bodyMedium),
            Text(
              'Collected by ${release.receivedByLabel}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              'Released by ${release.releasedByName}',
              style: theme.textTheme.bodySmall,
            ),
            if (release.remarks != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(release.remarks!, style: theme.textTheme.bodySmall),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReprint,
                icon: const Icon(Icons.print_outlined, size: 18),
                // Reprinting logs nothing. It reproduces a copy that was
                // already accounted for -- a jammed printer, a page that
                // came out blank. A second handover is a second release,
                // and gets its own entry through the form above.
                label: const Text('Print again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
