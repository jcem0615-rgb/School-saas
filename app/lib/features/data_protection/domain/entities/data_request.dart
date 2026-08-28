/// What a person is asking the school to do with their information.
///
/// The four the law recognises, kept as separate kinds rather than a
/// free-text subject line, because they are answered differently and the
/// office needs to see at a glance which queue a request is in. An
/// access request is fulfilled by producing a document; an erasure
/// request often has to be refused, and refused in writing.
enum DataRequestKind {
  access(
    'access',
    'Copy of my records',
    'A copy of everything the school holds in this system.',
  ),
  correction(
    'correction',
    'Correct something',
    'Something on the record is wrong and should be fixed.',
  ),
  erasure(
    'erasure',
    'Delete something',
    'A request to remove information. The school cannot always agree.',
  ),
  objection(
    'objection',
    'Object to a use',
    'An objection to the way some information is being used.',
  );

  final String value;
  final String displayLabel;
  final String blurb;
  const DataRequestKind(this.value, this.displayLabel, this.blurb);

  static DataRequestKind fromString(String value) => DataRequestKind.values
      .firstWhere((k) => k.value == value, orElse: () => DataRequestKind.access);
}

enum DataRequestStatus {
  open('open', 'Open'),
  actioned('actioned', 'Done'),

  /// Refused, with a reason. A school genuinely cannot delete everything
  /// on request -- a transcript and a receipt both have to survive -- and
  /// a system with no way to record a refusal quietly pushes the office
  /// into either lying or ignoring the request.
  refused('refused', 'Refused');

  final String value;
  final String displayLabel;
  const DataRequestStatus(this.value, this.displayLabel);

  static DataRequestStatus fromString(String value) => DataRequestStatus.values
      .firstWhere((s) => s.value == value, orElse: () => DataRequestStatus.open);
}

/// One request, and what the school did about it.
///
/// The record is the deliverable as much as the answer is. A school
/// asked "how do you handle data subject requests" can point at this
/// list; a school with no list has to say "we would deal with it", which
/// is not an answer anybody accepts.
class DataRequest {
  final String id;

  /// The student the request is about, when it is about a student.
  /// Null for a staff member asking about their own record.
  final String? studentId;
  final String? studentName;

  /// Who asked. Recorded by name as well as uid because the person
  /// answering it six weeks later is reading, not querying.
  final String requestedByUid;
  final String requestedByName;
  final DataRequestKind kind;

  /// What they actually asked for, in their words.
  final String details;

  final DateTime requestedAt;
  final DataRequestStatus status;
  final String? handledByName;
  final DateTime? handledAt;

  /// What was done, or why it was refused. Required to close a request:
  /// a request marked done with nothing said about it is the entry that
  /// makes an audit worse rather than better.
  final String? outcome;

  const DataRequest({
    required this.id,
    required this.requestedByUid,
    required this.requestedByName,
    required this.kind,
    required this.details,
    required this.requestedAt,
    this.studentId,
    this.studentName,
    this.status = DataRequestStatus.open,
    this.handledByName,
    this.handledAt,
    this.outcome,
  });

  bool get isOpen => status == DataRequestStatus.open;

  int daysOpen({DateTime? asOf}) =>
      (asOf ?? DateTime.now()).difference(requestedAt).inDays;

  /// The school's own target for answering, in days.
  ///
  /// Fifteen is the figure most Philippine schools work to, and it is
  /// set here as a default the school can argue with rather than as a
  /// statement of what the law requires -- that is a question for their
  /// counsel, not for this software.
  static const int targetDays = 15;

  bool isOverdue({DateTime? asOf}) => isOpen && daysOpen(asOf: asOf) > targetDays;

  String get subjectLabel => studentName ?? requestedByName;
}
