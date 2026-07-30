import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import 'otp_screen.dart';

class MobileInputScreen extends StatefulWidget {
  const MobileInputScreen({super.key});

  @override
  State<MobileInputScreen> createState() => _MobileInputScreenState();
}

class _MobileInputScreenState extends State<MobileInputScreen> {
  final _phoneController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'My mobile\nnumber is',
                style: theme.textTheme.displayMedium,
              ),
              const SizedBox(height: 16),
              Text(
                'We will send you a verification code to verify your identity.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.brightness == Brightness.dark 
                      ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 48),
              CustomTextField(
                label: 'Mobile Number',
                hint: '+91 00000 00000',
                keyboardType: TextInputType.phone,
                controller: _phoneController,
                prefixIcon: LucideIcons.phone,
              ),
              const Spacer(),
              CustomButton(
                text: 'Continue',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OTPScreen(phoneNumber: _phoneController.text),
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
