import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/models/user_model.dart';
import '../../profile/screens/student_profile_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userProvider = context.watch<UserProvider>();

    final receivedRequests = userProvider.students
        .where((s) => userProvider.getConnectionStatus(s.id) == 'Received')
        .toList();
        
    final myConnections = userProvider.students
        .where((s) => userProvider.getConnectionStatus(s.id) == 'Connected')
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Connections', style: theme.textTheme.displayMedium?.copyWith(fontSize: 24)),
          bottom: TabBar(
            labelColor: theme.primaryColor,
            unselectedLabelColor: theme.textTheme.bodyMedium?.color,
            indicatorColor: theme.primaryColor,
            tabs: [
              Tab(text: 'Received (${receivedRequests.length})'),
              Tab(text: 'My Connections (${myConnections.length})'),
            ],
          ),
        ),
        body: userProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildReceivedRequests(receivedRequests, theme, isDark, userProvider, context),
                  _buildMyConnections(myConnections, theme, isDark, context),
                ],
              ),
      ),
    );
  }

  Widget _buildReceivedRequests(List<User> requests, ThemeData theme, bool isDark, UserProvider provider, BuildContext context) {
    if (requests.isEmpty) {
      return Center(child: Text('No pending requests.', style: theme.textTheme.bodyLarge));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final user = requests[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentProfileScreen(user: user)));
                },
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundImage: NetworkImage(user.profilePhotoUrl),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name, style: theme.textTheme.titleMedium),
                          Text('${user.year} • ${user.course}', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text('2h ago', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.bookOpen, size: 16, color: theme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Wants to connect as a Study Partner',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        provider.updateConnectionStatus(user.id, 'None');
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: theme.dividerColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        provider.updateConnectionStatus(user.id, 'Connected');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Connected with ${user.name}!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMyConnections(List<User> connections, ThemeData theme, bool isDark, BuildContext context) {
    if (connections.isEmpty) {
      return Center(child: Text('No connections yet.', style: theme.textTheme.bodyLarge));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: connections.length,
      itemBuilder: (context, index) {
        final user = connections[index];
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
          subtitle: Text('${user.department}'),
          trailing: IconButton(
            icon: const Icon(LucideIcons.messageCircle),
            onPressed: () {
              // Create or navigate to chat
            },
            color: theme.primaryColor,
          ),
        );
      },
    );
  }
}
