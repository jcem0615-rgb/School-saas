import 'package:flutter/material.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../domain/entities/privacy_notice.dart';

/// The notice itself, without a Scaffold around it.
///
/// Separated so the same words appear on the standalone page and inside
/// the acknowledgement gate. A gate that summarises the notice instead
/// of showing it is a gate that records people agreeing to a summary.
class PrivacyNoticeBody extends StatelessWidget {
  final SchoolBranding branding;
  const PrivacyNoticeBody({super.key, required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schoolName = branding.schoolName?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(PrivacyNotice.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Version ${PrivacyNotice.version}'
          '${schoolName == null || schoolName.isEmpty ? '' : ' · $schoolName'}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Text(PrivacyNotice.preamble, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        Text('What is held', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final category in PrivacyNotice.categories)
          _CategoryCard(category: category),
        const SizedBox(height: 16),
        _Section(
          title: 'Who it is shared with',
          body: PrivacyNotice.sharing,
          icon: Icons.share_outlined,
        ),
        _Section(
          title: 'How long it is kept',
          body: PrivacyNotice.retention,
          icon: Icons.schedule_outlined,
        ),
        _Section(
          title: 'How it is protected',
          body: PrivacyNotice.security,
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 16),
        Text('What you can ask for', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final right in PrivacyNotice.rights)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(right.heading, style: theme.textTheme.titleSmall),
                Text(right.body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        const SizedBox(height: 8),
        _DpoCard(branding: branding),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final PrivacyCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category.name, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            _Line(label: 'What', value: category.holds),
            _Line(label: 'Why', value: category.why),
            // The question a family actually asks, and the one a notice
            // written from a template usually answers with "authorised
            // personnel".
            _Line(label: 'Who can see it', value: category.seenBy),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;
  final IconData icon;
  const _Section({required this.title, required this.body, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The named person a complaint goes to.
///
/// Shown as unset rather than hidden when the school has not named one.
/// A blank space says nothing; "your school has not named one yet" is
/// the prompt that gets one named, and it is the first thing a regulator
/// asks for.
class _DpoCard extends StatelessWidget {
  final SchoolBranding branding;
  const _DpoCard({required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = branding.dpoName?.trim();
    final email = branding.dpoEmail?.trim();
    final phone = branding.dpoPhone?.trim();
    final named = name != null && name.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data Protection Officer', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          if (!named)
            Text(
              'Your school has not named one in this system yet. Ask the '
              'school office who to contact about your information.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            Text(name, style: theme.textTheme.bodyMedium),
            if (email != null && email.isNotEmpty)
              SelectableText(email, style: theme.textTheme.bodySmall),
            if (phone != null && phone.isNotEmpty)
              SelectableText(phone, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
