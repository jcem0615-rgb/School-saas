/// One account, one device at a time.
///
/// The rule this implements: signing in somewhere new signs you out
/// everywhere else. It exists because a school login is worth sharing --
/// one paid parent account read by three families, one student account
/// lent to a friend who wants to see the answer key screen, one staff
/// account left signed in on a machine in the faculty room. None of that
/// is caught by a password.
///
/// ## How it works
///
/// A single document, `sessions/current`, under the account's own
/// profile. It holds the id of whichever device claimed the account last.
/// Every signed-in device watches it. A device that reads an id which is
/// not its own knows it has been displaced, and signs itself out.
///
/// The document lives in a subcollection of the user's profile rather
/// than as a field on it, for the same reason `deviceTokens` does:
/// `users/{uid}` is readable by everyone in the school (see
/// firestore.rules), and where a person is signed in is not the school's
/// business. Only the account holder can read or write their own.
///
/// ## What this is and is not
///
/// It is an honesty mechanism, not a security boundary. Enforcement
/// happens in the app: a modified client could decline to claim, or
/// decline to sign out when displaced, and Firestore rules cannot
/// require a write that a client simply never makes. What it does do is
/// make casual sharing stop working -- the second person's sign-in
/// throws the first one out, every time, which is enough to make a
/// shared account useless as a shared account.
///
/// Nothing here touches Firebase Auth's own session. The displaced
/// device signs out through the ordinary sign-out path, so its push
/// token is cleaned up exactly as it would be if the user had tapped
/// Sign out.
library;

/// The claim currently held on an account.
class DeviceClaim {
  final String deviceId;

  /// What to call the holder when telling somebody else they lost the
  /// session -- "a web browser", "an Android device".
  final String deviceLabel;

  final DateTime? claimedAt;

  const DeviceClaim({
    required this.deviceId,
    required this.deviceLabel,
    this.claimedAt,
  });
}

/// What a device should do about the claim it can currently see.
enum SessionVerdict {
  /// This device holds the account. Carry on.
  hold,

  /// Nobody holds it. Claim it.
  unclaimed,

  /// Somebody else holds it. Sign out.
  displaced,
}

/// The whole decision, as a function, so it can be tested without a
/// Firestore or a widget tree.
SessionVerdict verdictFor({
  required String myDeviceId,
  required DeviceClaim? claim,
}) {
  if (claim == null) return SessionVerdict.unclaimed;
  if (claim.deviceId == myDeviceId) return SessionVerdict.hold;
  return SessionVerdict.displaced;
}

/// Reads and writes the claim for the signed-in account.
abstract class SessionGuard {
  /// Records this device as the account's current one, displacing
  /// whoever held it. Last write wins, deliberately: two devices racing
  /// to sign in should end with exactly one of them signed in, and which
  /// one does not matter as long as the other finds out.
  Future<void> claim(DeviceClaim claim);

  /// The claim as it stands, and every change to it. Emits null when no
  /// device has claimed the account.
  Stream<DeviceClaim?> watch();
}

/// Used in demo mode and in tests. Claims nothing, displaces nobody.
///
/// Demo mode has no Firebase and no second device to be displaced by --
/// a browser tab cannot take a session from itself -- so there is
/// nothing here to enforce and no honest way to show the rule working.
class NoOpSessionGuard implements SessionGuard {
  const NoOpSessionGuard();

  @override
  Future<void> claim(DeviceClaim claim) async {}

  @override
  Stream<DeviceClaim?> watch() => const Stream.empty();
}
