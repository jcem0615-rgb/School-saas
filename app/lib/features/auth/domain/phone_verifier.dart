import '../../../core/errors/result.dart';

/// Recovering an account with the phone in your hand.
///
/// A port rather than direct Firebase calls, for the same reason
/// PushRegistrar is one: demo mode never initialises Firebase, and
/// sending a stranger a real SMS so they can look at a demo would be
/// rude, slow and billable.
///
/// The flow is three steps and they have to happen in order:
///
///   1. [sendCode] -- Firebase texts a code to that handset.
///   2. [confirmCode] -- the code proves the SIM, and Firebase signs the
///      caller in *as the phone*, which is not the same thing as their
///      school account.
///   3. [resetPassword] -- the server looks up which account the school
///      registered that number against, and sets its password.
///
/// Step 3 is where the account is actually touched, and it is a callable
/// precisely because step 2 does not authenticate anybody to it: the
/// phone session is proof of a SIM and nothing more.
abstract class PhoneVerifier {
  /// Texts a code. Returns an opaque handle to pass back to
  /// [confirmCode] -- on some platforms it is a verification id, on
  /// others a confirmation object held internally.
  Future<Result<String>> sendCode(String phoneNumber);

  Future<Result<void>> confirmCode({
    required String verificationHandle,
    required String smsCode,
  });

  /// Sets the new password on whichever account that verified number
  /// belongs to. Fails with the server's own message when the number is
  /// on no account, or on more than one.
  Future<Result<void>> resetPassword(String newPassword);

  /// Ends the temporary phone session, whether or not the reset
  /// happened. Nobody should be left signed in as a bare phone number.
  Future<void> cancel();
}
