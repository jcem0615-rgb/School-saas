import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/location/location_probe.dart';
import '../../domain/entities/emergency_alert.dart';
import '../../domain/entities/emergency_contact.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../datasources/emergency_remote_datasource.dart';

class EmergencyRepositoryImpl implements EmergencyRepository {
  final EmergencyRemoteDataSource _remote;
  const EmergencyRepositoryImpl(this._remote);

  @override
  Stream<List<EmergencyContact>> watchContacts() => _remote.watchContacts();

  @override
  Stream<List<EmergencyAlert>> watchAlerts() => _remote.watchAlerts();

  @override
  Stream<List<EmergencyAlert>> watchAlertsForStudent(String studentId) =>
      _remote.watchAlertsForStudent(studentId);

  @override
  Future<Result<void>> saveContact({
    String? contactId,
    required String label,
    required String phone,
    String? notes,
    required int sortOrder,
  }) =>
      _run(() => _remote.saveContact(
            contactId: contactId,
            label: label,
            phone: phone,
            notes: notes,
            sortOrder: sortOrder,
          ));

  @override
  Future<Result<void>> deleteContact(String contactId) =>
      _run(() => _remote.deleteContact(contactId));

  @override
  Future<Result<void>> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
    LocationResult? location,
  }) =>
      _run(() => _remote.raiseAlert(
            studentId: studentId,
            studentName: studentName,
            section: section,
            message: message,
            location: location,
          ));

  @override
  Future<Result<void>> acknowledgeAlert(String alertId) =>
      _run(() => _remote.acknowledgeAlert(alertId));

  @override
  Future<Result<void>> resolveAlert({required String alertId, String? note}) =>
      _run(() => _remote.resolveAlert(alertId: alertId, note: note));

  Future<Result<void>> _run(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
