import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/external_launch.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/fe_header.dart';

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
  /// How long we let the page try before assuming it's a dead end (a content
  /// type — PDF, an office doc, anything else — that a bare [WebViewWidget]
  /// has no renderer for on Android, so `onPageFinished` either never fires
  /// or fires without ever painting anything). Belt-and-braces alongside
  /// documents_tab.dart routing known-bad types (PDF/DOC/XLS/…) straight to
  /// the external launcher before ever pushing this screen — this timeout is
  /// what catches whatever type that check didn't anticipate.
  static const _loadTimeout = Duration(seconds: 9);

  late final WebViewController _controller;
  Timer? _timeoutTimer;
  var _loading = true;
  var _timedOut = false;
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
            _timeoutTimer?.cancel();
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Sub-resources fail all the time (a missing icon, a blocked
            // font); only a failure of the page itself is worth reporting.
            if (!error.isForMainFrame!) return;
            _timeoutTimer?.cancel();
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
    _startTimeoutTimer();
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_loadTimeout, () {
      // Still spinning after the timeout with no success and no reported
      // error — the page load is simply never going to resolve. Offer the
      // escape hatch instead of leaving the technician staring at a spinner.
      if (mounted && _loading && _error == null) {
        setState(() => _timedOut = true);
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _openExternally() => launchExternalUrl(widget.url);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: FeColors.panel,
        appBar: FeHeader(
          title: widget.title ?? 'web.record_title'.getString(context),
          actions: [
            IconButton(
              tooltip: 'web.reload_tooltip'.getString(context),
              icon: const Icon(LucideIcons.rotateCw, size: 18),
              onPressed: () {
                setState(() => _timedOut = false);
                _startTimeoutTimer();
                _controller.reload();
              },
            ),
            IconButton(
              tooltip: 'web.open_in_browser_tooltip'.getString(context),
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
                  title: 'web.load_error_title'.getString(context),
                  subtitle: _error,
                ),
              )
            : Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_loading && !_timedOut) const TechSpinner(),
                  if (_timedOut && _loading)
                    Container(
                      color: FeColors.panel,
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.fileWarning,
                              size: 40,
                              color: FeColors.ink2,
                            ),
                            const SizedBox(height: 12),
                            AppText.bodyMedium(
                              'web.load_timeout_title'.getString(context),
                              weight: FontWeight.w600,
                              align: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            AppText.caption(
                              'web.load_timeout_subtitle'.getString(context),
                              color: FeColors.ink2,
                              align: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _openExternally,
                              icon: const Icon(
                                LucideIcons.externalLink,
                                size: 16,
                              ),
                              label: Text(
                                'web.open_in_browser_button'.getString(
                                  context,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      );
}
