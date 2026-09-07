import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/router.dart';
import '../state/providers.dart';
import '../theme/app_colors.dart';
import '../theme/theme_extensions.dart';

/// The portal's one header: dark chrome bar, title left, actions right.
class TechHeader extends ConsumerWidget implements PreferredSizeWidget {
  const TechHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.showCalendar = true,
    this.showNotifications = true,
    this.onLogout,
  });

  final String title;
  final bool showBack;
  final bool showCalendar;
  final bool showNotifications;

  /// Only the dashboard and profile offer logout.
  final VoidCallback? onLogout;

  @override
  Size get preferredSize => const Size.fromHeight(53);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final unseen =
        ref.watch(unseenNotificationCountProvider).valueOrNull ?? 0;

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.ink,
        border: Border(bottom: BorderSide(color: AppColors.inkBorder)),
      ),
      child: Row(
        children: [
          if (showBack)
            _HeaderButton(
              icon: LucideIcons.arrowLeft,
              tooltip: 'Back',
              onTap: () => context.pop(),
            ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
            ),
          ),
          if (showCalendar && location != Routes.calendar)
            _HeaderButton(
              icon: LucideIcons.calendarDays,
              tooltip: 'Calendar',
              onTap: () => context.push(Routes.calendar),
            ),
          if (showNotifications)
            _HeaderButton(
              icon: LucideIcons.bell,
              tooltip: 'Notifications',
              badge: unseen,
              onTap: () => context.push(Routes.notifications),
            ),
          if (onLogout != null)
            _HeaderButton(
              icon: LucideIcons.logOut,
              tooltip: 'Log Out',
              onTap: onLogout!,
            ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Unseen count. Anything past nine shows as "9+", as the web does.
  final int badge;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 20, color: AppColors.white),
    );

    if (badge <= 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16),
            decoration: BoxDecoration(
              color: AppColors.red600,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.ink),
            ),
            child: Text(
              badge > 9 ? '9+' : '$badge',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    height: 1.2,
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Confirmation the dashboard and profile show before clearing the session.
Future<bool> showLogoutDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radii.sheet),
      ),
      title: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.red50,
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.logOut,
                size: 20, color: AppColors.red600),
          ),
          const SizedBox(width: 12),
          const Text('Sign Out'),
        ],
      ),
      content: const Text(
        'Are you sure you want to log out of the technician portal? '
        'You will need to sign in again to access your tasks.',
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red600,
            foregroundColor: AppColors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Log Out'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
