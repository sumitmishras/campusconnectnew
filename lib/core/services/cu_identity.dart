/// Everything we can derive from a Chandigarh University login id such as
/// `21bcs5084@cuchd.in`. Only `@cuchd.in` addresses are accepted.
class CuIdentity {
  static const String allowedDomain = 'cuchd.in';

  /// `21bcs5084` (lower case, without the domain).
  final String uid;

  /// Admission year in full, e.g. 2021.
  final int admissionYear;

  /// Three letter program code, e.g. `bcs`.
  final String programCode;

  /// Roll number within the batch, e.g. `5084`.
  final String rollNumber;

  final String department;
  final String course;

  const CuIdentity({
    required this.uid,
    required this.admissionYear,
    required this.programCode,
    required this.rollNumber,
    required this.department,
    required this.course,
  });

  /// Uppercase university id as printed on the ID card: `21BCS5084`.
  String get displayUid => uid.toUpperCase();

  String get email => '$uid@$allowedDomain';

  /// Current year of study, clamped to a sane 1..4 range for the demo.
  String get yearOfStudy {
    final now = DateTime.now();
    // The academic session rolls over in July.
    var elapsed = now.year - admissionYear + (now.month >= 7 ? 1 : 0);
    if (elapsed < 1) elapsed = 1;
    if (elapsed > 4) elapsed = 4;
    const suffixes = {1: 'st', 2: 'nd', 3: 'rd', 4: 'th'};
    return '$elapsed${suffixes[elapsed]} Year';
  }

  String get batchLabel => 'Batch $admissionYear';

  /// A stable, human looking suggestion for the username field.
  String get suggestedUsername => uid;

  static const Map<String, List<String>> _programs = {
    // code : [department, course]
    'bcs': ['Computer Science', 'B.E. CSE'],
    'bai': ['AI & ML', 'B.E. AI & ML'],
    'bit': ['Information Technology', 'B.E. IT'],
    'bec': ['Electronics & Comm.', 'B.E. ECE'],
    'bee': ['Electrical', 'B.E. EE'],
    'bme': ['Mechanical', 'B.E. ME'],
    'bcv': ['Civil', 'B.E. CE'],
    'bce': ['Civil', 'B.E. CE'],
    'bca': ['Computer Applications', 'BCA'],
    'mca': ['Computer Applications', 'MCA'],
    'mcs': ['Computer Science', 'M.E. CSE'],
    'bba': ['Management', 'BBA'],
    'mba': ['Management', 'MBA'],
    'bcm': ['Commerce', 'B.Com'],
    'bsc': ['Sciences', 'B.Sc'],
    'msc': ['Sciences', 'M.Sc'],
    'bph': ['Pharmacy', 'B.Pharm'],
    'bla': ['Law', 'BA LLB'],
    'bhm': ['Hotel Management', 'BHMCT'],
    'bjm': ['Journalism', 'BA JMC'],
    'bar': ['Architecture', 'B.Arch'],
    'bag': ['Agriculture', 'B.Sc Agriculture'],
  };

  /// Departments a student can pick from when the code is unknown.
  static List<String> get allDepartments {
    final set = _programs.values.map((v) => v[0]).toSet().toList()..sort();
    return set;
  }

  static final RegExp _uidPattern = RegExp(r'^(\d{2})([a-z]{3})(\d{3,5})$');

  /// Returns `null` when [input] is not a usable CU login id.
  static CuIdentity? parse(String input) {
    final cleaned = input.trim().toLowerCase();
    if (cleaned.isEmpty) return null;

    final uid = cleaned.contains('@') ? cleaned.split('@').first : cleaned;
    if (cleaned.contains('@') && cleaned.split('@').last != allowedDomain) {
      return null;
    }

    final match = _uidPattern.firstMatch(uid);
    if (match == null) return null;

    final yy = int.parse(match.group(1)!);
    final code = match.group(2)!;
    final program = _programs[code] ?? const ['Chandigarh University', 'Student'];

    return CuIdentity(
      uid: uid,
      admissionYear: 2000 + yy,
      programCode: code,
      rollNumber: match.group(3)!,
      department: program[0],
      course: program[1],
    );
  }

  /// Validation message for the login field, or `null` when the id is fine.
  static String? validate(String input) {
    final value = input.trim();
    if (value.isEmpty) return 'Please enter your CU email';

    if (!value.contains('@')) {
      return 'Use your full CU email, e.g. 21bcs5084@$allowedDomain';
    }
    final parts = value.toLowerCase().split('@');
    if (parts.length != 2 || parts.last != allowedDomain) {
      return 'Only @$allowedDomain emails can join Campus Connect';
    }
    if (parse(value) == null) {
      return 'That does not look like a CU University ID (e.g. 21BCS5084)';
    }
    return null;
  }
}
