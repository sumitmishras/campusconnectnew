/// Build-time configuration.
///
/// Credentials come from `--dart-define` so they never sit in source control:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// When they are absent the app runs entirely on mock data, exactly as it did
/// before the backend existed. That is deliberate: the migration from mock to
/// Supabase happens one module at a time, and the app has to stay runnable
/// throughout — including for anyone who clones the repo without a project of
/// their own.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True once both values are supplied. Every provider checks this to decide
  /// between the live backend and the mock one.
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// What this project's Auth settings are set to mail. Override without
  /// touching code if that setting changes:
  ///
  /// ```
  /// --dart-define=OTP_LENGTH=6
  /// ```
  ///
  /// Supabase's own default is 6; **this project is configured for 8**, which
  /// is what the verification mail actually contains.
  static const int _projectOtpLength = 8;

  static const int _configuredOtpLength =
      int.fromEnvironment('OTP_LENGTH', defaultValue: _projectOtpLength);

  /// The shortest code Supabase Auth can be configured to send. Used as the
  /// floor for "is this worth sending to the server", so a wrong [otpLength]
  /// degrades to the server saying "incorrect" rather than the screen refusing
  /// to submit at all.
  static const int minOtpLength = 6;

  /// How long a code is, and therefore how many boxes the OTP screen renders.
  ///
  /// This is the **only** place the number is decided — [AuthBackend]s read it
  /// rather than carrying their own, because a screen that renders six boxes
  /// for an eight-digit code is a sign-in nobody can complete.
  ///
  /// Clamped to the range Supabase Auth allows, so a typo in the define cannot
  /// lock the screen either. The mock flow uses four.
  static int get otpLength =>
      useSupabase ? _configuredOtpLength.clamp(minOtpLength, 10) : 4;

  /// Shown on the OTP screen only in mock mode, where no mail is ever sent.
  static bool get showsDemoOtp => !useSupabase;
}
