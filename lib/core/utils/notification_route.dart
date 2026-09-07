import '../../app/router.dart';
import '../../domain/app_notification.dart';

/// Where tapping a notification takes a technician. A port of the web's
/// `getNotificationRoute.ts`, Technician branch only — this app has no other
/// role to serve.
///
/// Returns null when there is nowhere useful to go, and the caller should leave
/// the technician on the notifications list rather than pushing a dead route.
String? routeForNotification(AppNotification notification) {
  final link = notification.link?.trim();
  if (link != null && link.isNotEmpty) {
    final route = _appRouteForWebLink(link);
    if (route != null) return route;
    // A link pointing outside the technician portal — another role's page, or
    // an absolute URL. There is no screen here that can show it.
    return null;
  }

  final entityId = notification.entityId?.trim();
  final entityType = notification.entityType?.trim();
  if (entityId == null || entityId.isEmpty) return null;
  if (entityType == null || entityType.isEmpty) return null;

  // AI conversations resume in the Flow Agent workspace, which this app does
  // not have.
  if (entityType == 'conversation') return null;

  // The invite inbox, not the task page. `assignmentInviteService.ts` uses this
  // exact title and only this title for invites, and the detail screen fires a
  // dozen calls just to reach the accept/decline panel at the top of it.
  if (notification.title == 'New assignment invite') return Routes.invites;

  final slug = _slugForEntityType(entityType);
  return slug == null ? null : Routes.orderDetail(slug, entityId);
}

/// The four entity names the server stamps on a notification, mapped to this
/// app's route segments. Spelled out rather than derived: the server's names
/// are PascalCase and the routes are not.
String? _slugForEntityType(String entityType) => switch (entityType) {
      'WorkOrder' => 'work-order',
      'PreventiveMaintenance' => 'preventive',
      'ReactiveMaintenance' => 'reactive',
      'AnnualMaintenance' => 'annual',
      _ => null,
    };

/// The server sends web paths. This app's routes are the same paths without the
/// `/technician` prefix, so a technician link maps across directly — anything
/// else belongs to a different portal.
String? _appRouteForWebLink(String link) {
  const prefix = '/technician';
  if (!link.startsWith(prefix)) return null;
  final route = link.substring(prefix.length);
  if (route.isEmpty || route == '/') return Routes.dashboard;
  return route.startsWith('/') ? route : '/$route';
}
