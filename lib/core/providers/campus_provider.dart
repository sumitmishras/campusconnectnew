import 'package:flutter/material.dart';
import '../models/campus_models.dart';
import '../mock_data/mock_data_generator.dart';

class CampusProvider with ChangeNotifier {
  List<Event> _events = [];
  List<Community> _communities = [];
  List<Poll> _polls = [];
  bool _isLoading = false;

  List<Event> get events => _events;
  List<Community> get communities => _communities;
  List<Poll> get polls => _polls;
  bool get isLoading => _isLoading;

  CampusProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 600));

    if (MockDataGenerator.events.isEmpty) {
      MockDataGenerator.initialize();
    }
    
    _events = List.from(MockDataGenerator.events);
    _communities = List.from(MockDataGenerator.communities);
    _polls = List.from(MockDataGenerator.polls);
    
    _isLoading = false;
    notifyListeners();
  }

  void toggleEventInterest(String eventId) {
    // Mock logic for joining/saving an event
    notifyListeners();
  }

  void joinCommunity(String communityId) {
    // Mock logic for joining a community
    final index = _communities.indexWhere((c) => c.id == communityId);
    if (index != -1) {
      final c = _communities[index];
      _communities[index] = Community(
        id: c.id,
        name: c.name,
        description: c.description,
        isDepartment: c.isDepartment,
        memberCount: c.memberCount + 1,
      );
      notifyListeners();
    }
  }

  void votePoll(String pollId, String optionId) {
    final index = _polls.indexWhere((p) => p.id == pollId);
    if (index != -1) {
      final poll = _polls[index];
      if (!poll.hasVoted) {
        final updatedOptions = poll.options.map((o) {
          if (o.id == optionId) {
            return PollOption(id: o.id, text: o.text, votes: o.votes + 1);
          }
          return o;
        }).toList();

        _polls[index] = Poll(
          id: poll.id,
          question: poll.question,
          options: updatedOptions,
          authorId: poll.authorId,
          hasVoted: true,
        );
        notifyListeners();
      }
    }
  }
}
