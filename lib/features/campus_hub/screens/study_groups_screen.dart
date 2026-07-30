import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/user_provider.dart';
import '../../profile/screens/student_profile_screen.dart';

class StudyGroupsScreen extends StatelessWidget {
  const StudyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    
    // For demo: anyone looking for "Study Partner"
    final studyPartners = userProvider.students.where((s) => s.lookingFor.contains('Study Partner')).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Study Groups', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
      ),
      body: userProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: studyPartners.length,
              itemBuilder: (context, index) {
                final user = studyPartners[index];
                return ListTile(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)));
                  },
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundImage: NetworkImage(user.profilePhotoUrl),
                  ),
                  title: Text(user.name, style: theme.textTheme.titleMedium),
                  subtitle: Text('${user.course} • ${user.year}'),
                  trailing: ElevatedButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)));
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Connect'),
                  ),
                );
              },
            ),
    );
  }
}
