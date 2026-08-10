import 'dart:math';
import 'package:uuid/uuid.dart';

import '../data/reference_data.dart';
import '../data/repositories/campus_repository.dart';
import '../models/user_model.dart';
import '../models/campus_models.dart';

/// The generated campus that stands in for Postgres when no credentials were
/// supplied.
///
/// This is a **fixture**, not a data source: nothing outside
/// `lib/core/data/repositories/` may reference it. Every screen and every
/// provider talks to a repository, and `Repositories` decides once at startup
/// whether that repository is the Supabase one or the mock one reading from
/// here. Keeping the app runnable with no project of its own is what lets the
/// migration happen one module at a time.
class MockDataGenerator {
  static const _uuid = Uuid();
  // Fixed seed so the same "campus" shows up on every launch of the demo.
  static final _random = Random(2126);

  static const _firstNamesM = ['Aarav', 'Vihaan', 'Aditya', 'Arjun', 'Sai', 'Reyansh', 'Ayaan', 'Krishna', 'Ishaan', 'Shaurya', 'Sumit', 'Rahul', 'Rohan', 'Kabir'];
  static const _firstNamesF = ['Aadhya', 'Diya', 'Ananya', 'Saanvi', 'Pari', 'Avni', 'Riya', 'Isha', 'Meera', 'Kavya', 'Sneha', 'Neha', 'Pooja', 'Priya'];
  static const _lastNames = ['Sharma', 'Patel', 'Singh', 'Kumar', 'Mishra', 'Gupta', 'Verma', 'Reddy', 'Chauhan', 'Yadav', 'Joshi', 'Nair'];

  /// The option lists live in [ReferenceOptions] now — in Supabase mode they
  /// come from `programs` and `tags`, and the generator has to draw from the
  /// same vocabulary or a generated student would carry interests no picker
  /// offers.
  static const departments = ReferenceOptions.defaultDepartments;
  static const interestPool = ReferenceOptions.defaultInterests;
  static const languagePool = ReferenceOptions.defaultLanguages;
  static const purposePool = ReferenceOptions.defaultPurposes;
  static const years = ReferenceOptions.defaultYears;

  static const _deptCodes = {
    'Computer Science': 'BCS',
    'AI & ML': 'BAI',
    'Information Technology': 'BIT',
    'Management': 'BBA',
    'Computer Applications': 'BCA',
    'Mechanical': 'BME',
    'Civil': 'BCV',
    'Electrical': 'BEE',
  };

  static const _deptCourses = {
    'Computer Science': 'B.E. CSE',
    'AI & ML': 'B.E. AI & ML',
    'Information Technology': 'B.E. IT',
    'Management': 'BBA',
    'Computer Applications': 'BCA',
    'Mechanical': 'B.E. ME',
    'Civil': 'B.E. CE',
    'Electrical': 'B.E. EE',
  };

  static const _bios = [
    'CSE student who lives on chai and late-night commits. Always up for a hackathon.',
    'Trying to balance placements prep with the dance society. Say hi if you are in Block 3!',
    'Looking for people to build side projects with. Flutter + Firebase is my comfort zone.',
    'Photography is my escape from assignments. I shoot most campus fests.',
    'Gym at 6am, lectures at 9, library till 10. Need a study partner who keeps up.',
    'Debate society regular. I will argue about anything, including which mess is best.',
    'Second year, still figuring things out. Happy to help juniors with DSA basics.',
    'Startup enthusiast. Currently validating an idea around campus logistics.',
  ];

  static const _statuses = [
    'Need study partner for exams!',
    'Free after 4pm, anyone for chai?',
    'Looking for a hackathon team',
    'At the library, Block 6',
    'Preparing for placements',
    null,
    null,
  ];

  // Cache
  static final List<User> students = [];
  static final List<Event> events = [];
  static final List<Community> communities = [];
  static final List<Club> clubs = [];
  static final List<StudyGroup> studyGroups = [];
  static final List<Project> projects = [];
  static final List<Poll> polls = [];
  static final List<CampusNotification> notifications = [];

  /// Groups the student is already a member of when the demo starts.
  static final Set<String> preJoinedCommunityIds = {};
  static final Set<String> preJoinedClubIds = {};
  static final Set<String> preJoinedStudyGroupIds = {};

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _generateStudents();
    _generateEvents();
    _generateCommunities();
    _generateClubs();
    _generateStudyGroups();
    _generateProjects();
    _generatePolls();
    _generateNotifications();
    _seedMemberships();
  }

  /// What `MockCampusRepository` is seeded with. The pre-joined ids are
  /// conversation ids: in mock mode an entity and its thread share one id,
  /// which is what `Community.conversationId` defaults to.
  static CampusSnapshot campusSnapshot() {
    initialize();
    return CampusSnapshot(
      events: List.of(events),
      communities: List.of(communities),
      clubs: List.of(clubs),
      studyGroups: List.of(studyGroups),
      projects: List.of(projects),
      polls: List.of(polls),
      notifications: List.of(notifications),
      joinedConversationIds: {
        ...preJoinedCommunityIds,
        ...preJoinedClubIds,
        ...preJoinedStudyGroupIds,
      },
    );
  }

  static String newId() => _uuid.v4();

  static void _generateStudents() {
    for (int i = 0; i < 120; i++) {
      final isMale = _random.nextBool();
      final firstName = isMale
          ? _firstNamesM[_random.nextInt(_firstNamesM.length)]
          : _firstNamesF[_random.nextInt(_firstNamesF.length)];
      final lastName = _lastNames[_random.nextInt(_lastNames.length)];
      final department = departments[_random.nextInt(departments.length)];
      final year = years[_random.nextInt(years.length)];
      final admissionYY = 26 - (years.indexOf(year) + 1);
      final roll = 1000 + _random.nextInt(8999);
      final uid = '$admissionYY${_deptCodes[department]}$roll';

      students.add(User(
        id: _uuid.v4(),
        name: '$firstName $lastName',
        username: '${firstName.toLowerCase()}${_random.nextInt(999)}',
        email: '${uid.toLowerCase()}@cuchd.in',
        uid: uid,
        phoneNumber: '+91 9${_random.nextInt(90000000) + 10000000}',
        gender: isMale ? 'Male' : 'Female',
        department: department,
        course: _deptCourses[department]!,
        year: year,
        bio: _bios[_random.nextInt(_bios.length)],
        interests: _pick(interestPool, 3),
        languages: _pick(languagePool, 2),
        lookingFor: _pick(purposePool, 2),
        profilePhotoUrl: 'https://i.pravatar.cc/300?img=${(i % 70) + 1}',
        trustLevel: _random.nextInt(10) < 7
            ? TrustLevel.trusted
            : TrustLevel.newVerified,
        verificationLevel: _random.nextInt(10) < 8
            ? VerificationLevel.studentId
            : VerificationLevel.email,
        badges: _random.nextBool() ? _pick(const ['Early Adopter', 'Helpful', 'Event Host'], 1) : const [],
        isOnline: _random.nextInt(10) < 3,
        lastActive: DateTime.now().subtract(Duration(minutes: _random.nextInt(2000))),
        campusStatus: _statuses[_random.nextInt(_statuses.length)],
      ));
    }
  }

  static const _eventTitles = [
    ['TechnoVate 2026 Hackathon', 'Technical', '36 hours of building, mentorship from industry engineers and a prize pool worth 2 lakh.'],
    ['Placement Prep Bootcamp', 'Workshop', 'Aptitude, DSA and mock interviews conducted by the training and placement cell.'],
    ['Zeitgeist Cultural Night', 'Cultural', 'The biggest cultural evening of the semester with performances from every society.'],
    ['Inter-Department Football Cup', 'Sports', 'Eight departments, one trophy. Register your team before the deadline.'],
    ['Flutter Study Jam', 'Workshop', 'Hands-on session building your first cross platform app. Bring your laptop.'],
    ['Startup Pitch Day', 'Technical', 'Pitch your idea to a panel of alumni founders and angel investors.'],
    ['Robowars Arena', 'Technical', 'Build a bot, break theirs. Registrations open for teams of four.'],
    ['Photography Walk', 'Cultural', 'Golden hour walk across campus with the photography society.'],
    ['AI & ML Guest Lecture', 'Workshop', 'A senior researcher walks through transformers from scratch.'],
    ['Freshers Welcome Party', 'Cultural', 'Music, games and the official welcome for the incoming batch.'],
    ['Marathon for a Cause', 'Sports', 'A 5K run around campus, all proceeds go to the campus NGO drive.'],
    ['Open Mic Night', 'Cultural', 'Poetry, stand-up and acoustic sets in the amphitheatre.'],
    ['Competitive Coding Contest', 'Technical', 'Three hours, six problems, ranked leaderboard with goodies.'],
    ['Resume Review Clinic', 'Workshop', 'Walk in with a draft, walk out with a recruiter-ready resume.'],
    ['Badminton Championship', 'Sports', 'Singles and doubles brackets across all years.'],
  ];

  static void _generateEvents() {
    for (int i = 0; i < _eventTitles.length; i++) {
      final data = _eventTitles[i];
      events.add(Event(
        id: _uuid.v4(),
        title: data[0],
        description: data[2],
        category: data[1],
        organizer: students[_random.nextInt(students.length)].name,
        date: DateTime.now().add(Duration(days: i * 2 + 1, hours: _random.nextInt(8) + 9)),
        venue: 'Block ${_random.nextInt(9) + 1}, ${['Auditorium', 'Seminar Hall', 'Ground', 'Lab 402'][_random.nextInt(4)]}',
        maxParticipants: _random.nextInt(150) + 50,
        goingCount: _random.nextInt(120) + 15,
        fee: _random.nextInt(3) == 0 ? '₹${(_random.nextInt(4) + 1) * 50}' : 'Free',
      ));
    }
  }

  static void _generateCommunities() {
    for (final dept in departments) {
      communities.add(Community(
        id: _uuid.v4(),
        name: '$dept Hub',
        description: 'Official space for $dept students — notes, notices and doubts.',
        isDepartment: true,
        memberCount: _random.nextInt(800) + 200,
      ));
    }
    const extras = [
      ['Hostel Block C', 'Everything happening inside Block C, from mess polls to lost items.'],
      ['Placement 2026', 'Drive updates, interview experiences and preparation resources.'],
      ['Campus Buy & Sell', 'Books, cycles, calculators — trade with people you actually know.'],
      ['Day Scholars', 'Bus timings, carpool coordination and off-campus meetups.'],
      ['Exam Warriors', 'Last minute doubts, previous year papers and moral support.'],
      ['Foodies of CU', 'Reviews of every canteen, cafe and late night stall around campus.'],
    ];
    for (final e in extras) {
      communities.add(Community(
        id: _uuid.v4(),
        name: e[0],
        description: e[1],
        isDepartment: false,
        memberCount: _random.nextInt(600) + 100,
      ));
    }
  }

  static const _clubData = [
    ['CodeChef CU Chapter', 'Technical', 'Weekly competitive programming contests and editorial sessions.', 'Every Saturday, 5:00 PM'],
    ['GDG on Campus', 'Technical', 'Google developer sessions, study jams and hackathon prep.', 'Alternate Fridays, 4:30 PM'],
    ['Nrityangana Dance Society', 'Cultural', 'Classical and western dance crew that performs at every fest.', 'Mon/Wed/Fri, 6:00 PM'],
    ['Shutterbugs Photography', 'Cultural', 'Photo walks, editing workshops and campus event coverage.', 'Sundays, 6:30 AM'],
    ['Robotics Society', 'Technical', 'Build combat bots, line followers and drone prototypes.', 'Tue/Thu, 5:00 PM'],
    ['Toastmasters CU', 'Literary', 'Public speaking practice in a friendly, structured format.', 'Every Wednesday, 5:30 PM'],
    ['Aavartan Music Club', 'Cultural', 'Band practice, open mics and recording sessions.', 'Daily, 7:00 PM'],
    ['E-Cell', 'Entrepreneurship', 'Startup mentorship, pitch practice and investor connects.', 'Every Thursday, 4:00 PM'],
    ['NSS Unit', 'Social', 'Village outreach, blood donation camps and cleanliness drives.', 'Weekends, 8:00 AM'],
    ['Esports Arena', 'Gaming', 'Valorant, BGMI and FIFA tournaments with cash prizes.', 'Fri/Sat, 8:00 PM'],
    ['Debating Society', 'Literary', 'Parliamentary debates and MUN preparation.', 'Every Tuesday, 6:00 PM'],
    ['Fine Arts Club', 'Cultural', 'Sketching, wall murals and fest decoration teams.', 'Sat/Sun, 3:00 PM'],
  ];

  static void _generateClubs() {
    for (final c in _clubData) {
      clubs.add(Club(
        id: _uuid.v4(),
        name: c[0],
        category: c[1],
        description: c[2],
        meetingSchedule: c[3],
        lead: students[_random.nextInt(students.length)].name,
        memberCount: _random.nextInt(350) + 40,
      ));
    }
  }

  static const _studyGroupData = [
    ['Data Structures', 'DSA Daily Grind', 'We solve three LeetCode problems a day and discuss approaches together.', 'Mon–Fri, 8:00 PM', 'Library, 2nd Floor'],
    ['DBMS', 'DBMS Doubt Circle', 'Normalisation, transactions and previous year papers before the mid-sem.', 'Tue & Thu, 6:00 PM', 'Block 6, Room 214'],
    ['Operating Systems', 'OS Concepts Crew', 'Walking through scheduling, deadlocks and memory management.', 'Wed & Sat, 5:00 PM', 'Study Hall, Block 3'],
    ['Aptitude', 'Placement Aptitude Squad', 'Timed quantitative and logical reasoning sets every session.', 'Daily, 7:30 AM', 'Cafeteria, Block 1'],
    ['Machine Learning', 'ML Paper Reading', 'One paper a week, one presenter, everyone discusses.', 'Sundays, 11:00 AM', 'AI Lab, Block 4'],
    ['Digital Electronics', 'DE Problem Solving', 'Karnaugh maps, flip-flops and circuit design practice.', 'Mon & Fri, 4:00 PM', 'Block 2, Lab 108'],
    ['Communication Skills', 'English Speaking Club', 'Only English for 90 minutes, judgement free zone.', 'Sat, 3:00 PM', 'Amphitheatre'],
    ['Thermodynamics', 'Thermo Study Group', 'Numerical practice with a focus on the university question pattern.', 'Tue & Sat, 6:30 PM', 'Block 5, Room 011'],
  ];

  static void _generateStudyGroups() {
    for (final s in _studyGroupData) {
      final host = students[_random.nextInt(students.length)];
      final max = _random.nextInt(6) + 6;
      studyGroups.add(StudyGroup(
        id: _uuid.v4(),
        subject: s[0],
        title: s[1],
        description: s[2],
        schedule: s[3],
        venue: s[4],
        hostId: host.id,
        hostName: host.name,
        memberCount: _random.nextInt(max - 2) + 2,
        maxMembers: max,
      ));
    }
  }

  static const _projectData = [
    ['Campus Lost & Found App', 'Building', 'A Flutter app where students can post and claim lost items with photo proof.', ['Flutter', 'Firebase'], ['UI Designer', 'Backend Dev']],
    ['Attendance Predictor', 'Prototype', 'Predicts how many lectures you can safely skip using your attendance history.', ['Python', 'Streamlit'], ['ML Engineer']],
    ['Mess Menu Rating Platform', 'Idea', 'Daily ratings for every mess so the committee actually sees the feedback.', ['React', 'Node.js'], ['Frontend Dev', 'Content Writer']],
    ['Smart Parking for Campus', 'Building', 'IoT sensors plus a mobile app showing free parking slots in real time.', ['Arduino', 'Flutter'], ['Hardware Lead', 'Mobile Dev']],
    ['Alumni Mentorship Portal', 'Prototype', 'Connects final year students with alumni working in their target companies.', ['Next.js', 'Postgres'], ['Full Stack Dev', 'Product Manager']],
    ['StudyBuddy AI', 'Idea', 'An AI study planner that builds a revision timetable from your syllabus PDF.', ['Python', 'FastAPI'], ['ML Engineer', 'UI Designer']],
    ['Campus Ride Share', 'Building', 'Carpool matching for day scholars travelling from the same locality.', ['Flutter', 'Supabase'], ['Mobile Dev', 'Marketing']],
    ['Event Ticketing System', 'Launched', 'QR based entry for fests, already used by two societies last semester.', ['React', 'Express'], ['Backend Dev']],
  ];

  static void _generateProjects() {
    for (final p in _projectData) {
      final owner = students[_random.nextInt(students.length)];
      projects.add(Project(
        id: _uuid.v4(),
        title: p[0] as String,
        description: p[2] as String,
        stage: p[1] as String,
        techStack: (p[3] as List).cast<String>(),
        rolesNeeded: (p[4] as List).cast<String>(),
        ownerId: owner.id,
        ownerName: owner.name,
        teamSize: _random.nextInt(4) + 1,
        applicantCount: _random.nextInt(14),
      ));
    }
  }

  static const _pollData = [
    ['Which mess serves the best dinner?', ['Block 1 Mess', 'Block 5 Mess', 'North Campus Mess', 'Food Court']],
    ['Best time slot for the hackathon?', ['Friday night', 'Saturday morning', 'Full weekend']],
    ['Should the library stay open 24x7 during exams?', ['Yes, definitely', 'No, current hours are fine']],
    ['Which elective is worth taking next sem?', ['Cloud Computing', 'Blockchain', 'Computer Vision', 'Game Dev']],
    ['How do you commute to campus?', ['Hostel, I walk', 'University bus', 'Own vehicle', 'Cab / auto']],
    ['Preferred fest headliner genre?', ['Bollywood', 'EDM', 'Indie', 'Punjabi']],
    ['Online or offline classes for theory subjects?', ['Offline', 'Online', 'Hybrid']],
    ['Best study spot on campus?', ['Central Library', 'Block 6 study hall', 'Cafeteria', 'Hostel room']],
  ];

  static void _generatePolls() {
    for (final p in _pollData) {
      final author = students[_random.nextInt(students.length)];
      polls.add(Poll(
        id: _uuid.v4(),
        question: p[0] as String,
        authorId: author.id,
        authorName: author.name,
        createdAt: DateTime.now().subtract(Duration(hours: _random.nextInt(72) + 1)),
        options: (p[1] as List)
            .cast<String>()
            .map((t) => PollOption(id: _uuid.v4(), text: t, votes: _random.nextInt(90) + 5))
            .toList(),
      ));
    }
  }

  static void _generateNotifications() {
    final samples = <List<dynamic>>[
      [CampusNotificationType.connection, 'New connection request', '${students[0].name} wants to connect as a Study Partner.', 2],
      [CampusNotificationType.message, 'New message', '${students[6].name} sent you a message.', 5],
      [CampusNotificationType.event, 'Event reminder', 'TechnoVate 2026 Hackathon starts tomorrow at 9:00 AM.', 8],
      [CampusNotificationType.connection, 'Request accepted', '${students[3].name} accepted your connection request.', 20],
      [CampusNotificationType.poll, 'Poll closing soon', 'Vote on "Which mess serves the best dinner?" before tonight.', 26],
      [CampusNotificationType.system, 'Profile verified', 'Your CU email has been verified. You now have full access.', 48],
      [CampusNotificationType.event, 'New event near you', 'Flutter Study Jam registrations just opened.', 52],
    ];

    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      notifications.add(CampusNotification(
        id: _uuid.v4(),
        type: s[0] as CampusNotificationType,
        title: s[1] as String,
        body: s[2] as String,
        timestamp: DateTime.now().subtract(Duration(hours: s[3] as int)),
        isRead: i > 3,
      ));
    }
  }

  /// Which communities, clubs and study groups the demo student already belongs
  /// to. Only the membership is seeded — the threads themselves are a server
  /// feature and there is no fixture for them.
  static void _seedMemberships() {
    // Two communities, one club and one study group are already joined.
    final seedCommunities = [
      communities.firstWhere((c) => c.name == 'Computer Science Hub',
          orElse: () => communities.first),
      communities.firstWhere((c) => c.name == 'Placement 2026',
          orElse: () => communities.last),
    ];
    for (final c in seedCommunities) {
      preJoinedCommunityIds.add(c.id);
    }
    preJoinedClubIds.add(clubs.first.id);
    preJoinedStudyGroupIds.add(studyGroups.first.id);
  }

  static List<T> _pick<T>(List<T> list, int count) {
    final copy = List<T>.from(list)..shuffle(_random);
    return copy.take(count).toList();
  }
}
