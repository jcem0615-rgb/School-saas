import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../widgets/privacy_notice_body.dart';
import 'my_data_screen.dart';

/// The notice, on its own page.
///
/// Reachable from Profile at any time, not only at the moment somebody
/// is asked to acknowledge it. A notice you can only see once, while a
/// dialog is holding you at the door, is one nobody reads.
class PrivacyNoticeScreen extends ConsumerWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider).valueOrNull ?? SchoolBranding.empty;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PrivacyNoticeBody(branding: branding),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const MyDataScreen())),
            icon: const Icon(Icons.assignment_outlined),
            label: const Text('Ask about my information'),
          ),
        ],
      ),
    );
  }
}
