import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/chat_message.dart';
import '../../domain/maintenance_record.dart';
import '../../state/chat_controller.dart';
import '../../state/order_detail_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';

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
    super.dispose();
  }

  String get _greeting {
    final subject = widget.orderKey.type == OrderType.workOrder
        ? 'work order'
        : '${widget.orderKey.type.slug} maintenance';
    final asset = widget.assetName == null ? '' : ' for ${widget.assetName}';
    return 'Ask me about this $subject$asset — checklist steps, asset details, '
        'or the order itself.';
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _scrollToEnd();
    await ref.read(chatControllerProvider(widget.orderKey).notifier).send(text);
    _scrollToEnd();
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(context.radii.xxxl),
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
                              AlwaysStoppedAnimation(AppColors.gray400),
                        ),
                      ),
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      children: [
                        if (state.messages.isEmpty)
                          _Bubble(
                            message: ChatMessage(
                              id: 'welcome',
                              content: _greeting,
                              fromTechnician: false,
                            ),
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
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: const Icon(LucideIcons.sparkles,
                  size: 16, color: AppColors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Assistant',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    assetName ?? 'This order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.gray400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.x, size: 20, color: AppColors.gray400),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromTechnician;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.white : const Color(0xFF2B2D31),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? 16 : 4),
            topRight: Radius.circular(mine ? 4 : 16),
            bottomLeft: const Radius.circular(16),
            bottomRight: const Radius.circular(16),
          ),
        ),
        child: message.pending
            ? const _Thinking()
            // The technician's own text is shown exactly as typed. The
            // assistant answers in Markdown — headings, bold labels, bullet
            // lists — which read as literal `**Ticket ID:**` and `####` if
            // printed raw.
            : mine
                ? Text(
                    message.content,
                    style: const TextStyle(
                      color: AppColors.black,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  )
                : _AssistantMarkdown(content: message.content),
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  const _AssistantMarkdown({required this.content});

  final String content;

  static const _body = TextStyle(
    color: AppColors.white,
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
            color: AppColors.blue400,
            decoration: TextDecoration.underline,
          ),
          listBullet: _body,
          blockquote: _body,
          code: _body.copyWith(
            fontFamily: 'monospace',
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

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 12,
            width: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(AppColors.gray400),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Thinking…',
            style: TextStyle(color: AppColors.gray400, fontSize: 12),
          ),
        ],
      );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.style,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1E22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: style?.copyWith(
                    color: AppColors.white,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask about this order…',
                    hintStyle: TextStyle(color: AppColors.gray600),
                    // The theme fills inputs white for the light screens; left
                    // on, this panel's white text would be typed onto white.
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton.filled(
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.black,
                      disabledBackgroundColor: const Color(0x66FFFFFF),
                    ),
                    onPressed: sending ? null : onSend,
                    icon: const Icon(LucideIcons.send, size: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
