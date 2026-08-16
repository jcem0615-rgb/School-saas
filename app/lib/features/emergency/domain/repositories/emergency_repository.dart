import '../../../../core/errors/result.dart';
import '../entities/emergency_alert.dart';
import '../entities/emergency_contact.dart';

abstract class EmergencyRepository {
  /// The school's published numbers. Readable by every role.
  Stream<List<EmergencyContact>> watchContacts();

  Future<Result<void>> saveContact({
    String? contactId,
    required String label,
    required String phone,
    String? notes,
    required int sortOrder,
  });

  Future<Result<void>> deleteContact(String contactId);

  /// Alerts a staff member should be looking at.
  Stream<List<EmergencyAlert>> watchAlerts();

  /// Alerts raised by one student, for their own history and for the
  /// parents linked to them.
  Stream<List<EmergencyAlert>> watchAlertsForStudent(String studentId);

  /// Raises one. Only a student does this, and only for themselves.
  Future<Result<void>> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
  });

  Future<Result<void>> acknowledgeAlert(String alertId);

  Future<Result<void>> resolveAlert({required String alertId, String? note});
}
