import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/assistant.dart';
import '../../widgets/common.dart';

/// The chat surface shared by the onboarding walkthrough and the freeform
/// assistant screen — same bubbles, same composer. Only the system prompt
/// and kickoff behaviour differ, and those live in the two callers, not
/// here.
class AssistantChatView extends StatefulWidget {
  const AssistantChatView({
    super.key,
    required this.messages,
    required this.onSend,
    this.sending = false,
    this.hint = 'Ask something…',
  });

  final List<ChatMessage> messages;
  final Future<void> Function(String text) onSend;
  final bool sending;
  final String hint;

  @override
  State<AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<AssistantChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant AssistantChatView old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length) _scrollToBottom();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Renders oldest-first, top to bottom — the plain, unambiguous way to
  /// order a list — and just scrolls to the end after every build instead
  /// of using the `reverse: true` + reversed-index trick. That trick is
  /// easy to get backwards (it was, here) and one direct scroll call is
  /// simpler to reason about than reversed index math.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || widget.sending) return;
    _input.clear();
    await widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.messages.isEmpty
              ? const EmptyState(
                  icon: Icons.smart_toy_outlined,
                  title: 'Say hello',
                  message: 'Ask the assistant anything about your profile '
                      'or the platform.',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  itemCount: widget.messages.length,
                  itemBuilder: (_, i) {
                    final message = widget.messages[i];
                    return _Bubble(message: message);
                  },
                ),
        ),
        if (widget.sending)
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 16),
            child: _TypingIndicator(),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: widget.sending ? null : _submit,
                  icon: widget.sending
                      ? const DottedProgressIndicator(
                          size: 16, color: Colors.white)
                      : const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.isFromUser;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color:
              mine ? AppColors.accent.withValues(alpha: 0.16) : scheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: Border.all(
            color: mine
                ? AppColors.accent.withValues(alpha: 0.35)
                : scheme.outline,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.smart_toy_outlined,
                        size: 12, color: AppColors.button),
                    const SizedBox(width: 4),
                    Text(
                      'Assistant',
                      style: monoStyle(
                          size: 10,
                          weight: FontWeight.w700,
                          color: AppColors.button),
                    ),
                  ],
                ),
              ),
            Text(message.content, style: const TextStyle(height: 1.4)),
            const SizedBox(height: 3),
            Text(
              formatTimeAgo(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DottedProgressIndicator(size: 14, color: AppColors.button),
          const SizedBox(width: 8),
          Text(
            'Thinking…',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      );
}
