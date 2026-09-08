import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;

/// Whether the signed-in account may change the school's records at all.
///
/// False for the Director and the Principal, who supervise rather than
/// operate: they read every screen they are entitled to and the editing
/// affordances on those screens are not offered to them. See
/// `UserRole.isOversightOnly` for what that means and
/// `docs/39-oversight-and-operations.md` for why.
///
/// This is a UX boundary, not the security one. `firestore.rules` and the
/// callables refuse the write regardless, and would do so if this
/// provider were wrong. What it buys is that a supervisor is never handed
/// a form to fill in that the server will then reject -- which the rest
/// of this codebase already treats as worse than no button at all.
final canOperateProvider = Provider<bool>((ref) {
  final role = ref.watch(authStateProvider).valueOrNull?.role;
  return role?.canOperate ?? false;
});
