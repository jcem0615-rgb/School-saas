import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider, firestoreProvider;
import '../../data/datasources/audit_trail_remote_datasource.dart';
import '../../data/repositories_impl/audit_trail_repository_impl.dart';
import '../../domain/entities/audit_log_entry.dart';
import '../../domain/repositories/audit_trail_repository.dart';
import '../../domain/usecases/watch_audit_log_usecase.dart';

final auditTrailRemoteDataSourceProvider = Provider<AuditTrailRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('AuditTrailRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return AuditTrailRemoteDataSource(firestore: ref.watch(firestoreProvider), schoolId: user.schoolId!);
});

final auditTrailRepositoryProvider = Provider<AuditTrailRepository>((ref) {
  return AuditTrailRepositoryImpl(ref.watch(auditTrailRemoteDataSourceProvider));
});

class AuditTrailFilter {
  final String? module;
  final DateTime? startDate;
  final DateTime? endDate;
  const AuditTrailFilter({this.module, this.startDate, this.endDate});

  @override
  bool operator ==(Object other) =>
      other is AuditTrailFilter &&
      other.module == module &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(module, startDate, endDate);
}

final auditLogStreamProvider =
    StreamProvider.autoDispose.family<List<AuditLogEntry>, AuditTrailFilter>((ref, filter) {
  return WatchAuditLogUseCase(ref.watch(auditTrailRepositoryProvider))(
    moduleFilter: filter.module,
    startDate: filter.startDate,
    endDate: filter.endDate,
  );
});

/// The signed-in user's own activity history -- available to every role
/// (General Requirement: "Activity History, Audit Trail" per user),
/// unlike the full-school AuditTrailScreen which is Owner/Director/Admin only.
final myActivityStreamProvider = StreamProvider.autoDispose<List<AuditLogEntry>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return const Stream.empty();
  return WatchAuditLogUseCase(ref.watch(auditTrailRepositoryProvider))(userIdFilter: uid);
});
