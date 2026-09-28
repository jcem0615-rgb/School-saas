import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import 'theme_choice.dart';
import 'theme_preference.dart';

/// Which theme the person signed in right now has chosen.
///
/// It watches who is signed in, so signing out and signing back in as
/// somebody else swaps the theme with the account rather than leaving
/// the second person with the first one's preference. On a school's
/// shared front desk computer that is the whole point of storing it per
/// account at all.
///
/// The read is synchronous -- see [ThemePreference] -- so the first
/// frame is already the right colour and nothing flashes.
final themeChoiceProvider =
    NotifierProvider<ThemeController, ThemeChoice>(ThemeController.new);

class ThemeController extends Notifier<ThemeChoice> {
  String? _uid;

  /// What has been chosen this session, per account.
  ///
  /// Riverpod re-runs [build] whenever the account stream emits --
  /// including when it emits the *same* account, which a profile edit
  /// does. Re-reading storage then would undo a choice made a moment
  /// earlier whose write had not yet reached the disk. This is what
  /// makes the switch stay where it was put.
  final _chosen = <String, ThemeChoice>{};

  static const _nobody = '';

  @override
  ThemeChoice build() {
    // valueOrNull, not a switch on the AsyncValue: while auth is still
    // resolving there is no account to ask, and the device's last
    // choice is a better guess than white.
    _uid = ref.watch(authStateProvider).valueOrNull?.uid;
    return _chosen[_uid ?? _nobody] ?? ThemePreference.read(_uid);
  }

  /// Applies a choice now, and remembers it.
  ///
  /// The state moves first and the write is awaited after. A switch
  /// that waited on a disk before moving is a switch that feels broken
  /// on a slow device -- and if the write fails, the theme is still
  /// right for this session, which is the part the person can see.
  Future<void> choose(ThemeChoice choice) async {
    if (state == choice) return;
    final uid = _uid;
    _chosen[uid ?? _nobody] = choice;
    state = choice;
    await ThemePreference.write(uid, choice);
  }
}
