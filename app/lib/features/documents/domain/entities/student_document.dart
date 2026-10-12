/// A student's folder: the papers a school holds about one child.
///
/// Every registrar's office has a physical one. It holds what the family
/// handed in at enrolment, what the previous school sent over, and a copy
/// of whatever this school has issued since. The questions asked of it are
/// always the same two -- "do we have their Form 137 yet?" and "what
/// exactly did we give them in March?" -- and a folder that cannot answer
/// the second one is the reason `documentReleases` exists.
///
/// This is the other half of that log. The log says a document left; this
/// says what the document was.
library;

/// What a paper in the folder is.
///
/// Deliberately a short list of the things a Philippine school is actually
/// asked to produce, plus [other]. A long enum nobody can choose from
/// correctly becomes one bucket in practice, and then the folder is a pile
/// again.
///
/// Medical records are not here on purpose. A child's health information
/// is a different sensitivity class from their Form 137 -- it belongs with
/// Guidance, behind Guidance's own rules, not in a folder the whole
/// registrar's office reads.
enum DocumentKind {
  birthCertificate('birth_certificate', 'PSA Birth Certificate'),
  form137Received('form_137_received', 'Form 137 (from previous school)'),
  reportCardReceived('form_138_received', 'Report Card (from previous school)'),
  goodMoral('good_moral', 'Certificate of Good Moral Character'),
  enrolmentForm('enrolment_form', 'Enrolment Form'),
  transferCredential('transfer_credential', 'Transfer Credential'),

  /// A copy of something this school issued and handed over.
  ///
  /// Filed automatically when a document is released, which is the only
  /// way the release log becomes reproducible: without it the school can
  /// say a TOR left the office in March and cannot show what was on it.
  issuedCopy('issued_copy', 'Copy of an issued document'),

  other('other', 'Other');

  /// What is stored. Kept apart from the label so the record survives the
  /// school deciding to call a thing something else.
  final String value;
  final String displayLabel;

  const DocumentKind(this.value, this.displayLabel);

  /// Unknown values read as [other] rather than throwing. A folder that
  /// refuses to open because one row has a kind this build has not heard
  /// of is worse than a row labelled "Other".
  static DocumentKind fromString(String value) => DocumentKind.values
      .firstWhere((k) => k.value == value, orElse: () => DocumentKind.other);

  /// The kinds a person may file by hand.
  ///
  /// [issuedCopy] is not among them: it is written by the release flow and
  /// carries a `releaseId`, and one filed by hand would be a copy of a
  /// release that never happened.
  static List<DocumentKind> get fileable =>
      DocumentKind.values.where((k) => k != DocumentKind.issuedCopy).toList();
}

/// Which direction the paper travelled.
enum DocumentOrigin {
  /// Somebody handed it to the school: the family, a previous school, a
  /// division office.
  received('received'),

  /// The school produced it and gave it out. Always paired with the
  /// release that handed it over.
  issued('issued');

  final String value;
  const DocumentOrigin(this.value);

  static DocumentOrigin fromString(String value) => DocumentOrigin.values
      .firstWhere((o) => o.value == value, orElse: () => DocumentOrigin.received);
}

/// What Storage will accept, mirroring `storage.rules`.
///
/// Checked here as well so an unsupported file is refused with a sentence
/// before the bytes go over the wire, rather than coming back as a
/// permission error that reads like the user's fault.
bool isFilableContentType(String contentType) {
  final type = contentType.trim().toLowerCase();
  return type == 'application/pdf' || type.startsWith('image/');
}

/// One paper in one student's folder.
class StudentDocument {
  final String id;
  final String studentId;

  /// The student's name as it stood when the paper was filed.
  ///
  /// Denormalised for the same reason `DocumentRelease.studentName` is: a
  /// folder that read the name back from the student record would silently
  /// rewrite its own history after a correction, and what the office needs
  /// is what the paper said at the time.
  final String studentName;

  final DocumentKind kind;
  final DocumentOrigin origin;

  /// What it is called on the shelf. Usually the kind's label; free text
  /// because "Form 137 - Santa Rosa NHS" is more use than "Form 137".
  final String title;

  final String fileName;

  /// Where the bytes are. A Storage download URL in the product, a `data:`
  /// URI in the demo -- `openAttachment` handles both.
  final String url;

  final String contentType;
  final int sizeBytes;

  final String filedByName;
  final DateTime filedAt;
  final String? note;

  /// The release this is a copy of, when [origin] is [DocumentOrigin.issued].
  ///
  /// The join that makes the append-only release log mean something: the
  /// log row says a Form 137 was handed to the mother on the 3rd, and this
  /// is the Form 137 that was handed over.
  final String? releaseId;

  /// Set when the paper is withdrawn from the folder.
  ///
  /// Archiving rather than deleting, and with a reason, because a student
  /// folder that can be quietly emptied answers nothing -- the same
  /// argument that makes `documentReleases` append-only. A superseded
  /// birth certificate is still evidence of what the school was working
  /// from last year.
  final DateTime? archivedAt;
  final String? archivedByName;
  final String? archiveReason;

  const StudentDocument({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.kind,
    required this.origin,
    required this.title,
    required this.fileName,
    required this.url,
    required this.contentType,
    required this.sizeBytes,
    required this.filedByName,
    required this.filedAt,
    this.note,
    this.releaseId,
    this.archivedAt,
    this.archivedByName,
    this.archiveReason,
  });

  bool get isArchived => archivedAt != null;

  /// Whether this is a copy of something the school issued.
  bool get isIssuedCopy => origin == DocumentOrigin.issued;

  /// "412 KB", "1.2 MB". Rounded, because the point is "is this the scan
  /// or the thumbnail", not the byte count.
  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  StudentDocument archived({
    required DateTime at,
    required String byName,
    required String reason,
  }) =>
      StudentDocument(
        id: id,
        studentId: studentId,
        studentName: studentName,
        kind: kind,
        origin: origin,
        title: title,
        fileName: fileName,
        url: url,
        contentType: contentType,
        sizeBytes: sizeBytes,
        filedByName: filedByName,
        filedAt: filedAt,
        note: note,
        releaseId: releaseId,
        archivedAt: at,
        archivedByName: byName,
        archiveReason: reason,
      );
}

/// What the folder looks like at a glance, for the header above the list.
///
/// Counted over the papers that are still in it: an archived Form 137 is
/// not a Form 137 the school holds, and a summary that said otherwise
/// would answer "do we have it yet" wrongly.
class FolderSummary {
  final int onFile;
  final int archived;
  final Set<DocumentKind> kindsOnFile;

  const FolderSummary({
    required this.onFile,
    required this.archived,
    required this.kindsOnFile,
  });

  factory FolderSummary.of(Iterable<StudentDocument> documents) {
    var onFile = 0;
    var archived = 0;
    final kinds = <DocumentKind>{};
    for (final d in documents) {
      if (d.isArchived) {
        archived++;
      } else {
        onFile++;
        kinds.add(d.kind);
      }
    }
    return FolderSummary(onFile: onFile, archived: archived, kindsOnFile: kinds);
  }

  bool holds(DocumentKind kind) => kindsOnFile.contains(kind);

  bool get isEmpty => onFile == 0;
}
