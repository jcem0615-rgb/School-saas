import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../widgets/privacy_notice_body.dart';

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
        // No "ask about my information" button any more: requests are
        // made to the office, and a button that only opened a screen
        // saying so would be an errand rather than an answer. The notice
        // itself says where to ask.
        children: [PrivacyNoticeBody(branding: branding)],
      ),
    );
  }
}
