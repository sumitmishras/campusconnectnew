/// Reasons a student can give when reporting someone.
///
/// The wire values are exactly the CHECK constraint on `public.reports.reason`
/// in `0006_notifications_and_moderation.sql`. Sending anything else fails the
/// whole INSERT, so the UI can never be allowed to post its own label text —
/// which is what it used to do.
enum ReportReason {
  spam,
  harassment,
  hateSpeech,
  nudity,
  impersonation,
  scam,
  selfHarm,
  other,
}

extension ReportReasonX on ReportReason {
  static const _wire = {
    ReportReason.spam: 'spam',
    ReportReason.harassment: 'harassment',
    ReportReason.hateSpeech: 'hate_speech',
    ReportReason.nudity: 'nudity',
    ReportReason.impersonation: 'impersonation',
    ReportReason.scam: 'scam',
    ReportReason.selfHarm: 'self_harm',
    ReportReason.other: 'other',
  };

  /// The value stored in `reports.reason`.
  String get wire => _wire[this]!;

  /// What the student reads. Deliberately unchanged from the strings the
  /// report sheet already showed.
  String get label {
    switch (this) {
      case ReportReason.impersonation:
        return 'Fake or impersonating profile';
      case ReportReason.harassment:
        return 'Harassment or bullying';
      case ReportReason.nudity:
        return 'Inappropriate content';
      case ReportReason.spam:
        return 'Spam or scam';
      case ReportReason.hateSpeech:
        return 'Hate speech';
      case ReportReason.scam:
        return 'Scam or fraud';
      case ReportReason.selfHarm:
        return 'Self-harm or suicide';
      case ReportReason.other:
        return 'Something else';
    }
  }

  static ReportReason parse(Object? value,
      {ReportReason fallback = ReportReason.other}) {
    if (value is ReportReason) return value;
    if (value is String) {
      for (final entry in _wire.entries) {
        if (entry.value == value) return entry.key;
      }
    }
    return fallback;
  }
}

/// What the report sheet on a profile offers, in order. Five options, matching
/// the list that was there before — the difference is that each one now
/// carries a value the database will accept.
const List<ReportReason> kProfileReportReasons = [
  ReportReason.impersonation,
  ReportReason.harassment,
  ReportReason.nudity,
  ReportReason.spam,
  ReportReason.other,
];
