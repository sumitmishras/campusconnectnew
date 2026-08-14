import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/services/cu_identity.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import 'otp_screen.dart';

/// The single entry point for both signing in and signing up.
///
/// The student types the university id printed on their card — `21BCS5084` —
/// and nothing else. Before any mail goes out we ask the backend whether a
/// finished account already owns that id (`uid_exists`, migration 0014), so
/// the next screen can greet a returning student instead of talking to
/// everyone as if they were new.
///
/// That lookup is presentation only. Both branches take the identical OTP
/// path, and what actually happens after the code is verified is decided by
/// [AuthProvider.verifyOtp] reading the profile with a real session. Keeping
/// one flow is the point: two flows would need to be kept in step forever,
/// and every divergence between them would be a way to get stuck.
class EmailLoginScreen extends StatefulWidget {
  const EmailLoginScreen({super.key});

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

    // Does this id already have a finished account? `null` means the lookup
    // itself did not answer — a flaky network on the first screen. That is
    // deliberately not treated as "no account": the code still goes out, the
    // next screen just stays neutral, and verifyOtp decides for real.
    final isReturning = await auth.uidExists(input);
    if (!mounted) return;

    // The id is enough on its own; the domain is the same for every student.
    final email = CuIdentity.parse(input)!.email;

    final ok = await auth.requestOtp(email);
    if (!mounted) return;

    if (!ok) {
      setState(() => _error = auth.errorMessage);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OTPScreen(isReturning: isReturning)),
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
        // No "log in" / "sign up" split: which one this turns out to be is
        // worked out from the id, not chosen by the student up front.
        title: const Text('Campus Connect'),
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
                Text('My university\nID is', style: theme.textTheme.displayMedium),
                const SizedBox(height: 16),
                Text(
                  'Enter the ID printed on your student card. We will send a code to your @cuchd.in inbox — new here or coming back, it is the same step.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.textTheme.bodySmall?.color),
                ),
                const SizedBox(height: 32),
                CustomTextField(
                  label: 'University ID',
                  // "e.g." on purpose: a hint that reads exactly like a valid
                  // id looks like prefilled text you can just submit.
                  hint: 'e.g. 21BCS5084',
                  controller: _controller,
                  keyboardType: TextInputType.text,
                  prefixIcon: LucideIcons.idCard,
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
            'Just the ID — for example 21BCS5084. You can type the full '
            '@cuchd.in address if you prefer; personal Gmail or Outlook '
            'addresses are not accepted.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
