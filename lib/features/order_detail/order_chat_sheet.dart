import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' show Amplitude;
import 'package:url_launcher/url_launcher.dart';

import '../../core/capture/capture_services.dart';
import '../../core/utils/dates.dart';
import '../../domain/chat_message.dart';
import '../../domain/maintenance_record.dart';
import '../../state/chat_controller.dart';
import '../../state/checklist_controller.dart' show photoCaptureProvider;
import '../../state/order_detail_controller.dart';
import '../../theme/fe_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/app_text.dart';
import '../../widgets/tech_popup.dart';
import '../../widgets/voice_note_player.dart';
import '../../widgets/voice_waveform.dart';

/// The per-order assistant, opened from the button on the detail screen.
///
/// Scoped to one job on purpose: it answers about this checklist, this asset
/// and this order, and has none of the facility agent's asset-creation or
/// reporting powers.
Future<void> showOrderChatSheet(
  BuildContext context, {
  required OrderKey orderKey,
  String? assetName,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => OrderChatSheet(
        orderKey: orderKey,
        assetName: assetName,
      ),
    );

class OrderChatSheet extends ConsumerStatefulWidget {
  const OrderChatSheet({super.key, required this.orderKey, this.assetName});

  final OrderKey orderKey;
  final String? assetName;

  @override
  ConsumerState<OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends ConsumerState<OrderChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<CapturedPhoto> _attachments = [];

  // Voice attach — one clip per message, mirroring the `audio` field's
  // singular shape server-side. Owns its own `VoiceCapture` instance rather
  // than sharing `record_voice_note.dart`'s, exactly the way that widget owns
  // its own instance too: recording is a widget-scoped resource, not a
  // singleton.
  final _voice = VoiceCapture();
  bool _recording = false;
  Stream<Amplitude>? _amplitudeStream;
  VoiceRecording? _voiceAttachment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider(widget.orderKey).notifier).open();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _voice.dispose();
    super.dispose();
  }

  String get _greeting {
    final subject = widget.orderKey.type == OrderType.workOrder
        ? 'order_detail.chat_subject_work_order'.getString(context)
        : context.formatString(
            'order_detail.chat_subject_maintenance'.getString(context),
            [widget.orderKey.type.slug],
          );
    final subjectWithAsset = widget.assetName == null
        ? subject
        : context.formatString(
            'order_detail.chat_subject_with_asset'.getString(context),
            [subject, widget.assetName!],
          );
    return context.formatString(
      'order_detail.chat_greeting'.getString(context),
      [subjectWithAsset],
    );
  }

  Future<void> _send() async {
    final text = _input.text;
    final images = _attachments.map((photo) => photo.dataUrl).toList();
    final audio = _voiceAttachment?.dataUrl;
    // A voice note or a photo is enough on its own — typing alongside it
    // defeats the point of speaking instead of typing. Only block when there
    // is truly nothing to send (matches `_Composer`'s `canSend`, which
    // already allows this).
    final hasContent =
        text.trim().isNotEmpty || images.isNotEmpty || audio != null;
    if (!hasContent || _recording) return;
    _input.clear();
    setState(() {
      _attachments.clear();
      _voiceAttachment = null;
    });
    _scrollToEnd();
    await ref
        .read(chatControllerProvider(widget.orderKey).notifier)
        .send(text, images: images, audio: audio);
    _scrollToEnd();
  }

  /// Fills the composer with a tapped suggestion chip's question rather than
  /// sending it straight away — the technician can still edit or add a photo
  /// before it goes out, same as anything else typed by hand. Purely a text
  /// fill on the controller [_send] already reads from; no new send path.
  void _fillSuggestion(String question) {
    _input.text = question;
    _input.selection = TextSelection.collapsed(offset: question.length);
  }

  Future<void> _pickImage({required bool fromGallery}) async {
    final capture = ref.read(photoCaptureProvider);
    final photo = fromGallery
        ? await capture.pickFromGallery()
        : await capture.takeJobPhoto();
    if (photo == null || !mounted) return;
    setState(() => _attachments.add(photo));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// Tapping the mic starts recording; tapping it again stops and holds the
  /// clip as a pending attachment (like `_attachments`, nothing is sent yet).
  /// Recording again before sending replaces it — same "one clip, latest
  /// wins" rule `record_voice_note.dart` uses for the checklist voice note.
  Future<void> _toggleVoiceRecording() async {
    if (_recording) {
      final recording = await _voice.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _amplitudeStream = null;
      });
      if (recording == null) {
        showTechPopup(
          context,
          message: 'order_detail.nothing_recorded'.getString(context),
          isError: true,
        );
        return;
      }
      setState(() => _voiceAttachment = recording);
      return;
    }

    try {
      final directory = await getTemporaryDirectory();
      await _voice.start(directory.path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _amplitudeStream = _voice.amplitudeStream();
      });
    } on CaptureFailure catch (e) {
      showTechPopup(context, message: e.message, isError: true);
    }
  }

  void _removeVoiceAttachment() {
    setState(() => _voiceAttachment = null);
  }

  /// A small action sheet offering the same two capture sources as
  /// checklist_item_sheet.dart's `_Attachments`, reusing its translated
  /// strings rather than duplicating "gallery"/"camera" copy.
  Future<void> _showAttachOptions() async {
    final fromGallery = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1C1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.radii.sheet),
        ),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.image, color: Colors.white),
              title: AppText(
                'order_detail.choose_from_gallery'.getString(sheetContext),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            ListTile(
              leading: const Icon(LucideIcons.camera, color: Colors.white),
              title: AppText(
                'order_detail.take_a_photo'.getString(sheetContext),
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.of(sheetContext).pop(false),
            ),
          ],
        ),
      ),
    );
    if (fromGallery == null || !mounted) return;
    await _pickImage(fromGallery: fromGallery);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.orderKey));
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
        // Four fifths of the screen, but never more than the space left above
        // the keyboard, less a strip for the status bar — otherwise the
        // panel's header slides under the clock the moment anyone types. The
        // strip is a constant because a sheet's own MediaQuery reports zero
        // for both `padding.top` and `viewPadding.top`.
        height: math.min(
          media.size.height * 0.8,
          media.size.height - media.viewInsets.bottom - 48,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF16171A),
          // Same corner radius token every other bottom sheet in this app
          // uses (close_sheet.dart, checklist_item_sheet.dart's
          // VerificationSheet) — this sheet keeps its own dark surface, but
          // the corner shape stays consistent with the rest of the app's
          // sheet chrome rather than inventing a rounder one just for chat.
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.radii.sheet),
          ),
        ),
        child: Column(
          children: [
            _Header(assetName: widget.assetName),
            Expanded(
              child: state.loadingHistory && state.messages.isEmpty
                  ? const Center(
                      child: SizedBox(
                        height: 28,
                        width: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation(FeColors.ink2),
                        ),
                      ),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      children: [
                        if (state.messages.isEmpty)
                          _EmptyState(
                            greeting: _greeting,
                            onSuggestionTap: _fillSuggestion,
                          ),
                        for (final message in state.messages)
                          _Bubble(message: message),
                      ],
                    ),
            ),
            _Composer(
              controller: _input,
              sending: state.sending,
              onSend: _send,
              attachments: _attachments,
              onAttach: _showAttachOptions,
              onRemoveAttachment: _removeAttachment,
              recording: _recording,
              amplitudeStream: _amplitudeStream,
              onToggleRecording: _toggleVoiceRecording,
              voiceAttachment: _voiceAttachment,
              onRemoveVoiceAttachment: _removeVoiceAttachment,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.assetName});

  final String? assetName;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
        ),
        child: Row(
          children: [
            // Brand-tinted gradient rather than the flat translucent-white
            // tile this used to be — ties the header icon back to the same
            // accent blue that pulses behind the AppBar trigger button
            // (order_detail_screen.dart's `_ChatTriggerButton`), so the AI
            // branding reads as one thread from trigger to sheet.
            Container(
              height: 34,
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    FeColors.primaryLight.withValues(alpha: 0.55),
                    FeColors.primary.withValues(alpha: 0.35),
                  ],
                ),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: const Icon(LucideIcons.sparkles,
                  size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    'order_detail.chat_header_title'.getString(context),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    assetName ?? 'order_detail.chat_header_fallback'.getString(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FeColors.ink2,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 20, color: FeColors.ink2),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x14FFFFFF),
                shape: const CircleBorder(),
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
}

/// Shown once, in place of the first assistant bubble, before any message
/// exists — a proper empty state (icon + greeting + tap-to-ask suggestions)
/// rather than a lone bubble that happened to have nothing to reply to.
/// Tapping a chip only fills the composer via [onSuggestionTap]; nothing
/// here sends on its own, so it rides the same [OrderChatSheet._send] path
/// as anything typed by hand.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.greeting, required this.onSuggestionTap});

  final String greeting;
  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Container(
              height: 56,
              width: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    FeColors.primaryLight.withValues(alpha: 0.5),
                    FeColors.primary.withValues(alpha: 0.28),
                  ],
                ),
                border: Border.all(color: const Color(0x26FFFFFF)),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                size: 26,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: AppText(
                greeting,
                align: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 18),
            AppText(
              'order_detail.chat_suggestions_label'.getString(context).toUpperCase(),
              style: const TextStyle(
                color: FeColors.ink2,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _SuggestionChip(
                  icon: LucideIcons.listChecks,
                  label: 'order_detail.chat_suggestion_checklist'
                      .getString(context),
                  onTap: () => onSuggestionTap(
                    'order_detail.chat_suggestion_checklist_question'
                        .getString(context),
                  ),
                ),
                _SuggestionChip(
                  icon: LucideIcons.box,
                  label:
                      'order_detail.chat_suggestion_asset'.getString(context),
                  onTap: () => onSuggestionTap(
                    'order_detail.chat_suggestion_asset_question'
                        .getString(context),
                  ),
                ),
                _SuggestionChip(
                  icon: LucideIcons.circleHelp,
                  label: 'order_detail.chat_suggestion_status'
                      .getString(context),
                  onTap: () => onSuggestionTap(
                    'order_detail.chat_suggestion_status_question'
                        .getString(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

/// One tappable "ask this" pill in [_EmptyState]. Same soft-outline treatment
/// as the composer's own container (`_Composer`'s `Color(0xFF1C1E22)` fill +
/// faint white border), so these read as belonging to this sheet rather than
/// a generic chip style borrowed from elsewhere.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1C1E22),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: FeColors.primaryLight),
                const SizedBox(width: 6),
                AppText(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromTechnician;
    // A slightly bigger radius than the old flat 16/4 — matches the size of
    // rounding the rest of the app uses for its cards (`context.radii.xl`)
    // — while keeping a small "tail" corner on the side pointing at the
    // sender, so the two message directions still read apart at a glance.
    final tailRadius = Radius.circular(context.radii.sm);
    final roundRadius = Radius.circular(context.radii.xl);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: mine ? FeColors.panel : const Color(0xFF2B2D31),
              borderRadius: BorderRadius.only(
                topLeft: mine ? roundRadius : tailRadius,
                topRight: mine ? tailRadius : roundRadius,
                bottomLeft: roundRadius,
                bottomRight: roundRadius,
              ),
              // Assistant bubbles sit on a background that is nearly the
              // same dark tone as the bubble itself — this faint edge is
              // what keeps them from reading as a smudge rather than a
              // distinct message. The technician's own (light) bubble
              // already has enough contrast against the dark sheet and
              // doesn't need one.
              border: mine
                  ? null
                  : Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: message.pending
                ? const _Thinking()
                // The technician's own text is shown exactly as typed. The
                // assistant answers in Markdown — headings, bold labels,
                // bullet lists — which read as literal `**Ticket ID:**` and
                // `####` if printed raw.
                : mine
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.images.isNotEmpty) ...[
                            _MessageImages(dataUrls: message.images),
                            if (message.audio != null ||
                                message.content.isNotEmpty)
                              const SizedBox(height: 8),
                          ],
                          if (message.audio != null) ...[
                            // Read-only here: this note already left the
                            // device, there is nothing left to delete it
                            // from locally. Given its own soft card rather
                            // than sitting bare on the bubble, matching how
                            // the pre-send voice preview
                            // (`_VoiceAttachmentPreview`) already presents
                            // an unplayed clip.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: FeColors.page,
                                borderRadius:
                                    BorderRadius.circular(context.radii.md),
                                border: Border.all(color: FeColors.line),
                              ),
                              child: VoiceNotePlayer(audioUrl: message.audio!),
                            ),
                            if (message.content.isNotEmpty)
                              const SizedBox(height: 8),
                          ],
                          if (message.content.isNotEmpty)
                            AppText(
                              message.content,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                        ],
                      )
                    : _AssistantMarkdown(content: message.content),
          ),
          if (!message.pending && message.sentAt != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AppText(
                formatHistoryTimestamp(message.sentAt!),
                style: const TextStyle(color: FeColors.ink2, fontSize: 10.5),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.content});

  final String content;

  static const _body = TextStyle(
    color: Colors.white,
    fontSize: 13,
    height: 1.5,
  );

  TextStyle _heading(double size) => _body.copyWith(
        fontSize: size,
        height: 1.3,
        fontWeight: FontWeight.w800,
      );

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: content,
        // Anything the assistant links to opens in the phone's browser, and
        // only ever over http(s) — the same guard the QR scanner applies, so a
        // model-authored `javascript:` or `file:` string cannot be launched.
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
            return;
          }
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        styleSheet: MarkdownStyleSheet(
          p: _body,
          h1: _heading(17),
          h2: _heading(16),
          h3: _heading(15),
          h4: _heading(14),
          h5: _heading(13),
          h6: _heading(13),
          strong: _body.copyWith(fontWeight: FontWeight.w700),
          em: _body.copyWith(fontStyle: FontStyle.italic),
          a: _body.copyWith(
            color: FeColors.info,
            decoration: TextDecoration.underline,
          ),
          listBullet: _body,
          blockquote: _body,
          code: _body.copyWith(
            fontSize: 12,
            backgroundColor: Colors.transparent,
          ),
          codeblockPadding: const EdgeInsets.all(10),
          codeblockDecoration: BoxDecoration(
            color: const Color(0xFF1C1E22),
            borderRadius: BorderRadius.circular(8),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
          blockquoteDecoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: Color(0x33FFFFFF), width: 3),
            ),
          ),
          horizontalRuleDecoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x33FFFFFF))),
          ),
          // Tighter than the package default: these bubbles are narrow and the
          // assistant writes several short sections per answer.
          blockSpacing: 8,
          h1Padding: const EdgeInsets.only(top: 4),
          h2Padding: const EdgeInsets.only(top: 4),
          h3Padding: const EdgeInsets.only(top: 4),
          h4Padding: const EdgeInsets.only(top: 4),
        ),
      );
}

/// The assistant-bubble "typing" state: three dots pulsing/bouncing in a
/// staggered wave, drawn inside the same bubble container `_Bubble` already
/// gives every assistant message (color, radius, padding unchanged) — this
/// only replaces the static "Thinking…" content that used to sit in there.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking>
    with SingleTickerProviderStateMixin {
  // One full cycle for all three dots; each dot leads the next by a third of
  // it, the same "staggered wave" idea `StaggeredEntrance` uses for list
  // items (widgets/motion.dart), just looped instead of played once.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 12,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i != 0) const SizedBox(width: 5),
              _ThinkingDot(controller: _controller, delay: i / 3),
            ],
          ],
        ),
      );
}

class _ThinkingDot extends StatelessWidget {
  const _ThinkingDot({required this.controller, required this.delay});

  final Animation<double> controller;
  final double delay;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          // Triangle wave 0 -> 1 -> 0 over the cycle, offset by `delay` so
          // the three dots bounce in sequence rather than in lockstep.
          final t = (controller.value + delay) % 1.0;
          final bounce = math.sin(t * math.pi);
          return Transform.translate(
            offset: Offset(0, -4 * bounce),
            child: Opacity(opacity: 0.4 + 0.6 * bounce, child: child),
          );
        },
        child: const _Dot(),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: FeColors.ink2,
          shape: BoxShape.circle,
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.attachments,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.recording,
    required this.amplitudeStream,
    required this.onToggleRecording,
    required this.voiceAttachment,
    required this.onRemoveVoiceAttachment,
    this.style,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final List<CapturedPhoto> attachments;
  final VoidCallback onAttach;
  final ValueChanged<int> onRemoveAttachment;
  final bool recording;
  final Stream<Amplitude>? amplitudeStream;
  final VoidCallback onToggleRecording;
  final VoiceRecording? voiceAttachment;
  final VoidCallback onRemoveVoiceAttachment;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: attachments.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) => _AttachmentPreview(
                      photo: attachments[index],
                      onRemove: () => onRemoveAttachment(index),
                    ),
                  ),
                ),
              ),
            if (voiceAttachment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _VoiceAttachmentPreview(
                  recording: voiceAttachment!,
                  onRemove: onRemoveVoiceAttachment,
                ),
              ),
            if (recording)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.mic,
                      size: 14,
                      color: FeColors.danger,
                    ),
                    const SizedBox(width: 8),
                    AppText(
                      'order_detail.stop_recording'.getString(context),
                      style: const TextStyle(
                        color: FeColors.danger,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (amplitudeStream != null)
                      Expanded(
                        child: VoiceWaveform(
                          amplitudeStream: amplitudeStream!,
                          color: FeColors.danger,
                          height: 22,
                        ),
                      ),
                  ],
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1E22),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Both leading icons pin to the same 32x32 box the send
                  // button already uses at the other end of this row
                  // (below), instead of Material's default 48x48 tap target.
                  // Left untouched, two full-size default IconButtons sitting
                  // directly next to each other (no SizedBox between them)
                  // read as a much bigger gap than the icon-to-textfield or
                  // icon-to-send-button spacing, since those neighbors are
                  // smaller/tighter — this keeps every gap in the row close
                  // to the same visual size.
                  IconButton(
                    onPressed: sending || recording ? null : onAttach,
                    tooltip: 'order_detail.chat_attach_photo'.getString(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: const Icon(
                      LucideIcons.paperclip,
                      size: 18,
                      color: FeColors.ink2,
                    ),
                  ),
                  IconButton(
                    onPressed: sending ? null : onToggleRecording,
                    tooltip: recording
                        ? 'order_detail.stop_recording'.getString(context)
                        : 'order_detail.record_voice_note_tooltip'
                            .getString(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    // Same filled-danger-while-recording treatment
                    // `record_voice_note.dart` uses for its own mic button
                    // (dangerSoft fill + danger icon) — kept consistent here
                    // rather than inventing a new recording indicator.
                    style: IconButton.styleFrom(
                      backgroundColor:
                          recording ? FeColors.dangerSoft : Colors.transparent,
                      foregroundColor:
                          recording ? FeColors.danger : FeColors.ink2,
                      shape: const CircleBorder(),
                    ),
                    icon: Icon(
                      recording ? LucideIcons.square : LucideIcons.mic,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: style?.copyWith(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'order_detail.chat_input_hint'.getString(context),
                        hintStyle: const TextStyle(color: FeColors.ink2),
                        // The theme fills inputs white for the light screens;
                        // left on, this panel's white text would be typed
                        // onto white.
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      height: 32,
                      width: 32,
                      // Listens to the text controller directly (rather than
                      // relying on the parent's setState) so the button's
                      // enabled look updates on every keystroke, not just
                      // when an attachment/recording change already
                      // triggers a rebuild.
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, _) {
                          final hasContent =
                              controller.text.trim().isNotEmpty ||
                                  attachments.isNotEmpty ||
                                  voiceAttachment != null;
                          final canSend = hasContent && !sending && !recording;
                          return IconButton.filled(
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              backgroundColor: FeColors.panel,
                              foregroundColor: Colors.black,
                              // Faint on the dark composer rather than the
                              // previous near-opaque white, so "nothing to
                              // send" reads as clearly off next to the full
                              // white circle it becomes once enabled.
                              disabledBackgroundColor: const Color(0x1FFFFFFF),
                              disabledForegroundColor: FeColors.ink2,
                            ),
                            onPressed: canSend ? onSend : null,
                            icon: const Icon(LucideIcons.send, size: 15),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// One not-yet-sent attachment in the composer's preview strip, with its own
/// remove button — mirrors `_AttachmentTile` in checklist_item_sheet.dart,
/// but simpler: nothing here has been uploaded yet, so removing one needs no
/// confirmation dialog and no network call.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.photo, required this.onRemove});

  final CapturedPhoto photo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        width: 60,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(context.radii.card),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.radii.card),
                child: Image.memory(photo.bytes, fit: BoxFit.cover),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
}

/// The not-yet-sent voice note above the composer — same role as
/// `_AttachmentPreview` for images, but a single clip shown as a labeled pill
/// (icon + duration) rather than a thumbnail, since there is nothing visual
/// to preview.
class _VoiceAttachmentPreview extends StatelessWidget {
  const _VoiceAttachmentPreview({
    required this.recording,
    required this.onRemove,
  });

  final VoiceRecording recording;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1E22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.mic, size: 16, color: FeColors.primary),
            const SizedBox(width: 8),
            AppText(
              formatClipDuration(recording.duration),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, size: 11, color: Colors.white),
              ),
            ),
          ],
        ),
      );
}

/// Thumbnails of the images attached to a sent message, decoded from the
/// same `data:<mime>;base64,<data>` strings the message carries — whether it
/// was just sent or loaded back from `/api/fm/ai/chat/history`.
class _MessageImages extends StatelessWidget {
  const _MessageImages({required this.dataUrls});

  final List<String> dataUrls;

  @override
  Widget build(BuildContext context) {
    final decoded = <Uint8List>[];
    for (final url in dataUrls) {
      final bytes = decodeChatImage(url);
      if (bytes != null) decoded.add(bytes);
    }
    if (decoded.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < decoded.length; i++)
          GestureDetector(
            onTap: () => _openViewer(context, decoded, i),
            child: Container(
              // Card radius + a hairline border — the same treatment
              // checklist_item_sheet.dart's own photo tiles use — so a sent
              // photo reads as a deliberately designed thumbnail rather than
              // a raw clipped image dropped into the bubble.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(context.radii.card),
                border: Border.all(color: FeColors.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(context.radii.card),
                child: Image.memory(
                  decoded[i],
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openViewer(BuildContext context, List<Uint8List> images, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            _MessageImageViewer(images: images, initialIndex: index),
      ),
    );
  }
}

/// Full-screen pan/zoom viewer for a message's attached images. Kept
/// separate from `widgets/photo_viewer.dart`'s `showPhotoViewer`, which loads
/// its images with `Image.network` — these are raw bytes decoded from a
/// `data:` URL, never a fetchable URL, so they need `Image.memory` instead.
class _MessageImageViewer extends StatefulWidget {
  const _MessageImageViewer({required this.images, required this.initialIndex});

  final List<Uint8List> images;
  final int initialIndex;

  @override
  State<_MessageImageViewer> createState() => _MessageImageViewerState();
}

class _MessageImageViewerState extends State<_MessageImageViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(LucideIcons.x, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.images.length,
          itemBuilder: (context, index) => InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.memory(widget.images[index], fit: BoxFit.contain),
            ),
          ),
        ),
      );
}
