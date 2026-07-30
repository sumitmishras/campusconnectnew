import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/user_provider.dart';

class StudentProfileScreen extends StatelessWidget {
  final User user;
  const StudentProfileScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
            onPressed: () {
              // Show options (Block, Report, etc.)
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile Header / Cover
            Container(
              height: 350,
              decoration: BoxDecoration(
                color: theme.primaryColor,
                image: DecorationImage(
                  image: NetworkImage(user.profilePhotoUrl),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.3), BlendMode.darken),
                ),
              ),
            ),
            
            // Profile Info Section
            Transform.translate(
              offset: const Offset(0, -30),
              child: Container(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          user.name,
                          style: theme.textTheme.displayMedium,
                        ),
                        if (user.isVerified)
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.primaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(LucideIcons.checkCircle2, color: theme.primaryColor, size: 24),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(LucideIcons.graduationCap, size: 16, color: theme.textTheme.bodySmall?.color),
                        const SizedBox(width: 8),
                        Text(
                          '${user.course} • ${user.year}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Action Buttons
                    Consumer<UserProvider>(
                      builder: (context, userProvider, child) {
                        final connectionStatus = userProvider.getConnectionStatus(user.id);
                        final isRequested = connectionStatus == 'Requested';
                        final isConnected = connectionStatus == 'Connected';

                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: isRequested || isConnected
                                    ? null // Disable if already requested/connected
                                    : () => _showConnectionRequestModal(context, theme, userProvider),
                                icon: Icon(
                                  isConnected ? LucideIcons.userCheck : (isRequested ? LucideIcons.clock : LucideIcons.userPlus),
                                ),
                                label: Text(
                                  isConnected ? 'Connected' : (isRequested ? 'Requested' : 'Connect'),
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  backgroundColor: isRequested || isConnected ? theme.disabledColor : theme.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.dividerColor),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: IconButton(
                                icon: const Icon(LucideIcons.bookmark),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        );
                      }
                    ),
                    const SizedBox(height: 32),
                    
                    // About
                    Text('About', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      user.bio,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    
                    // Interests
                    if (user.interests.isNotEmpty) ...[
                      Text('Interests', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.interests.map((i) => _buildChip(i, theme)).toList(),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    // Looking For
                    if (user.lookingFor.isNotEmpty) ...[
                      Text('Looking For', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: user.lookingFor.map((l) => _buildPurposeChip(l, LucideIcons.checkCircle, theme)).toList(),
                      ),
                      const SizedBox(height: 48),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPurposeChip(String label, IconData icon, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.primaryColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: theme.primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionRequestModal(BuildContext context, ThemeData theme, UserProvider userProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Send Connection Request', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Choose a purpose for your connection request.', 
                style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _buildSelectablePurpose('Friendship', LucideIcons.users, theme, context, userProvider),
                  _buildSelectablePurpose('Study Partner', LucideIcons.bookOpen, theme, context, userProvider),
                  _buildSelectablePurpose('Networking', LucideIcons.briefcase, theme, context, userProvider),
                  _buildSelectablePurpose('Coffee Chat', LucideIcons.coffee, theme, context, userProvider),
                  _buildSelectablePurpose('Project Partner', LucideIcons.code, theme, context, userProvider),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectablePurpose(String label, IconData icon, ThemeData theme, BuildContext context, UserProvider userProvider) {
    return GestureDetector(
      onTap: () {
        userProvider.sendConnectionRequest(user.id, label);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection request sent for $label!'),
            backgroundColor: theme.primaryColor,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: theme.textTheme.bodyMedium?.color),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
