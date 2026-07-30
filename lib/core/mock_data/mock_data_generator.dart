import 'dart:math';
import 'package:faker/faker.dart';
import 'package:uuid/uuid.dart';

import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../models/campus_models.dart';

class MockDataGenerator {
  static final _faker = Faker();
  static const _uuid = Uuid();
  static final _random = Random();

  // Indian names datasets for faker
  static const _firstNamesM = ['Aarav', 'Vihaan', 'Aditya', 'Arjun', 'Sai', 'Reyansh', 'Ayaan', 'Krishna', 'Ishaan', 'Shaurya', 'Sumit', 'Rahul', 'Rohan', 'Kabir'];
  static const _firstNamesF = ['Aadhya', 'Diya', 'Ananya', 'Saanvi', 'Pari', 'Avni', 'Riya', 'Isha', 'Meera', 'Kavya', 'Sneha', 'Neha', 'Pooja', 'Priya'];
  static const _lastNames = ['Sharma', 'Patel', 'Singh', 'Kumar', 'Mishra', 'Gupta', 'Verma', 'Reddy', 'Chauhan', 'Yadav', 'Joshi', 'Nair'];

  static const _departments = ['Computer Science', 'MBA', 'BCA', 'BBA', 'Mechanical', 'Civil', 'Electrical', 'AI & ML'];
  static const _interests = ['Coding', 'Dance', 'Photography', 'Music', 'Gaming', 'Football', 'Cricket', 'Startups', 'Travel', 'Fitness', 'Reading'];
  static const _languages = ['English', 'Hindi', 'Punjabi', 'Telugu', 'Tamil', 'Marathi'];
  static const _purposes = ['Friendship', 'Study Partner', 'Coffee Chat', 'Gym Partner', 'Gaming Partner', 'Project Partner', 'Startup Co-founder'];

  // Cache
  static final List<User> students = [];
  static final List<Chat> chats = [];
  static final List<Event> events = [];
  static final List<Community> communities = [];
  static final List<Poll> polls = [];

  static void initialize() {
    _generateStudents();
    _generateChats();
    _generateEvents();
    _generateCommunities();
    _generatePolls();
  }

  static void _generateStudents() {
    for (int i = 0; i < 120; i++) {
      bool isMale = _random.nextBool();
      String firstName = isMale ? _firstNamesM[_random.nextInt(_firstNamesM.length)] : _firstNamesF[_random.nextInt(_firstNamesF.length)];
      String lastName = _lastNames[_random.nextInt(_lastNames.length)];
      
      students.add(User(
        id: _uuid.v4(),
        name: '$firstName $lastName',
        username: '${firstName.toLowerCase()}${_random.nextInt(999)}',
        phoneNumber: '+91 9${_random.nextInt(900000000) + 100000000}',
        department: _departments[_random.nextInt(_departments.length)],
        course: ['BE', 'BSc', 'MSc', 'MBA'][_random.nextInt(4)],
        year: '${_random.nextInt(4) + 1}st Year',
        bio: "Passionate student exploring new things at Chandigarh University. Let's connect!",
        interests: _getRandomElements(_interests, 3),
        languages: _getRandomElements(_languages, 2),
        lookingFor: _getRandomElements(_purposes, 2),
        profilePhotoUrl: 'https://i.pravatar.cc/150?u=$firstName',
        trustLevel: TrustLevel.values[_random.nextInt(TrustLevel.values.length)],
        verificationLevel: VerificationLevel.values[_random.nextInt(VerificationLevel.values.length)],
        isOnline: _random.nextBool(),
        lastActive: DateTime.now().subtract(Duration(minutes: _random.nextInt(1000))),
        campusStatus: _random.nextBool() ? 'Need study partner for exams!' : null,
      ));
    }
  }

  static void _generateChats() {
    // Generate 40 chats
    for (int i = 0; i < 40; i++) {
      User otherUser = students[_random.nextInt(students.length)];
      
      // Generate random messages (up to 300 total across all chats, so avg 7-8 per chat)
      int messageCount = _random.nextInt(15) + 1;
      List<Message> messages = [];
      
      for (int m = 0; m < messageCount; m++) {
        bool isMe = _random.nextBool();
        messages.add(Message(
          id: _uuid.v4(),
          senderId: isMe ? 'me' : otherUser.id,
          content: _faker.lorem.sentence(),
          timestamp: DateTime.now().subtract(Duration(days: _random.nextInt(5), hours: _random.nextInt(24))),
          isSeen: _random.nextBool(),
        ));
      }

      // Sort by time
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      chats.add(Chat(
        id: _uuid.v4(),
        otherUser: otherUser,
        messages: messages,
        unreadCount: _random.nextInt(3),
      ));
    }
  }

  static void _generateEvents() {
    for (int i = 0; i < 25; i++) {
      events.add(Event(
        id: _uuid.v4(),
        title: '${_departments[_random.nextInt(_departments.length)]} ${_faker.lorem.word()} Fest',
        description: _faker.lorem.sentences(3).join(' '),
        category: ['Technical', 'Sports', 'Cultural', 'Workshop'][_random.nextInt(4)],
        organizer: '${students[_random.nextInt(students.length)].name}',
        date: DateTime.now().add(Duration(days: _random.nextInt(30))),
        venue: 'Block ${_random.nextInt(9) + 1} Auditorium',
        maxParticipants: _random.nextInt(100) + 50,
      ));
    }
  }

  static void _generateCommunities() {
    for (int i = 0; i < 18; i++) {
      bool isDept = _random.nextBool();
      communities.add(Community(
        id: _uuid.v4(),
        name: isDept ? '${_departments[_random.nextInt(_departments.length)]} Hub' : '${_interests[_random.nextInt(_interests.length)]} Society',
        description: 'Official community for discussions and updates.',
        isDepartment: isDept,
        memberCount: _random.nextInt(500) + 50,
      ));
    }
  }

  static void _generatePolls() {
    for (int i = 0; i < 12; i++) {
      polls.add(Poll(
        id: _uuid.v4(),
        question: 'What is your favorite ${_faker.lorem.word()}?',
        options: [
          PollOption(id: _uuid.v4(), text: 'Option A', votes: _random.nextInt(50)),
          PollOption(id: _uuid.v4(), text: 'Option B', votes: _random.nextInt(50)),
        ],
        authorId: students[_random.nextInt(students.length)].id,
      ));
    }
  }

  static List<T> _getRandomElements<T>(List<T> list, int count) {
    var copy = List<T>.from(list);
    copy.shuffle();
    return copy.take(count).toList();
  }
}
