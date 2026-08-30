import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../data/phone/phone_verifier_impl.dart';
import '../../domain/phone_verifier.dart';
import 'auth_controller.dart' show firebaseAuthProvider, firebaseFunctionsProvider;

final phoneVerifierProvider = Provider<PhoneVerifier>((ref) {
  return PhoneVerifierImpl(
    auth: ref.watch(firebaseAuthProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

/// Where the recovery has got to.
enum PhoneResetStage {
  /// Typing the number.
  number,

  /// A code has been sent; typing it in.
  code,

  /// The SIM is proven; choosing the new password.
  password,

  /// Done. Sign in with it.
  finished,
}

class PhoneResetState {
  final PhoneResetStage stage;
  final bool busy;
  final String? error;

  /// Held between steps so the code screen can say which number it went
  /// to -- somebody who mistyped a digit finds out here rather than
  /// after waiting for a text that never comes.
  final String phoneNumber;
  final String verificationHandle;

  const PhoneResetState({
    this.stage = PhoneResetStage.number,
    this.busy = false,
    this.error,
    this.phoneNumber = '',
    this.verificationHandle = '',
  });

  PhoneResetState copyWith({
    PhoneResetStage? stage,
    bool? busy,
    String? error,
    String? phoneNumber,
    String? verificationHandle,
    bool clearError = false,
  }) =>
      PhoneResetState(
        stage: stage ?? this.stage,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
        phoneNumber: phoneNumber ?? this.phoneNumber,
        verificationHandle: verificationHandle ?? this.verificationHandle,
      );
}

/// Drives the three steps.
///
/// The state machine is here rather than in the screen because the steps
/// are not independent: a code cannot be confirmed before one is sent,
/// and a password cannot be set before a code is confirmed. A screen
/// holding four booleans gets that wrong eventually.
class PhoneResetController extends StateNotifier<PhoneResetState> {
  final PhoneVerifier _verifier;

  PhoneResetController(this._verifier) : super(const PhoneResetState());

  Future<void> sendCode(String phoneNumber) async {
    final number = phoneNumber.trim();
    if (number.isEmpty) {
      _set(state.copyWith(error: 'Enter the mobile number on your record.'));
      return;
    }
    _set(state.copyWith(busy: true, clearError: true));

    final result = await _verifier.sendCode(_toInternational(number));
    switch (result) {
      case Success(:final value):
        _set(state.copyWith(
          stage: PhoneResetStage.code,
          busy: false,
          phoneNumber: number,
          verificationHandle: value,
          clearError: true,
        ));
      case Error(:final failure):
        _set(state.copyWith(busy: false, error: failure.message));
    }
  }

  Future<void> confirmCode(String smsCode) async {
    _set(state.copyWith(busy: true, clearError: true));
    final result = await _verifier.confirmCode(
      verificationHandle: state.verificationHandle,
      smsCode: smsCode,
    );
    switch (result) {
      case Success():
        _set(state.copyWith(
          stage: PhoneResetStage.password,
          busy: false,
          clearError: true,
        ));
      case Error(:final failure):
        _set(state.copyWith(busy: false, error: failure.message));
    }
  }

  Future<void> setPassword(String newPassword) async {
    _set(state.copyWith(busy: true, clearError: true));
    final result = await _verifier.resetPassword(newPassword);
    switch (result) {
      case Success():
        // The phone session is not the account and must not be left
        // signed in as one.
        await _verifier.cancel();
        _set(state.copyWith(
          stage: PhoneResetStage.finished,
          busy: false,
          clearError: true,
        ));
      case Error(:final failure):
        _set(state.copyWith(busy: false, error: failure.message));
    }
  }

  /// Ends the phone session whenever this controller goes away -- which
  /// is when the screen does, since it is autoDispose.
  ///
  /// Here rather than in the screen's own `dispose`, because `ref` is
  /// already gone by then: reading a provider there throws "cannot use
  /// ref after the widget was disposed", which is a crash on the way
  /// *out* of a password reset and therefore one nobody would report
  /// clearly. The state machine owns the session, so it is the thing
  /// that should end it.
  @override
  void dispose() {
    // Deliberately not awaited: disposal is synchronous, and nobody is
    // waiting on a sign-out that only matters for what it prevents.
    _verifier.cancel();
    super.dispose();
  }

  void _set(PhoneResetState next) {
    if (mounted) state = next;
  }

  /// Turns what somebody types into what Firebase expects.
  ///
  /// A Philippine mobile is written `09171234567` on every form in the
  /// country and `+639171234567` by every phone API. Converting here
  /// rather than asking for the `+63` form is the difference between a
  /// recovery flow people can use and one they get wrong on the first
  /// field.
  @visibleForTesting
  static String toInternationalForTest(String raw) => _toInternational(raw);

  static String _toInternational(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('0')) return '+63${digits.substring(1)}';
    if (digits.startsWith('63')) return '+$digits';
    if (RegExp(r'^9\d{9}$').hasMatch(digits)) return '+63$digits';
    // Anything else is passed through as typed: a number from another
    // country is not this function's to mangle.
    return digits;
  }
}

final phoneResetControllerProvider = StateNotifierProvider.autoDispose<
    PhoneResetController, PhoneResetState>((ref) {
  return PhoneResetController(ref.watch(phoneVerifierProvider));
});
