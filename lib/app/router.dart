import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/calendar/calendar_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/invites/invites_screen.dart';
import '../features/login/login_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/order_detail/order_detail_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/overview/overview_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/shell/technician_shell.dart';
import '../features/twin/twin_screen.dart';
import '../features/web/web_page_screen.dart';
import '../state/auth_controller.dart';

/// Paths mirror the web routes so the notification deep-link table maps 1:1.
abstract final class Routes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const overview = '/overview';
  static const orders = '/orders';
  static const invites = '/invites';
  static const profile = '/profile';
  static const calendar = '/calendar';
  static const notifications = '/notifications';
  static const scan = '/scan';

  static String orderDetail(String type, String id) => '/orders/$type/$id';
  static String twin(String assetId) => '/twin/$assetId';

  /// The built-in browser. The address is a query parameter rather than a path
  /// segment so slashes in it survive.
  static String webPage(String url, {String? title}) {
    final query = {
      'url': url,
      'title': ?title,
    };
    return Uri(path: '/web', queryParameters: query).toString();
  }

  /// The five routes that live inside the bottom-bar shell. Each one owns a
  /// branch navigator, and pushing one onto the root navigator reserves that
  /// branch's key a second time — which throws
  /// `!keyReservation.contains(key)` and takes the app down. They are switched
  /// to with `go`, never pushed.
  static const shellBranches = <String>{
    dashboard,
    overview,
    orders,
    invites,
    profile,
  };

  static bool isShellBranch(String route) => shellBranches.contains(route);
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (previous, next) {
    if (previous?.isAuthenticated != next.isAuthenticated) refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) {
      final authed = ref.read(authControllerProvider).isAuthenticated;
      final atLogin = state.matchedLocation == Routes.login;
      if (!authed) return atLogin ? null : Routes.login;
      if (atLogin) return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            TechnicianShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.overview,
              builder: (context, state) => const OverviewScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.orders,
              builder: (context, state) => const OrdersScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.invites,
              builder: (context, state) => const InvitesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/orders/:type/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => OrderDetailScreen(
          orderType: state.pathParameters['type'] ?? 'work-order',
          orderId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: Routes.calendar,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const CalendarScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.scan,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/web',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => WebPageScreen(
          url: state.uri.queryParameters['url'] ?? '',
          title: state.uri.queryParameters['title'],
        ),
      ),
      GoRoute(
        path: '/twin/:assetId',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => TwinScreen(
          assetId: state.pathParameters['assetId'] ?? '',
          assetName: state.uri.queryParameters['name'],
        ),
      ),
    ],
  );
});
