import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../../faculty_portal/domain/entities/grading_scheme.dart';
import '../../../faculty_portal/domain/entities/quarterly_grade.dart';
import '../../../faculty_portal/presentation/controllers/faculty_controller.dart'
    show gradingSchemeProvider;
import '../../../documents/presentation/controllers/documents_controller.dart';
import '../../../faculty_portal/presentation/documents/report_card_pdf.dart';
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
    final releaseId = await ref.read(registrarActionControllerProvider.notifier).recordDocumentRelease(
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
    if (releaseId == null) {
      setState(() => _working = false);
      return; // The controller listener has already shown why.
    }

    final document = _document;
    final printed = await _print(
      purpose: purpose,
      releasedTo: releasedTo,
      copies: _copies,
    );
    if (!mounted) return;

    // The copy goes in the folder last, and its failure does not fail the
    // release. The release is the thing a school is answerable for and it
    // is already written; an upload that did not land leaves the log
    // intact and says so, rather than rolling back a record of something
    // that physically happened.
    var filed = true;
    if (printed != null) {
      filed = await ref.read(documentsActionControllerProvider.notifier).fileIssuedCopy(
            studentId: widget.student.id,
            studentName: widget.student.fullName,
            releaseId: releaseId,
            title: _copyTitle(document),
            fileName: AcademicRecordPdf.fileName(
              document: document,
              student: widget.student,
            ),
            bytes: printed,
          );
      if (!mounted) return;
    }

    setState(() => _working = false);
    _purposeController.clear();
    _remarksController.clear();
    _say(filed
        ? 'Released, logged, and a copy filed.'
        : 'Released and logged. The copy could not be filed -- try again '
            'from the student\'s Documents.');
  }

  /// What the archived copy is called on the shelf.
  ///
  /// The control number rather than the date, because that is the string
  /// the office quotes back on the phone -- it is on the printed page the
  /// family is holding.
  String _copyTitle(SchoolDocument document) {
    final control = AcademicRecordPdf.controlNumber(
      document: document,
      student: widget.student,
      on: DateTime.now(),
    );
    return '${document.displayLabel} - $control';
  }

  /// Renders the document, prints it, and returns the bytes that were
  /// printed.
  ///
  /// The bytes are built once and used for both, so the copy filed in the
  /// student's folder is the page that came out of the printer and not a
  /// second render that could differ -- a different issue date on a job
  /// run either side of midnight would be enough.
  ///
  /// Null when nothing was printed: the grading scheme had not loaded, or
  /// the school has not confirmed it. Both are the school being told to
  /// do a step it has not done, and neither should file a copy.
  Future<Uint8List?> _print({
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
    final chosen = document ?? _document;

    if (chosen == SchoolDocument.form138) {
      final scheme = ref.read(gradingSchemeProvider).valueOrNull;
      if (scheme == null) {
        _say('The grading scheme has not loaded yet. Try again in a moment.');
        return null;
      }
      try {
        final bytes = await ReportCardPdf.build(
          studentName: widget.student.fullName,
          studentNumber: widget.student.studentNumber,
          classLabel: widget.student.classLabel,
          schoolYear: branding.schoolYear ?? '',
          terms: _termsIn(grades),
          bySubject: _quarterlyBySubject(grades, scheme),
          scheme: scheme,
          branding: branding,
          preparedByName: registrarName,
        );
        await Printing.layoutPdf(
          name: ReportCardPdf.fileName(widget.student.fullName),
          onLayout: (_) async => bytes,
        );
        return bytes;
      } on StateError catch (e) {
        // The unconfirmed-scheme refusal. Said in the words the domain
        // used rather than as a failure, because it is not one: it is
        // the school being told to do the step it has not done.
        if (mounted) _say(e.message);
        return null;
      }
    }

    final bytes = await AcademicRecordPdf.build(
      document: chosen,
      student: widget.student,
      branding: branding,
      grades: grades,
      registrarName: registrarName,
      purpose: purpose,
      releasedToName: releasedTo,
      copies: copies,
      issuedOn: DateTime.now(),
    );
    await Printing.layoutPdf(
      name: AcademicRecordPdf.fileName(document: chosen, student: widget.student),
      onLayout: (_) async => bytes,
    );
    return bytes;
  }

  /// The quarters the student has marks in, in the order a report card
  /// reads them. Sorted by name, which puts "1st Quarter" before "2nd"
  /// and "Q1" before "Q2" -- and leaves a school with its own labels
  /// with a stable order rather than the order Firestore happened to
  /// return.
  static List<String> _termsIn(List<Grade> grades) =>
      ({for (final g in grades) g.term}.toList()..sort());

  static Map<String, List<QuarterlyGrade>> _quarterlyBySubject(
    List<Grade> grades,
    GradingScheme scheme,
  ) {
    final subjects = {for (final g in grades) g.subject}.toList()..sort();
    final terms = _termsIn(grades);
    return {
      for (final subject in subjects)
        subject: [
          for (final term in terms)
            computeQuarterlyGrade(
              subject: subject,
              term: term,
              grades: grades.where((g) => g.subject == subject && g.term == term),
              scheme: scheme,
            ),
        ],
    };
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
    // Watched for the same reason as branding: the report card cannot be
    // computed without it, and subscribing for the first time inside
    // _print would return nothing.
    ref.watch(gradingSchemeProvider);

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
                          // A reprint files no new copy: it is the same
                          // release, and the copy is already in the folder.
                          // Filing a second would make the folder say the
                          // school issued it twice.
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
