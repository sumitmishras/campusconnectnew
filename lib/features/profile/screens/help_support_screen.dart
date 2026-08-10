import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const _faqs = <List<String>>[
    [
      'Why do I need a @cuchd.in email?',
      'Campus Connect is only for Chandigarh University students. Verifying your university email keeps outsiders and fake profiles off the platform.',
    ],
    [
      'I did not receive my verification code',
      'Codes can take up to a minute. Check spam, then use the Resend Code button on the verification screen.',
    ],
    [
      'How do connection requests work?',
      'You pick a purpose (study partner, project partner, and so on) and send the request. The other student can accept or decline, and nothing is shared until they accept.',
    ],
    [
      'Can other students see my email or phone number?',
      'No. Your email is only used for verification and is never shown on your profile.',
    ],
    [
      'How do I report someone?',
      'Open their profile, tap the three-dot menu and choose Report. Student moderators review every report.',
    ],
    [
      'What happens when I block someone?',
      'They disappear from Discover, cannot message you, and your existing chat is removed. You can unblock from Privacy Settings.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Help & Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.primaryColor, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.helpCircle, color: Colors.white),
                const SizedBox(height: 12),
                Text('Need a hand?',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'The student support team replies within 24 hours on working days.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Frequently asked', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._faqs.map(
            (faq) => Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: Text(faq[0], style: theme.textTheme.bodyLarge),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(faq[1], style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text('Contact us', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.mail),
            title: const Text('support@campusconnect.cu'),
            subtitle: const Text('Email the support team'),
            onTap: () => showAppSnackBar(
                context, 'Copied support@campusconnect.cu',
                icon: LucideIcons.copy),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.messageSquare),
            title: const Text('Send feedback'),
            subtitle: const Text('Tell us what to build next'),
            onTap: () => _showFeedbackSheet(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.flag),
            title: const Text('Report a safety concern'),
            subtitle: const Text('Reviewed by student moderators'),
            onTap: () => _showFeedbackSheet(context, isSafety: true),
          ),
        ],
      ),
    );
  }

  void _showFeedbackSheet(BuildContext context, {bool isSafety = false}) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Text(
              isSafety ? 'Report a safety concern' : 'Send feedback',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              label: isSafety ? 'What happened?' : 'Your feedback',
              hint: isSafety
                  ? 'Describe the issue and who was involved...'
                  : 'What would make Campus Connect better?',
              controller: controller,
              maxLines: 4,
              maxLength: 500,
              autofocus: true,
            ),
            const SizedBox(height: 20),
            CustomButton(
              text: 'Submit',
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  showAppSnackBar(sheetContext, 'Please write something first',
                      icon: LucideIcons.circleAlert);
                  return;
                }
                Navigator.pop(sheetContext);
                showAppSnackBar(
                  context,
                  isSafety
                      ? 'Report submitted. Our team will look into it.'
                      : 'Thanks! Your feedback has been sent.',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
