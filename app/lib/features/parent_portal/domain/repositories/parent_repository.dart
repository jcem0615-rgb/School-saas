import '../../../registrar_portal/domain/entities/student_summary.dart';

/// Deliberately tiny: resolving "my children" is the only genuinely new
/// query Parent Portal needs. Every child-facing screen (attendance,
/// grades, payments, announcements) already exists and already accepts
/// a studentId -- Parent Portal is almost entirely reuse of Registrar,
/// Faculty, Payments, and QR Attendance screens, gated by rules that were
/// already written when those modules were built (each one's read rule
/// already checks `claims().role == 'parent' && studentId in
/// linkedStudentIds`).
abstract class ParentRepository {
  /// [linkedStudentIds] comes from the signed-in user's own AppUser
  /// entity (already present on the ID token / Firestore profile since
  /// Module 4) -- this method just resolves those IDs to full student
  /// records, rather than re-deriving the link itself.
  Stream<List<StudentSummary>> watchChildren(List<String> linkedStudentIds);
}
