import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/location/location_probe.dart';
import '../../../../core/location/location_providers.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../../data/datasources/emergency_remote_datasource.dart';
import '../../data/repositories_impl/emergency_repository_impl.dart';
import '../../../parent_portal/presentation/controllers/parent_controller.dart'
    show myChildrenProvider;
import '../../../registrar_portal/domain/entities/student_summary.dart';
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

/// Every alert raised by the children linked to the signed-in parent,
/// newest first.
///
/// Fanned out per child rather than queried in one go, because that is
/// the shape firestore.rules allows: a parent may read an alert whose
/// studentId is in their own linkedStudentIds, and a collection query
/// cannot express that -- rules reject queries, they do not filter them.
/// Two children is two small streams, which is the right trade against a
/// denormalised copy that could go stale in the one moment it matters.
final childrenEmergencyAlertsProvider = Provider.autoDispose<List<EmergencyAlert>>((ref) {
  final children = ref.watch(myChildrenProvider).valueOrNull ?? const <StudentSummary>[];
  final all = <EmergencyAlert>[];
  for (final child in children) {
    all.addAll(ref.watch(myEmergencyAlertsProvider(child.id)).valueOrNull ?? const []);
  }
  all.sort((a, b) => b.raisedAt.compareTo(a.raisedAt));
  return all;
});

/// The unresolved ones. Drives the dashboard banner, which is the whole
/// point: a parent must not have to go looking for this.
final childrenActiveAlertsProvider = Provider.autoDispose<List<EmergencyAlert>>((ref) {
  return ref.watch(childrenEmergencyAlertsProvider).where((a) => a.isActive).toList();
});

final myEmergencyAlertsProvider =
    StreamProvider.autoDispose.family<List<EmergencyAlert>, String>((ref, studentId) {
  return ref.watch(emergencyRepositoryProvider).watchAlertsForStudent(studentId);
});

class EmergencyActionController extends StateNotifier<AsyncValue<void>> {
  final EmergencyRepository _repository;
  final LocationProbe _locationProbe;

  /// How long the alert is willing to wait for a position.
  ///
  /// Short on purpose. A student who has pressed the button is waiting,
  /// and an alert that reaches an adviser eight seconds late with a
  /// location is still better than one that reaches them thirty seconds
  /// late with a slightly better one. Whatever has not arrived by then is
  /// recorded as a timeout and the alert goes without it.
  static const locationTimeout = Duration(seconds: 8);

  EmergencyActionController(this._repository, this._locationProbe)
      : super(const AsyncData(null));

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

  /// Raises an alert, attaching wherever the device says the student is.
  ///
  /// The probe is asked here rather than in the screen so that the rule
  /// that matters lives in one place: asking for a location must never
  /// stop the alert. The probe is bounded and does not throw, so the
  /// worst case is an alert carrying a reason instead of a position.
  Future<bool> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
  }) async {
    // The deadline is enforced here as well as passed down. LocationProbe
    // promises to be bounded and not to throw, but this is the one call in
    // the app where a probe that quietly breaks that promise -- a plugin
    // that hangs on a device with no signal, an exception from an
    // embedded webview -- would leave a student who pressed the button
    // waiting on a spinner instead of getting help. Whichever gives up
    // first, the alert still goes.
    final location = await _locationProbe
        .current(timeout: locationTimeout)
        .timeout(
          locationTimeout,
          onTimeout: () => const LocationResult.failed(LocationFailure.timeout),
        )
        .catchError(
          (_) => const LocationResult.failed(LocationFailure.unavailable),
        );

    return _run(() => _repository.raiseAlert(
          studentId: studentId,
          studentName: studentName,
          section: section,
          message: message?.trim().isEmpty ?? true ? null : message!.trim(),
          location: location,
        ));
  }

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
  return EmergencyActionController(
    ref.watch(emergencyRepositoryProvider),
    ref.watch(locationProbeProvider),
  );
});
