import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';

/// Every role gets this same screen (spec: "Unique QR for every user").
/// Deliberately renders the opaque `qrCode` token, never the raw uid --
/// the token is what markAttendance.ts looks up, and using an opaque
/// value means a leaked screenshot can't be reverse-engineered into
/// anything else about the account.
class MyQrIdScreen extends ConsumerWidget {
  const MyQrIdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('My QR ID')),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 36,
                            backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                            child: user.photoUrl == null ? const Icon(Icons.person, size: 36) : null,
                          ),
                          const SizedBox(height: 12),
                          Text(user.fullName, style: Theme.of(context).textTheme.titleLarge),
                          Text(user.role.displayName, style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: QrImageView(
                              data: user.qrCode,
                              version: QrVersions.auto,
                              size: 220,
                              gapless: false,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Present this code for attendance, entry, or verification.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
