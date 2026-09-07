import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';

/// The built-in browser for our own `/public/*` pages — asset and material
/// sheets a QR sticker points at, which have no native screen in this portal.
///
/// Deliberately narrow: no address bar, no history, and it only ever opens a
/// URL the app itself built. Anything scanned from outside goes to the
/// system browser instead, so a hostile page never renders next to the
/// technician's session.
class WebPageScreen extends StatefulWidget {
  const WebPageScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _controller;
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Sub-resources fail all the time (a missing icon, a blocked
            // font); only a failure of the page itself is worth reporting.
            if (!error.isForMainFrame!) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _error = error.description;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          foregroundColor: FeLightAppBar.foreground,
          titleTextStyle: FeLightAppBar.title(context),
          systemOverlayStyle: FeLightAppBar.overlay,
          title: Text(widget.title ?? 'Record'),
          actions: [
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(LucideIcons.rotateCw, size: 18),
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              tooltip: 'Open in browser',
              icon: const Icon(LucideIcons.externalLink, size: 18),
              onPressed: _openExternally,
            ),
          ],
        ),
        body: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: TechEmptyState(
                  icon: LucideIcons.wifiOff,
                  title: 'This page would not load',
                  subtitle: _error,
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading) const TechSpinner(),
                ],
              ),
      );
}
