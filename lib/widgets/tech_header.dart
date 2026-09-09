import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/router.dart';
import '../state/providers.dart';
import '../theme/fe_colors.dart';
import '../theme/theme_extensions.dart';
import 'app_text.dart';
import 'fe_header.dart';

/// The shell-level header: [FeHeader] plus the calendar/notification-bell/
/// logout affordances every top-level screen shares.
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
    final unseen = ref.watch(unseenNotificationCountProvider).valueOrNull ?? 0;

    return FeHeader(
      title: title,
      showBack: showBack,
      actions: [
        if (showCalendar && location != Routes.calendar)
          _HeaderButton(
            icon: LucideIcons.calendarDays,
            tooltip: 'common.calendar'.getString(context),
            onTap: () => context.push(Routes.calendar),
          ),
        if (showNotifications)
          _HeaderButton(
            icon: LucideIcons.bell,
            tooltip: 'common.notifications'.getString(context),
            badge: unseen,
            onTap: () => context.push(Routes.notifications),
          ),
        if (onLogout != null)
          _HeaderButton(
            icon: LucideIcons.logOut,
            tooltip: 'common.log_out'.getString(context),
            onTap: onLogout!,
          ),
        const SizedBox(width: 4),
      ],
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
      icon: Icon(icon, size: 20),
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
              color: FeColors.danger,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: FeColors.panel),
            ),
            child: AppText(
              badge > 9 ? '9+' : '$badge',
              align: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                height: 1.2,
                color: Colors.white,
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
      backgroundColor: FeColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radii.sheet),
      ),
      title: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: FeColors.dangerSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.logOut, size: 20, color: FeColors.danger),
          ),
          const SizedBox(width: 12),
          AppText('common.sign_out_title'.getString(context)),
        ],
      ),
      content: AppText('common.sign_out_message'.getString(context)),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: AppText('common.cancel'.getString(context)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: FeColors.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: AppText('common.log_out'.getString(context)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
