import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart' show goRouterProvider;
import '../features/auth/domain/entities/app_user.dart';
import '../features/auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import 'demo_overrides.dart';
import 'demo_store.dart';

/// Floating "Demo accounts" control layered over the whole app.
///
/// There are ten roles and each one lands on a different portal, so
/// signing out and back in through the login form ten times is the main
/// friction in evaluating this app. This lets you jump between roles in
/// one tap.
///
/// It draws its own panel inside a [Stack] rather than using
/// showModalBottomSheet, because it is installed via MaterialApp.builder,
/// which sits *above* the router's Navigator -- there is no Navigator in
/// scope at this point in the tree.
class DemoSwitcher extends ConsumerStatefulWidget {
  final Widget child;
  const DemoSwitcher({super.key, required this.child});

  @override
  ConsumerState<DemoSwitcher> createState() => _DemoSwitcherState();
}

class _DemoSwitcherState extends ConsumerState<DemoSwitcher> {
  bool _open = false;

  void _signInAs(AppUser user) {
    demoSignInAs(
      ref.read(demoAuthRepositoryProvider),
      ref.read(goRouterProvider),
      user,
    );
    setState(() => _open = false);
  }

  void _signOut() {
    ref.read(demoAuthRepositoryProvider).logout();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // authStateProvider, not the store's subject directly: watching the
    // store would only rebuild if the store instance itself changed, so
    // the checkmark would never follow the signed-in role.
    final current = ref.watch(authStateProvider).valueOrNull;

    return Stack(
      children: [
        widget.child,
        if (_open)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _open = false),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_open) _panel(theme, current),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'demo-switcher',
                  onPressed: () => setState(() => _open = !_open),
                  icon: Icon(_open ? Icons.close : Icons.switch_account),
                  label: Text(_open ? 'Close' : 'Demo accounts'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(ThemeData theme, AppUser? current) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: theme.colorScheme.primaryContainer,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demo mode',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'In-memory data, no Firebase. Tap a role to sign in as them. '
                    'Password for all accounts: ${DemoStore.password}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: DemoStore.demoAccounts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final user = DemoStore.demoAccounts[i];
                  final isCurrent = current?.uid == user.uid;
                  return ListTile(
                    dense: true,
                    selected: isCurrent,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      child: Text(
                        user.firstName.characters.first,
                        style: TextStyle(
                          fontSize: 13,
                          color: isCurrent
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(user.role.displayName),
                    subtitle: Text(
                      '${user.fullName} · ${user.email}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isCurrent ? const Icon(Icons.check, size: 18) : null,
                    onTap: () => _signInAs(user),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    current == null
                        ? 'Signed out'
                        : 'Signed in as ${current.role.displayName}',
                    style: theme.textTheme.bodySmall,
                  ),
                  TextButton.icon(
                    onPressed: current == null ? null : _signOut,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
