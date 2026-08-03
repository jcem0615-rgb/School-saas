/// Registers this device to receive announcement notifications.
///
/// A port rather than a direct FirebaseMessaging call, for the same
/// reason as UploadRepository: demo mode never initialises Firebase, and
/// asking a browser for notification permission is not something a demo
/// should do to anyone.
///
/// The registration model is deliberately simple. One document per
/// device, keyed by the FCM token, under
/// `schools/{schoolId}/users/{uid}/deviceTokens/{token}`:
///
///   * keyed by the token, so re-registering the same browser overwrites
///     instead of accumulating a row per app launch;
///   * a subcollection, not a field on the user document, because
///     `users/{uid}` is readable by everyone in the school and a token is
///     enough to push to that device;
///   * deleted on sign-out, so the next person to use a shared school
///     computer does not receive the last person's notifications.
abstract class PushRegistrar {
  /// Asks for permission if it has not been granted, then stores the
  /// token for this device.
  ///
  /// Returns false when the user declined, when the browser cannot do
  /// push at all, or when anything else went wrong -- callers treat all
  /// three the same way, because none of them should interrupt someone
  /// who only wanted to check their grades.
  Future<bool> register();

  /// Forgets this device. Called on sign-out.
  Future<void> unregister();

  /// Whether this device is currently registered, so the UI can show the
  /// real state rather than a switch that lies.
  Future<bool> isRegistered();
}

/// Used in demo mode and in tests: does nothing, says so honestly.
class NoOpPushRegistrar implements PushRegistrar {
  const NoOpPushRegistrar();

  @override
  Future<bool> register() async => false;

  @override
  Future<void> unregister() async {}

  @override
  Future<bool> isRegistered() async => false;
}
