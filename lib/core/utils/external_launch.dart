import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser / associated app.
///
/// The single code path behind every "we can't render this in-app, hand it
/// off" fallback — [WebPageScreen]'s external-open button, the documents tab
/// skipping the in-app viewer for PDFs/Office files, the QR scanner, and
/// order-chat attachments all route through this instead of each calling
/// `url_launcher` themselves. Returns `false` (rather than throwing) when the
/// URL doesn't parse or nothing on the device can open it, so callers can
/// show their own feedback.
Future<bool> launchExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
