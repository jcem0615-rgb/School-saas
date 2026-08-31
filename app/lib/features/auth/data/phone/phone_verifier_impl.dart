import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
// `Result` collides with cloud_functions' own; ours is the one this
// file means everywhere it appears.
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter/foundation.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/phone_verifier.dart';

/// Firebase Phone Auth, on both kinds of platform.
///
/// Web and mobile do not share an API here and cannot be made to: on the
/// web the SMS flow is `signInWithPhoneNumber`, which returns a
/// confirmation object the browser holds on to, while on mobile it is
/// `verifyPhoneNumber` with callbacks and a verification id. Both are
/// wrapped rather than one being emulated with the other, because the
/// emulation is where the auto-retrieval on Android would be lost.
class PhoneVerifierImpl implements PhoneVerifier {
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Web only. Kept because the browser's confirmation object is the
  /// only handle to that SMS.
  ConfirmationResult? _webConfirmation;

  PhoneVerifierImpl({
    required FirebaseAuth auth,
    required FirebaseFunctions functions,
  })  : _auth = auth,
        _functions = functions;

  @override
  Future<Result<String>> sendCode(String phoneNumber) async {
    try {
      if (kIsWeb) {
        _webConfirmation = await _auth.signInWithPhoneNumber(phoneNumber);
        return Success(_webConfirmation!.verificationId);
      }

      // verifyPhoneNumber is callback-based; a completer turns it into
      // the same shape the web branch already has.
      final completer = Completer<Result<String>>();
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (_) {
          // Android can auto-retrieve the code. The user still types it
          // in this flow -- the alternative is a screen that jumps
          // forward on its own while somebody is reading it.
        },
        verificationFailed: (error) {
          if (!completer.isCompleted) {
            completer.complete(Error(AuthFailure(
              error.code,
              error.message ?? 'That number could not be verified.',
            )));
          }
        },
        codeSent: (verificationId, _) {
          if (!completer.isCompleted) completer.complete(Success(verificationId));
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!completer.isCompleted) completer.complete(Success(verificationId));
        },
      );
      return await completer.future;
    } on FirebaseAuthException catch (e) {
      return Error(AuthFailure(e.code, e.message ?? 'That number could not be verified.'));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> confirmCode({
    required String verificationHandle,
    required String smsCode,
  }) async {
    try {
      if (kIsWeb) {
        final confirmation = _webConfirmation;
        if (confirmation == null) {
          return const Error(AuthFailure('no-code', 'Ask for a new code first.'));
        }
        await confirmation.confirm(smsCode);
        return const Success(null);
      }

      await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: verificationHandle,
          smsCode: smsCode,
        ),
      );
      return const Success(null);
    } on FirebaseAuthException catch (e) {
      return Error(AuthFailure(
        e.code,
        // The common one by far, and worth saying plainly rather than
        // passing through Firebase's wording.
        e.code == 'invalid-verification-code'
            ? 'That code does not match. Check it and try again.'
            : e.message ?? 'That code could not be checked.',
      ));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> resetPassword(String newPassword) async {
    try {
      await _functions
          .httpsCallable('resetPasswordByPhone')
          .call<Map<String, dynamic>>({'newPassword': newPassword});
      return const Success(null);
    } on FirebaseFunctionsException catch (e) {
      // The server's message is the useful one here: "no active account
      // is registered to that number", "that number is registered to
      // more than one account". A generic failure would send somebody
      // back to try the same thing again.
      return Error(AuthFailure(e.code, e.message ?? 'That password could not be set.'));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<void> cancel() async {
    try {
      // Nobody is left signed in as a bare phone number, whether the
      // reset happened or they walked away halfway through.
      if (_auth.currentUser?.phoneNumber != null) await _auth.signOut();
      _webConfirmation = null;
    } catch (_) {
      // A session that could not be cleaned up is not worth failing a
      // password reset over.
    }
  }
}

/// Demo mode: no SMS, no Firebase, and it says so on screen.
class DemoPhoneVerifier implements PhoneVerifier {
  /// Printed on the screen in demo mode. There is no SMS to receive, and
  /// a demo that asked for a code nobody can get is a dead end.
  static const demoCode = '123456';

  const DemoPhoneVerifier();

  @override
  Future<Result<String>> sendCode(String phoneNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const Success('demo-verification');
  }

  @override
  Future<Result<void>> confirmCode({
    required String verificationHandle,
    required String smsCode,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return smsCode.trim() == demoCode
        ? const Success(null)
        : const Error(AuthFailure(
            'invalid-verification-code',
            'That code does not match. In this demo it is $demoCode.',
          ));
  }

  @override
  Future<Result<void>> resetPassword(String newPassword) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Deliberately does not change anything. Demo accounts share one
    // password that every visitor after this one still needs.
    return const Success(null);
  }

  @override
  Future<void> cancel() async {}
}
