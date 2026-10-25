import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/cashiering_repository_impl.dart';
import '../../domain/entities/cashier_shift.dart';

final cashieringRepositoryProvider = Provider<CashieringRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('CashieringRepository requires a signed-in, school-scoped user.');
  }
  return CashieringRepositoryImpl(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingCashier(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

/// The drawers this account is allowed to see.
///
/// A cashier sees their own; the Director and the Admin see everybody's,
/// because "who was short last month" is the question the module exists
/// to answer and it is not one a cashier asks about themselves. The
/// rules enforce the same split independently.
final shiftsProvider = StreamProvider.autoDispose<List<CashierShift>>((ref) {
  final repo = ref.watch(cashieringRepositoryProvider);
  final role = ref.watch(authStateProvider).valueOrNull?.role;
  final seesEveryone = role == UserRole.director || role == UserRole.admin;
  return seesEveryone ? repo.watchAllShifts() : repo.watchMyShifts();
});

/// The drawer this cashier has open, if any.
final myOpenShiftProvider = Provider.autoDispose<CashierShift?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  final shifts = ref.watch(shiftsProvider).valueOrNull ?? const <CashierShift>[];
  return shifts
      .where((s) => s.isOpen && s.cashierUid == uid)
      .firstOrNull;
});

/// What the open drawer should hold right now.
final reckoningProvider =
    StreamProvider.autoDispose.family<ShiftReckoning, CashierShift>((ref, shift) {
  return ref.watch(cashieringRepositoryProvider).watchReckoning(shift);
});

final cashieringActionControllerProvider = StateNotifierProvider.autoDispose<
    CashieringActionController, AsyncValue<void>>((ref) {
  return CashieringActionController(ref.watch(cashieringRepositoryProvider));
});

class CashieringActionController extends StateNotifier<AsyncValue<void>> {
  final CashieringRepository _repository;

  CashieringActionController(this._repository) : super(const AsyncData(null));

  Future<bool> openShift({
    required CashierShift? openShift,
    required double openingFloat,
    String? notes,
  }) async {
    // Checked here as well as on the server, so a second drawer is
    // refused with a sentence naming the first rather than a round trip
    // that comes back as an error code.
    final problem = reasonShiftCannotOpen(
      openShift: openShift,
      openingFloat: openingFloat,
    );
    if (problem != null) {
      if (mounted) state = AsyncError(problem, StackTrace.current);
      return false;
    }

    if (mounted) state = const AsyncLoading();
    final result = await _repository.openShift(
      openingFloat: openingFloat,
      notes: notes,
    );
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  /// Counts a drawer and closes it.
  ///
  /// Returns what the server reckoned, so the screen can say what the
  /// difference was rather than only that there was one. Null when the
  /// close was refused.
  Future<ShiftClosing?> closeShift({
    required CashierShift shift,
    required double countedAmount,
    required double expectedAmount,
    String varianceNote = '',
  }) async {
    final problem = reasonShiftCannotClose(
      shift: shift,
      countedAmount: countedAmount,
      expectedAmount: expectedAmount,
      varianceNote: varianceNote,
    );
    if (problem != null) {
      if (mounted) state = AsyncError(problem, StackTrace.current);
      return null;
    }

    if (mounted) state = const AsyncLoading();
    final result = await _repository.closeShift(
      shiftId: shift.id,
      countedAmount: countedAmount,
      varianceNote: varianceNote.trim().isEmpty ? null : varianceNote.trim(),
    );
    return switch (result) {
      Success(:final value) => () {
          if (mounted) state = const AsyncData(null);
          return value;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return null;
        }(),
    };
  }
}
