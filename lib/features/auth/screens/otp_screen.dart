import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../../navigation/main_navigation.dart';
import 'registration_wizard.dart';

class OTPScreen extends StatefulWidget {
  /// Whether the entry screen found a finished account for this id.
  ///
  /// Wording only — both branches verify the same code the same way, and what
  /// actually happens next is decided by [AuthProvider.verifyOtp] once there
  /// is a session. Null means the lookup did not answer, in which case the
  /// screen stays neutral rather than guessing.
  final bool? isReturning;

  const OTPScreen({super.key, this.isReturning});

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  late final int _length;
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  Timer? _timer;
  int _secondsLeft = 30;
  String? _error;

  String get _code => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    // One source of truth: `AppConfig.otpLength`. Six digits against Supabase
    // by default, four in the mock flow.
    _length = context.read<AuthProvider>().otpLength;
    _controllers = List.generate(_length, (_) => TextEditingController());
    _focusNodes = List.generate(_length, (_) => FocusNode());
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  void _onDigitChanged(String value, int index) {
    setState(() => _error = null);

    if (value.length > 1) {
      // Pasted code — spread it across the boxes.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      FocusScope.of(context).unfocus();
      _verify();
      return;
    }

    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (_code.length == _length) {
      FocusScope.of(context).unfocus();
      _verify();
    }
  }

  Future<void> _verify() async {
    final auth = context.read<AuthProvider>();
    // Deliberately not `!= _length`: pressing Verify with a code shorter than
    // the boxes should reach the server, so a misconfigured length is an
    // "incorrect code" at worst instead of a screen that cannot be submitted.
    if (_code.isEmpty) {
      setState(() => _error = 'Enter the code we emailed you');
      return;
    }

    final ok = await auth.verifyOtp(_code);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _error = auth.errorMessage ?? 'Incorrect code';
        for (final c in _controllers) {
          c.clear();
        }
      });
      _focusNodes[0].requestFocus();
      return;
    }

    final destination = auth.status == AuthStatus.loggedIn
        ? const MainNavigation()
        : const RegistrationWizard();

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    await context.read<AuthProvider>().resendOtp();
    if (!mounted) return;
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
    _startCountdown();
    showAppSnackBar(context, 'A new code has been sent', icon: LucideIcons.mail);
  }

  void _autofill() {
    final otp = context.read<AuthProvider>().demoOtp;
    if (otp.length != _length) return;
    for (var i = 0; i < _length; i++) {
      _controllers[i].text = otp[i];
    }
    setState(() => _error = null);
    FocusScope.of(context).unfocus();
    _verify();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final email = auth.pendingIdentity?.email ?? 'your CU email';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (widget.isReturning) {
                  true => 'Welcome\nback',
                  false => 'Let\'s get you\nset up',
                  null => 'Enter your\ncode',
                },
                style: theme.textTheme.displayMedium,
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.textTheme.bodySmall?.color),
                  children: [
                    TextSpan(text: 'We sent a $_length-digit code to '),
                    TextSpan(
                      text: email,
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Against a real backend the code went to an actual inbox, so
              // there is nothing to reveal and no autofill to offer.
              if (auth.showsDemoOtp) ...[
                _buildDemoBanner(theme, auth.demoOtp),
                const SizedBox(height: 32),
              ],
              // Sized from the available width rather than fixed: this has to
              // hold anywhere from four boxes to ten without overflowing a
              // phone, and the count comes from configuration.
              Row(
                children: [
                  for (var index = 0; index < _length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Expanded(child: _buildDigitBox(theme, index)),
                  ],
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: _secondsLeft > 0 ? null : _resend,
                  child: Text(
                    _secondsLeft > 0
                        ? 'Resend code in ${_secondsLeft}s'
                        : 'Resend Code',
                    style: TextStyle(
                      color: _secondsLeft > 0
                          ? theme.textTheme.bodySmall?.color
                          : theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Verify',
                isLoading: auth.isBusy,
                onPressed: _verify,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDigitBox(ThemeData theme, int index) {
    // Six 64pt boxes fit a phone; eight do not, so the digit shrinks with the
    // count instead of the row overflowing.
    final style = _length > 6
        ? theme.textTheme.headlineSmall
        : theme.textTheme.displayMedium;

    return TextFormField(
      controller: _controllers[index],
      focusNode: _focusNodes[index],
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofocus: index == 0,
      style: style,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        contentPadding:
            EdgeInsets.symmetric(vertical: _length > 6 ? 12 : 16),
      ),
      onChanged: (value) => _onDigitChanged(value, index),
    );
  }

  /// There is no real mail server in the demo, so the code is shown here.
  Widget _buildDemoBanner(ThemeData theme, String otp) {
    return InkWell(
      onTap: _autofill,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.primaryColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.sparkles, size: 18, color: theme.primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Demo mode — your code is $otp. Tap to fill it in.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
