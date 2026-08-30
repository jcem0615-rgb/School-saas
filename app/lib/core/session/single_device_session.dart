import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart'
    show authControllerProvider, authStateProvider;
import '../router/app_router.dart' show goRouterProvider;
import 'session_guard.dart';
import 'session_providers.dart';

/// Enforces one signed-in device per account, app-wide.
///
/// Installed via MaterialApp.builder so it covers every screen, and
/// returns its child unwrapped -- it adds no layout of its own, for the
/// same reason PaymentSubmissionAlerts does not.
///
/// ## Order matters
///
/// This device claims the account *first*, and only then starts watching
/// for somebody else's claim. The other order has a bug in it: on sign-in
/// the very first thing the stream delivers is whatever claim was already
/// there -- which, for anyone who last used a different device, is not
/// this one. A device that enforced on that emission would sign itself
/// out immediately after every sign-in on a second machine, and the
/// account would be unreachable from anywhere but the last device that
/// used it.
///
/// Claim-then-watch makes the newest sign-in the winner, which is the
/// behaviour a person expects: the device in your hand is the one that
/// works, and the one you left at home is the one that gets signed out.
class SingleDeviceSession extends ConsumerStatefulWidget {
  final Widget child;
  const SingleDeviceSession({super.key, required this.child});

  @override
  ConsumerState<SingleDeviceSession> createState() =>
      _SingleDeviceSessionState();
}

class _SingleDeviceSessionState extends ConsumerState<SingleDeviceSession> {
  /// The account this device has claimed, or null if none. Compared
  /// against the signed-in uid to notice sign-in, sign-out, and the
  /// one-signs-out-another-signs-in case on a shared school computer.
  String? _claimedFor;

  StreamSubscription<DeviceClaim?>? _watch;

  /// True between deciding we were displaced and the sign-out completing,
  /// so a second emission on the way out cannot start a second sign-out.
  bool _displacing = false;

  @override
  void dispose() {
    _watch?.cancel();
    super.dispose();
  }

  Future<void> _start(String uid) async {
    _stop();
    _claimedFor = uid;

    final deviceId = await ref.read(deviceIdentityProvider).id();
    // No stable id means no enforcement -- see DeviceIdentity.id. Also
    // covers demo mode, where the guard is a no-op anyway.
    if (deviceId == null || !mounted || _claimedFor != uid) return;

    final guard = ref.read(sessionGuardProvider);
    final label = ref.read(deviceIdentityProvider).label;

    try {
      await guard.claim(DeviceClaim(deviceId: deviceId, deviceLabel: label));
    } catch (_) {
      // Offline, or rules said no. Enforcing on a claim that never landed
      // would sign this device out on the strength of a stale document.
      return;
    }
    if (!mounted || _claimedFor != uid) return;

    _watch = guard.watch().listen(
      (claim) {
        if (!mounted || _claimedFor != uid || _displacing) return;
        if (verdictFor(myDeviceId: deviceId, claim: claim) ==
            SessionVerdict.displaced) {
          _displace(claim!.deviceLabel);
        }
      },
      // A dropped listener is not a reason to sign anybody out.
      onError: (_) {},
    );
  }

  /// Deliberately not async, and the cancel deliberately not awaited.
  ///
  /// This is called from inside the very subscription it cancels -- a
  /// displacement arrives as a stream event, and the first thing to do
  /// about it is stop listening. Awaiting `cancel()` there never returns:
  /// the future completes when the handler it was called from finishes,
  /// and the handler is waiting on the future. The sign-out sat behind
  /// that deadlock and simply never happened. Cancelling without waiting
  /// stops delivery immediately, which is the part that matters.
  void _stop() {
    _claimedFor = null;
    _watch?.cancel();
    _watch = null;
  }

  Future<void> _displace(String otherLabel) async {
    _displacing = true;
    _stop();
    // The ordinary sign-out path, so the push token is cleaned up here
    // exactly as it would be if the user had signed out themselves --
    // otherwise a displaced device keeps receiving this account's
    // notifications forever.
    await ref.read(authControllerProvider.notifier).logout();
    _displacing = false;
    _explain(otherLabel);
  }

  /// Says why the app went back to the sign-in screen.
  ///
  /// Without this the experience is indistinguishable from a crash or an
  /// expired session, and the person's next move is to sign in again --
  /// which displaces the device that displaced them, and so on. Naming
  /// the cause is what turns a loop into a decision.
  void _explain(String otherLabel) {
    // There is no Navigator above MaterialApp.builder, so the dialog goes
    // through the router's navigator key -- the same route
    // PaymentSubmissionAlerts takes to push a screen from here.
    final navigatorContext =
        ref.read(goRouterProvider).routerDelegate.navigatorKey.currentContext;
    if (navigatorContext == null) return;

    showDialog<void>(
      context: navigatorContext,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.phonelink_lock_outlined),
        title: const Text('Signed out'),
        content: Text(
          'Your account was signed in on $otherLabel, so this device was '
          'signed out.\n\n'
          'An account can only be signed in on one device at a time. If '
          'this was not you, sign in here and change your password.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    if (uid != _claimedFor && !_displacing) {
      // Deferred to the end of the frame: both branches touch providers
      // and one of them signs out, neither of which belongs in a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (uid == null) {
          _stop();
        } else if (uid != _claimedFor) {
          _start(uid);
        }
      });
    }

    return widget.child;
  }
}
