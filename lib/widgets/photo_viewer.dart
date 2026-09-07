import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_text.dart';
import 'fe_header.dart';

/// Full-screen photo viewer. Photos taken on a job are evidence — a thumbnail
/// is not enough to check what was captured, so they open pannable and zoomable.
Future<void> showPhotoViewer(
  BuildContext context, {
  required List<String> urls,
  required String initial,
}) {
  // A queued photo has no URL yet and nothing to show.
  final viewable =
      urls.where((url) => !url.startsWith('__pending_photo_')).toList();
  if (viewable.isEmpty) return Future.value();

  final start = viewable.indexOf(initial);
  return Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _PhotoViewer(
        urls: viewable,
        initialIndex: start < 0 ? 0 : start,
      ),
    ),
  );
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: FeHeader(
          variant: FeHeaderVariant.immersive,
          leading: IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          titleWidget: widget.urls.length == 1
              ? const SizedBox.shrink()
              : AppText(
                  '${_index + 1} of ${widget.urls.length}',
                  style: const TextStyle(fontSize: 14),
                ),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (index) => setState(() => _index = index),
          itemBuilder: (context, index) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.network(
                widget.urls[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                errorBuilder: (context, _, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.imageOff,
                        size: 40,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        'This photo could not be loaded.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
