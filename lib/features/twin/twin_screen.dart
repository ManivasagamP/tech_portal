import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/env.dart';
import '../../core/storage/session_store.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// The 3D asset view, shown by loading the portal's own twin page.
///
/// The viewer is xeokit rendering an XKT model in WebGL — thousands of lines
/// of loader, mapping store and camera work that exist and are maintained on
/// the web. Reimplementing that natively would buy nothing a technician can
/// see, so this screen hosts the real page instead.
///
/// The page expects a signed-in browser: it reads its bearer token out of
/// `localStorage`, which is empty in a fresh webview. So the token is written
/// into that origin first, and only then is the twin loaded.
class TwinScreen extends ConsumerStatefulWidget {
  const TwinScreen({super.key, required this.assetId, this.assetName});

  final String assetId;
  final String? assetName;

  @override
  ConsumerState<TwinScreen> createState() => _TwinScreenState();
}

class _TwinScreenState extends ConsumerState<TwinScreen> {
  WebViewController? _controller;
  var _loading = true;

  /// How many times the screen has tried to reach the twin. The bootstrap page
  /// is the portal's own login screen, which redirects itself to the dashboard
  /// the moment it sees the token appear — and that client-side navigation can
  /// land after our own request for the twin. So arriving anywhere other than
  /// the twin is treated as "seed again and re-ask", with a cap so a page that
  /// genuinely refuses to load cannot spin forever.
  var _attempts = 0;
  static const _maxAttempts = 3;
  String? _error;

  String get _twinUrl {
    final query = widget.assetName == null
        ? ''
        : '?name=${Uri.encodeComponent(widget.assetName!)}';
    return '${Env.webBaseUrl}/technician/twin/${widget.assetId}$query';
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final token = await ref.read(secureStoreProvider).readToken();
    final session = ref.read(authControllerProvider).session;

    if (!mounted) return;
    if (token == null || token.isEmpty || session == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in again to open the 3D view.';
      });
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.slate950)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) async {
            if (!url.startsWith(_twinUrl.split('?').first)) {
              if (_attempts >= _maxAttempts) {
                if (mounted) {
                  setState(() {
                    _loading = false;
                    _error = 'The 3D view kept redirecting to another page.';
                  });
                }
                return;
              }
              _attempts++;
              // Same origin as the twin, so what is written here is what the
              // twin page reads. Re-seeding is harmless — it writes the same
              // values — and it covers the case where the redirect landed on a
              // page that cleared them.
              await _seedSession(token, session);
              await _controller?.loadRequest(Uri.parse(_twinUrl));
              return;
            }
            // Strip the portal's own chrome so only the viewer shows: its
            // header (this screen already has one), the mobile bottom nav, and
            // the floating AI bubble. Injected as a stylesheet rather than
            // inline styles because React re-renders the layout and would
            // otherwise put them straight back.
            await _controller?.runJavaScript('''
              (function () {
                if (document.getElementById('fe-native-chrome')) return;
                var s = document.createElement('style');
                s.id = 'fe-native-chrome';
                s.textContent =
                  'header,nav{display:none!important}' +
                  '[class*="z-[100]"]{display:none!important}' +
                  '[class~="pb-16"]{padding-bottom:0!important}';
                document.head.appendChild(s);
              })();
            ''');
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!error.isForMainFrame!) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      );

    setState(() => _controller = controller);
    // A cheap same-origin page to get a storage context; the twin replaces it
    // as soon as the token is in place.
    await controller.loadRequest(Uri.parse('${Env.webBaseUrl}/login'));
  }

  /// Writes exactly the keys the web login writes, because the twin's data
  /// calls and the pages it links to read them by name.
  Future<void> _seedSession(String token, Session session) async {
    final entries = <String, String>{
      'token': token,
      'isAuthenticated': 'true',
      'role': 'Technician',
      'userId': session.userId,
      'userName': session.name,
      if (session.username != null) 'username': session.username!,
      if (session.technicianId != null) 'technicianId': session.technicianId!,
    };

    final script = StringBuffer();
    for (final entry in entries.entries) {
      script.write(
        'localStorage.setItem(${jsonEncode(entry.key)}, '
        '${jsonEncode(entry.value)});',
      );
    }
    await _controller?.runJavaScript(script.toString());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;

    return Scaffold(
      backgroundColor: AppColors.slate950,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: FeLightAppBar.foreground,
        titleTextStyle: FeLightAppBar.title(context),
        systemOverlayStyle: FeLightAppBar.overlay,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.assetName ?? 'Asset Location',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '3D VIEW',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.gray400,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: _error != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: TechEmptyState(
                icon: LucideIcons.box,
                title: 'The 3D view would not open',
                subtitle: _error,
              ),
            )
          : Stack(
              children: [
                if (controller != null) WebViewWidget(controller: controller),
                if (_loading)
                  const ColoredBox(
                    color: AppColors.slate950,
                    child: SizedBox.expand(
                      child: TechSpinner(color: AppColors.white),
                    ),
                  ),
              ],
            ),
    );
  }
}
