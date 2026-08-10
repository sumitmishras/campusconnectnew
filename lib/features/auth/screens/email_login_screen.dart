import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/services/cu_identity.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import 'otp_screen.dart';

/// Login / signup with a Chandigarh University email (`21bcs5084@cuchd.in`).
class EmailLoginScreen extends StatefulWidget {
  final bool isReturning;

  const EmailLoginScreen({super.key, this.isReturning = false});

  @override
  State<EmailLoginScreen> createState() => _EmailLoginScreenState();
}

class _EmailLoginScreenState extends State<EmailLoginScreen> {
  final _controller = TextEditingController();
  String? _error;
  CuIdentity? _preview;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _error = null;
      // Live preview once the id itself is complete, with or without domain.
      _preview = CuIdentity.parse(value);
    });
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();

    final input = _controller.text.trim();
    final validation = CuIdentity.validate(input);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final ok = await auth.requestOtp(input);
    if (!mounted) return;

    if (!ok) {
      setState(() => _error = auth.errorMessage);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OTPScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = context.watch<AuthProvider>().isBusy;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isReturning ? 'Welcome back' : 'Join Campus Connect'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.vertical -
                  kToolbarHeight -
                  48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('My CU email\nis', style: theme.textTheme.displayMedium),
                const SizedBox(height: 16),
                Text(
                  'Campus Connect is only for Chandigarh University students, so we verify your @cuchd.in address before letting you in.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 32),
                CustomTextField(
                  label: 'University Email',
                  hint: '21bcs5084@cuchd.in',
                  controller: _controller,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: LucideIcons.mail,
                  autofocus: true,
                  errorText: _error,
                  onChanged: _onChanged,
                  onSubmitted: (_) => _continue(),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                ),
                const SizedBox(height: 16),
                if (_preview != null) _buildPreview(theme, _preview!),
                const SizedBox(height: 24),
                _buildDomainNote(theme),
                const SizedBox(height: 32),
                CustomButton(
                  text: 'Send verification code',
                  isLoading: isBusy,
                  onPressed: _continue,
                ),
                const SizedBox(height: 16),
                Text(
                  'By continuing you agree to keep this space respectful. '
                  'Your email is never shown to other students.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows what we decoded from the UID so the student knows we recognised it.
  Widget _buildPreview(ThemeData theme, CuIdentity id) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.badgeCheck, color: theme.primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id.displayUid,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.primaryColor),
                ),
                const SizedBox(height: 2),
                Text(
                  '${id.course} • ${id.department} • ${id.yearOfStudy} • ${id.batchLabel}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainNote(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.info, size: 16, color: theme.textTheme.bodySmall?.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Use the university id printed on your ID card, for example '
            '21BCS5084@cuchd.in. Personal Gmail or Outlook addresses are rejected.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
