/// The academic documents a registrar's office hands out.
///
/// Only the ones a school is asked to account for: a receiving school
/// will write back asking when Form 137 was sent and to whom, a TOR is
/// what a student needs in hand to enrol anywhere else, and a report card
/// is signed by a parent and brought back. A certificate of enrolment or
/// a good-moral is printed and forgotten; these are not.
enum SchoolDocument {
  transcriptOfRecords('tor', 'Transcript of Records', 'TOR'),
  form137('form_137', 'Form 137', 'F137'),

  /// The report card. Logged alongside the other two because a family
  /// that says they never received one, or received a different one, is
  /// a dispute the office has to be able to answer -- and because a
  /// reissued card is the copy that ends up somewhere it should not.
  form138('form_138', 'Report Card', 'F138');

  /// What is stored. Kept apart from the label so the record survives
  /// the school deciding to print a different title on the page.
  final String value;
  final String displayLabel;

  /// For the file name and the narrow places a full title will not fit.
  final String shortLabel;

  const SchoolDocument(this.value, this.displayLabel, this.shortLabel);

  static SchoolDocument fromString(String value) => SchoolDocument.values
      .firstWhere((d) => d.value == value, orElse: () => SchoolDocument.transcriptOfRecords);
}

/// One occasion on which a document left the registrar's office.
///
/// This is a log of a physical act, not of a print job. Somebody stood at
/// the counter, was handed a document, and the office is now answerable
/// for that -- which is why [releasedToName] is recorded separately from
/// the student (a parent, a sibling, a school's liaison) and why nothing
/// here can be edited or deleted afterwards. A release log that could be
/// tidied up is not evidence of anything.
class DocumentRelease {
  final String id;
  final String studentId;

  /// The student's name as it stood when the document was released.
  ///
  /// Denormalised deliberately. A record that read the name back from
  /// the student would silently rewrite the history of every release
  /// after a correction, and the point of the log is what happened at
  /// the time.
  final String studentName;

  final SchoolDocument document;

  /// How many copies were handed over. Schools charge per copy and are
  /// asked "how many have we given this family already".
  final int copies;

  /// Why it was asked for -- "transfer to Santa Rosa NHS", "college
  /// application". The single most useful line when a document turns up
  /// somewhere it should not have.
  final String purpose;

  /// Who physically received it.
  final String releasedToName;

  /// Their relationship to the student, when it is not the student.
  final String? releasedToRelation;

  final String releasedByName;
  final DateTime releasedAt;
  final String? remarks;

  const DocumentRelease({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.document,
    required this.copies,
    required this.purpose,
    required this.releasedToName,
    required this.releasedByName,
    required this.releasedAt,
    this.releasedToRelation,
    this.remarks,
  });

  /// "Maria Santos (Mother)", or just the name when they are the student.
  String get receivedByLabel {
    final relation = releasedToRelation?.trim();
    if (relation == null || relation.isEmpty) return releasedToName;
    return '$releasedToName ($relation)';
  }
}
