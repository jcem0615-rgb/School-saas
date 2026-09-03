import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/result.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../entities/document_release.dart';
import '../entities/promotion.dart';
import '../entities/student_summary.dart';

class RegisterStudentOutcome {
  final String studentId;
  final String studentNumber;
  const RegisterStudentOutcome({required this.studentId, required this.studentNumber});
}

class ProvisionStudentAccountOutcome {
  final String uid;
  final String tempPassword;
  const ProvisionStudentAccountOutcome({required this.uid, required this.tempPassword});
}

abstract class RegistrarRepository {
  /// [limit] null means the whole roster; a number means one page of it,
  /// surname order. [educationLevel] narrows the query itself rather than
  /// the page it returns -- see the datasource for why that distinction
  /// matters.
  Stream<List<StudentSummary>> watchStudents({int? limit, EducationLevel? educationLevel});

  /// The whole roster, once, for callers that must not miss anyone --
  /// export today. Deliberately separate from [watchStudents] so that
  /// reading everything is always a decision someone made.
  Future<List<StudentSummary>> fetchAllStudents();

  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    String? email,
    String? phone,
    required List<GuardianContact> guardianContacts,
  });

  Future<Result<void>> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
    DateTime? birthDate,
    String? email,
    String? phone,
  });

  /// Sets the student's ID photo to an already-uploaded [photoUrl].
  ///
  /// Uploading and recording are two steps on purpose: the upload can
  /// succeed and the write fail, and a caller that conflated them would
  /// report a photo saved that no record points at.
  Future<Result<void>> setStudentPhoto({
    required String studentId,
    required String photoUrl,
  });

  /// Creates a Student Portal login for an existing academic record and
  /// links them (see provisionUser.ts's linkedStudentId handling).
  Future<Result<ProvisionStudentAccountOutcome>> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
  });

  /// Every mark this student has, for building a transcript. Unbounded
  /// on purpose -- see the datasource.
  Stream<List<Grade>> watchStudentGrades(String studentId);

  /// What has already been handed out for this student, newest first.
  Stream<List<DocumentRelease>> watchDocumentReleases(String studentId);

  /// Logs that a document left the office. Write-only by design: the
  /// rules refuse every update and delete, so this is the one and only
  /// thing that can happen to a release record.
  Future<Result<void>> recordDocumentRelease({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  });

  /// Sets the student's assessed balance. Server-side only -- see the
  /// datasource for why this cannot be an ordinary field update.
  Future<Result<void>> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  });

  // ---- Year-end rollover ----

  /// Every mark posted for one section, for building a rollover plan.
  Future<List<Grade>> fetchGradesForSection(String section);

  /// Who has already been moved for this school year.
  Future<Set<String>> fetchRolledOverStudentIds(String schoolYear);

  /// Applies one page of decisions. Returns how many were moved and how
  /// many were skipped as already done.
  ///
  /// Safe to call again with the same students: the server writes each
  /// promotion at an id built from the year and the student, so somebody
  /// already moved is skipped rather than moved twice.
  Future<Result<RolloverOutcome>> runYearEndRollover({
    required String schoolYear,
    required List<PromotionDecision> decisions,
  });
}

/// What one page of a rollover did.
class RolloverOutcome {
  final int applied;

  /// Students the server found already moved for this year. Not an
  /// error: it is what a second run of an interrupted rollover looks
  /// like, and the screen says so rather than reporting a failure.
  final int skipped;

  final String schoolYear;

  const RolloverOutcome({
    required this.applied,
    required this.skipped,
    required this.schoolYear,
  });
}
