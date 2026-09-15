import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/push/push_providers.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../emergency/presentation/screens/emergency_contacts_screen.dart';
import '../controllers/profile_controller.dart';
import '../../../../core/install/install_app_button.dart';
import '../../../../core/storage/uploaded_image.dart';
import '../../../../core/utils/validators.dart';

/// Every role's Profile screen (General Requirement). Shows identity
/// fields as read-only (name, role, email -- these are staff/admin-
/// managed, not self-editable, per the firestore.rules field boundary
/// established in Module 4) and allows editing only what the rules
/// actually permit: phone number and photo URL.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _phoneController = TextEditingController();

  /// What the account had when this screen opened, so Cancel can put it
  /// back and Save can tell a deliberate clear from an untouched field.
  String _savedPhone = '';

  /// Set once the signed-in user has been read. The controller cannot be
  /// filled in `initState` -- the user is a provider, not a constructor
  /// argument -- and refilling it on every build would fight the person
  /// typing into it.
  bool _phoneLoaded = false;

  String? _phoneError;
  bool _editing = false;
  /// Null until we have asked the registrar. Rendering the switch off
  /// before that would show every returning user a lie for a frame.
  bool? _pushOn;
  bool _pushBusy = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Reflects the real state of this device rather than a preference we
    // stored and hoped still matched: a user can revoke notification
    // permission in the browser without ever opening the app.
    Future.microtask(() async {
      final on = await ref.read(pushRegistrarProvider).isRegistered();
      if (mounted) setState(() => _pushOn = on);
    });
  }

  Future<void> _togglePush(bool wanted) async {
    setState(() => _pushBusy = true);
    final registrar = ref.read(pushRegistrarProvider);
    var on = false;
    if (wanted) {
      on = await registrar.register();
    } else {
      await registrar.unregister();
    }
    if (!mounted) return;
    setState(() {
      _pushOn = on;
      _pushBusy = false;
    });
    if (wanted && !on) {
      // The most common cause by far is a declined permission prompt, and
      // that is not something the app can retry its way out of -- say so
      // and point at the fix rather than silently flipping back.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text(
            'Notifications are blocked for this site. Allow them in your '
            'browser settings, then try again.',
          ),
        ));
    }
  }

  /// Asks first, and names the account being signed out.
  ///
  /// The name is there because school computers are shared: the person at
  /// the keyboard is not always the person the app is signed in as, and
  /// "Sign out?" alone tells them nothing about whose session they are
  /// about to end.
  Future<void> _signOut() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout),
        title: const Text('Sign out?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (user != null) ...[
              Text('You are signed in as ${user.fullName} (${user.email}).'),
              const SizedBox(height: 12),
            ],
            Text(
              'This device will stop receiving notifications for this '
              'account, and you will need your password to sign back in.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(authControllerProvider.notifier).logout();
    // No navigation here: the router redirects on the auth state change.
    // Popping as well would race it and briefly show the screen behind.
  }

  Future<void> _save() async {
    final typed = _phoneController.text.trim();

    // The same check provisioning and the employee import already run,
    // on the one screen where a person edits their own number. A number
    // `resetPasswordByPhone` cannot match recovers nothing, and the
    // account finds that out on the day it cannot sign in.
    final error = Validators.optionalPhilippineMobile(typed);
    if (error != null) {
      setState(() => _phoneError = error);
      return;
    }

    // Clearing it is allowed -- somebody changing numbers has to be able
    // to -- but it is a real loss and is said out loud rather than
    // reported as "Profile updated."
    final clearing = typed.isEmpty && _savedPhone.isNotEmpty;

    final success = await ref
        .read(profileActionControllerProvider.notifier)
        .updateProfile(phone: typed);
    if (!mounted) return;

    setState(() {
      _phoneError = null;
      _editing = false;
      if (success) {
        _savedPhone = typed;
      } else {
        // The write did not land, so the screen must not go on showing
        // the new number as though it had.
        _phoneController.text = _savedPhone;
      }
    });

    final message = !success
        ? 'Could not save. Your number is unchanged.'
        : clearing
            ? 'Phone number removed. You can no longer reset your password by phone.'
            : 'Profile updated.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // The number on file, put into the field the first time we have it.
    //
    // It was never put there at all: `AppUser` carried no `phone`, so the
    // row read "Not set" for every account whatever the school had
    // collected -- and tapping Edit then Save sent the empty string,
    // which the datasource writes, wiping the number `resetPasswordByPhone`
    // matches. The most natural thing to do when a field says "Not set"
    // destroyed the account's phone recovery.
    if (!_phoneLoaded) {
      _phoneLoaded = true;
      _savedPhone = user.phone ?? '';
      _phoneController.text = _savedPhone;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _signOut,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: UploadedImage.circle(
              url: user.photoUrl,
              radius: 40,
              fallback: const Icon(Icons.person, size: 40),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.fullName, style: Theme.of(context).textTheme.titleLarge)),
          Center(child: Text(user.role.displayName, style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: 32),
          _InfoTile(label: 'Email', value: user.email),
          const SizedBox(height: 8),
          if (_editing)
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Phone',
                errorText: _phoneError,
                // Said here rather than discovered later. This number is
                // how the account is recovered when the password is gone.
                helperText: 'Used to reset your password and to reach you.',
                hintText: '09171234567',
              ),
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
            )
          else
            _InfoTile(
              label: 'Phone',
              value: _savedPhone.isEmpty ? 'Not set' : _savedPhone,
            ),
          const SizedBox(height: 16),
          if (_editing)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    // Puts back what was on file. Leaving whatever was
                    // half-typed in the box would make the next Save
                    // write it.
                    onPressed: () => setState(() {
                      _phoneController.text = _savedPhone;
                      _phoneError = null;
                      _editing = false;
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _save, child: const Text('Save'))),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          const Divider(height: 40),
          Text('More', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text('My QR ID'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/qr-id'),
          ),
          // On Profile because Profile is the one screen all ten portals
          // share. A right that can only be exercised by finding the
          // right office at the right hour is a right on paper.
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy and my information'),
            subtitle: const Text('What the school holds, and how to ask about it'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('My Attendance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/my-attendance'),
          ),
          // Every role reaches the school's emergency numbers from here.
          // Profile is the one screen all ten portals share, which is why
          // it is the honest place for something everyone must be able to
          // find.
          ListTile(
            leading: const Icon(Icons.emergency_outlined),
            title: const Text('Emergency Numbers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
            ),
          ),
          const Divider(height: 40),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Announcements on this device'),
            subtitle: const Text(
              'Get a notification when the school posts an announcement '
              'for you — even when the app is closed.',
            ),
            value: _pushOn ?? false,
            onChanged: _pushBusy || _pushOn == null ? null : _togglePush,
          ),
          // Renders nothing unless this is a browser that can install,
          // so the phone and desktop builds never show a row offering to
          // install what is already installed. Here as well as on the
          // sign-in screen: somebody who signed in first and only later
          // wants it on their home screen has nowhere else to look.
          const InstallAppButton(),
          const Divider(height: 40),
          // Spelled out, at the bottom, where a settings screen's last
          // item is always the one that ends the session.
          //
          // There was already a sign-out here, as an unlabelled icon in
          // the app bar -- which is to say it was two taps behind a
          // person-outline icon and then a symbol. People asked where
          // sign-out was while looking at it. An icon is a reminder for
          // somebody who already knows the button exists; it is not how
          // anybody finds one.
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
            ),
            child: ListTile(
              leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
              title: Text(
                'Sign out',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text('End your session on this device', style: Theme.of(context).textTheme.bodySmall),
              onTap: _signOut,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
