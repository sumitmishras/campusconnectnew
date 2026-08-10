import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/providers/chat_provider.dart';
import '../../core/providers/user_provider.dart';
import '../campus_hub/screens/campus_hub_screen.dart';
import '../chat/screens/chat_list_screen.dart';
import '../connection/screens/connections_screen.dart';
import '../discover/screens/discover_screen.dart';
import '../profile/screens/my_profile_screen.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;

  const MainNavigation({super.key, this.initialIndex = 0});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  late int _currentIndex = widget.initialIndex;

  static const _screens = [
    DiscoverScreen(),
    CampusHubScreen(),
    ConnectionsScreen(),
    ChatListScreen(),
    MyProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pendingRequests = context.watch<UserProvider>().receivedRequests.length;
    final unreadChats = context.watch<ChatProvider>().totalUnread;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, LucideIcons.compass, 'Discover', theme),
                _buildNavItem(1, LucideIcons.layoutGrid, 'Hub', theme),
                _buildNavItem(2, LucideIcons.users, 'Connect', theme,
                    badge: pendingRequests),
                _buildNavItem(3, LucideIcons.messageCircle, 'Chats', theme,
                    badge: unreadChats),
                _buildNavItem(4, LucideIcons.user, 'Profile', theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, ThemeData theme,
      {int badge = 0}) {
    final isSelected = _currentIndex == index;
    final color =
        isSelected ? theme.primaryColor : theme.textTheme.bodySmall?.color;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentIndex = index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.primaryColor.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (badge > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: theme.scaffoldBackgroundColor, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (isSelected) ...[
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
