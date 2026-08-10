import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/custom_button.dart';
import 'email_login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _open(BuildContext context, {required bool isReturning}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmailLoginScreen(isReturning: isReturning),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        // Scrolls instead of overflowing on short screens / landscape.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Clamped: the viewport is momentarily zero-height while the
                // keyboard animates, and a negative minimum is an assertion.
                minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Center(
                      child: Container(
                        height: 120,
                        width: 120,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.graduationCap,
                          size: 64,
                          color: theme.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Campus Connect',
                      style: theme.textTheme.displayLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Exclusive community for Chandigarh University students. Real connections, real campus life.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    _buildHighlights(theme),
                    const Spacer(),
                    CustomButton(
                      text: 'Get Started',
                      icon: LucideIcons.arrowRight,
                      onPressed: () => _open(context, isReturning: false),
                    ),
                    const SizedBox(height: 12),
                    CustomButton(
                      text: 'I already have an account',
                      isOutlined: true,
                      onPressed: () => _open(context, isReturning: true),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Only @cuchd.in emails can join.',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlights(ThemeData theme) {
    const items = <List<Object>>[
      [LucideIcons.shieldCheck, 'Verified students only'],
      [LucideIcons.users, 'Find study & project partners'],
      [LucideIcons.calendarDays, 'Every campus event in one place'],
    ];

    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item[0] as IconData,
                  size: 16,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(item[1] as String, style: theme.textTheme.bodyMedium),
            ],
          ),
        );
      }).toList(),
    );
  }
}
