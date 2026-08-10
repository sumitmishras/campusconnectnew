import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Circular avatar that falls back to an initial when the network image
/// cannot be loaded (handy when the demo runs offline).
class UserAvatar extends StatelessWidget {
  final String imageUrl;
  final String name;
  final double radius;
  final bool showOnlineDot;
  final bool isOnline;

  const UserAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 24,
    this.showOnlineDot = false,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
      foregroundImage: imageUrl.isEmpty ? null : NetworkImage(imageUrl),
      onForegroundImageError: imageUrl.isEmpty ? null : (_, _) {},
      child: Text(
        initial,
        style: TextStyle(
          color: theme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );

    if (!showOnlineDot || !isOnline) return avatar;

    return Stack(
      children: [
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: radius * 0.5,
            height: radius * 0.5,
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Consistent card container used across the hub, events and lists.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 16),
    this.onTap,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = LucideIcons.inbox,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: theme.primaryColor),
            ),
            const SizedBox(height: 20),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.textTheme.bodySmall?.color),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small pill used for interests, tech stacks and categories.
class TagChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool filled;

  const TagChip({super.key, required this.label, this.icon, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? theme.primaryColor.withValues(alpha: 0.1) : null,
        border: filled
            ? null
            : Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? theme.primaryColor : null),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled ? theme.primaryColor : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grab handle shown at the top of every bottom sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).dividerColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// One-liner for the confirmation toasts used all over the app.
void showAppSnackBar(BuildContext context, String message, {IconData? icon}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: theme.colorScheme.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            Icon(icon ?? LucideIcons.checkCircle2,
                size: 18, color: theme.colorScheme.onInverseSurface),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onInverseSurface),
              ),
            ),
          ],
        ),
      ),
    );
}

/// Yes/no dialog used for destructive actions (block, logout, delete).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: isDestructive
              ? ElevatedButton.styleFrom(backgroundColor: Colors.red)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
