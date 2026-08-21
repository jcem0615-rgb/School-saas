import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/router/app_router.dart' show goRouterProvider;
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../domain/entities/payment_submission.dart';
import '../controllers/payment_controller.dart' show pendingSubmissionsProvider;
import '../screens/payment_review_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Roles that get told, in the moment, that money has been claimed.
///
/// Only the cashier for now. Director and Admin can also read and decide
/// submissions (see `firestore.rules`), but they are not sitting on the
/// review queue as a job, and a pop-up per payment would be noise to
/// them. Adding them is a one-line change here if a school wants it.
const _alertedRoles = {UserRole.registrar};

/// Tells the cashier, wherever they are in the app, that a family has just
/// submitted an online payment.
///
/// Online payments are a claim, not a fact -- nothing moves the student's
/// balance until a registrar approves the submission. That makes the
/// waiting time between "family sent money" and "cashier noticed" the
/// weak point in the flow: the family has paid and is waiting, and the
/// only thing standing between them and a credited account is somebody
/// opening the Online Payments screen. Before this, nothing said a
/// submission had arrived; you found out by going and looking.
///
/// Installed via MaterialApp.builder so it covers every screen, and
/// deliberately returns its child *unwrapped* -- it adds no layout of its
/// own. (See the note in demo_switcher.dart: wrapping the router's content
/// in a Stack at this level has consequences on the first frame.)
class PaymentSubmissionAlerts extends ConsumerStatefulWidget {
  final Widget child;
  const PaymentSubmissionAlerts({super.key, required this.child});

  @override
  ConsumerState<PaymentSubmissionAlerts> createState() =>
      _PaymentSubmissionAlertsState();
}

class _PaymentSubmissionAlertsState
    extends ConsumerState<PaymentSubmissionAlerts> {
  /// Submissions this app session has already accounted for.
  ///
  /// Null until the first emission arrives. That first emission is the
  /// queue as it already stood, and is swallowed on purpose: opening the
  /// app to a backlog of eight pending submissions should show you a
  /// review queue, not eight pop-ups. Only what lands *after* that is
  /// news.
  ///
  /// Kept across sign-outs and role changes rather than reset, so it means
  /// "what this session has already seen" and not "what the current login
  /// has seen". On a shared front-desk machine where one cashier signs out
  /// and the next signs in, that difference matters: a submission that
  /// arrived in between is news to the person now looking at the screen,
  /// and re-baselining on every sign-in would silently swallow it. A fresh
  /// app launch still starts from a clean baseline, so the backlog never
  /// arrives as a burst of pop-ups.
  Set<String>? _accountedFor;

  /// Ids are added and never removed. Once approved, a submission leaves
  /// the pending stream -- if it ever reappeared, re-announcing it as new
  /// would be a lie.
  void _absorb(Iterable<String> ids) => _accountedFor!.addAll(ids);

  void _onSubmissions(List<PaymentSubmission> submissions) {
    final ids = submissions.map((s) => s.id);
    if (_accountedFor == null) {
      _accountedFor = ids.toSet();
      return;
    }
    final fresh =
        submissions.where((s) => !_accountedFor!.contains(s.id)).toList();
    _absorb(ids);
    if (fresh.isEmpty) return;

    // Showing a SnackBar synchronously from a provider listener can land
    // mid-build; defer to the end of the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final submission in fresh) {
        _announce(submission);
      }
    });
  }

  void _announce(PaymentSubmission submission) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 460,
        duration: const Duration(seconds: 8),
        content: Row(
          children: [
            const Icon(Icons.payments_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_currencyFormat.format(submission.amount)} from '
                    '${submission.studentName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${submission.method.displayLabel} · '
                    '${submission.purpose.displayLabel} · '
                    'Ref ${submission.referenceNumber}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Review',
          onPressed: _openReviewQueue,
        ),
      ),
    );
  }

  /// The review screen is pushed imperatively from the Registrar
  /// dashboard rather than being a named route, so this goes through the
  /// router's navigator key -- there is no Navigator above
  /// MaterialApp.builder to use directly.
  void _openReviewQueue() {
    final navigator =
        ref.read(goRouterProvider).routerDelegate.navigatorKey.currentState;
    navigator?.push(
      MaterialPageRoute(builder: (_) => const PaymentReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role;

    if (role == null || !_alertedRoles.contains(role)) {
      // Signed out, or signed in as somebody who does not review payments.
      // The baseline is deliberately left alone -- see the field comment.
      return widget.child;
    }

    // Watched rather than listened to, so the very first emission -- the
    // queue as it already stands -- also goes through _onSubmissions and
    // becomes the baseline. Rebuilds are free: `widget.child` is the same
    // instance every time, so the app below is not rebuilt.
    final submissions = ref.watch(pendingSubmissionsProvider).valueOrNull;
    if (submissions != null) _onSubmissions(submissions);

    return widget.child;
  }
}
