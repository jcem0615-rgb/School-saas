import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/emergency_remote_datasource.dart';
import '../../data/repositories_impl/emergency_repository_impl.dart';
import '../../domain/entities/emergency_alert.dart';
import '../../domain/entities/emergency_contact.dart';
import '../../domain/repositories/emergency_repository.dart';

final emergencyRepositoryProvider = Provider<EmergencyRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('EmergencyRepository requires a signed-in, school-scoped user.');
  }
  return EmergencyRepositoryImpl(EmergencyRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    actingUser: user,
  ));
});

/// Every role reads this one. It is the point of the feature.
final emergencyContactsProvider = StreamProvider.autoDispose<List<EmergencyContact>>((ref) {
  return ref.watch(emergencyRepositoryProvider).watchContacts();
});

final emergencyAlertsProvider = StreamProvider.autoDispose<List<EmergencyAlert>>((ref) {
  return ref.watch(emergencyRepositoryProvider).watchAlerts();
});

final myEmergencyAlertsProvider =
    StreamProvider.autoDispose.family<List<EmergencyAlert>, String>((ref, studentId) {
  return ref.watch(emergencyRepositoryProvider).watchAlertsForStudent(studentId);
});

class EmergencyActionController extends StateNotifier<AsyncValue<void>> {
  final EmergencyRepository _repository;

  EmergencyActionController(this._repository) : super(const AsyncData(null));

  Future<bool> saveContact({
    String? contactId,
    required String label,
    required String phone,
    String? notes,
    required int sortOrder,
  }) {
    if (label.trim().isEmpty || phone.trim().isEmpty) {
      // A contact with no name or no number is a row that looks like help
      // and is not. Better to refuse it than to publish it.
      if (mounted) {
        state = AsyncError('A name and a number are both required.', StackTrace.current);
      }
      return Future.value(false);
    }
    return _run(() => _repository.saveContact(
          contactId: contactId,
          label: label.trim(),
          phone: phone.trim(),
          notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
          sortOrder: sortOrder,
        ));
  }

  Future<bool> deleteContact(String contactId) => _run(() => _repository.deleteContact(contactId));

  Future<bool> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
  }) =>
      _run(() => _repository.raiseAlert(
            studentId: studentId,
            studentName: studentName,
            section: section,
            message: message?.trim().isEmpty ?? true ? null : message!.trim(),
          ));

  Future<bool> acknowledgeAlert(String alertId) =>
      _run(() => _repository.acknowledgeAlert(alertId));

  Future<bool> resolveAlert({required String alertId, String? note}) =>
      _run(() => _repository.resolveAlert(alertId: alertId, note: note));

  Future<bool> _run(Future<Result<void>> Function() action) async {
    if (mounted) state = const AsyncLoading();
    final result = await action();
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }
}

final emergencyActionControllerProvider =
    StateNotifierProvider.autoDispose<EmergencyActionController, AsyncValue<void>>((ref) {
  return EmergencyActionController(ref.watch(emergencyRepositoryProvider));
});
