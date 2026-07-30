import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../mock_data/mock_data_generator.dart';

class UserProvider with ChangeNotifier {
  List<User> _allStudents = [];
  List<User> _filteredStudents = [];
  bool _isLoading = false;
  
  // Track mock connection requests. Map of userId -> request status (e.g. 'Requested')
  final Map<String, String> _connectionStatuses = {};

  List<User> get students => _filteredStudents;
  bool get isLoading => _isLoading;

  UserProvider() {
    _loadData();
  }

  Future<void> _loadData() async {
    _isLoading = true;
    notifyListeners();

    // Simulate network delay for realism
    await Future.delayed(const Duration(seconds: 1));

    if (MockDataGenerator.students.isEmpty) {
      MockDataGenerator.initialize();
    }
    
    _allStudents = List.from(MockDataGenerator.students);
    _filteredStudents = List.from(_allStudents);
    
    // Mock Received Requests
    if (_allStudents.length >= 6) {
      _connectionStatuses[_allStudents[0].id] = 'Received';
      _connectionStatuses[_allStudents[1].id] = 'Received';
      _connectionStatuses[_allStudents[2].id] = 'Received';
      
      // Mock Connections
      _connectionStatuses[_allStudents[3].id] = 'Connected';
      _connectionStatuses[_allStudents[4].id] = 'Connected';
      _connectionStatuses[_allStudents[5].id] = 'Connected';
    }
    
    _isLoading = false;
    notifyListeners();
  }

  String getConnectionStatus(String userId) {
    return _connectionStatuses[userId] ?? 'None';
  }

  void sendConnectionRequest(String userId, String purpose) {
    _connectionStatuses[userId] = 'Requested';
    notifyListeners();
  }
  
  void updateConnectionStatus(String userId, String status) {
    _connectionStatuses[userId] = status;
    notifyListeners();
  }

  void searchStudents(String query) {
    if (query.isEmpty) {
      _filteredStudents = List.from(_allStudents);
    } else {
      _filteredStudents = _allStudents.where((s) => 
        s.name.toLowerCase().contains(query.toLowerCase()) || 
        s.department.toLowerCase().contains(query.toLowerCase()) ||
        s.interests.any((i) => i.toLowerCase().contains(query.toLowerCase()))
      ).toList();
    }
    notifyListeners();
  }

  void filterByDepartment(String dept) {
    if (dept == 'Any') {
      _filteredStudents = List.from(_allStudents);
    } else {
      _filteredStudents = _allStudents.where((s) => s.department == dept).toList();
    }
    notifyListeners();
  }
}
