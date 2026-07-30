import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/custom_button.dart';
import 'mobile_input_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // App Logo or Icon
              Container(
                height: 120,
                width: 120,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.graduationCap,
                    size: 64,
                    color: theme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              Text(
                'Campus Connect',
                style: theme.textTheme.displayLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Exclusive community for Chandigarh University students. Real connections, real campus life.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              CustomButton(
                text: 'Get Started',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MobileInputScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              CustomButton(
                text: 'I already have an account',
                isOutlined: true,
                onPressed: () {
                  // Navigate to login
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MobileInputScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
