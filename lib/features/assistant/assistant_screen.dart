import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/assistant.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import 'assistant_chat_view.dart';

/// Stream A, §2.6: "an ongoing chatbot the user can return to with
/// freeform questions". Same conversation and the same `chat_messages`
/// history as the onboarding walkthrough (Step 4) — this is just a
/// different door into it, with a broader system prompt since the user
/// isn't necessarily mid-onboarding by the time they open this.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  List<ChatMessage>? _messages;
  Object? _loadError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _messages = null;
    });
    try {
      final history = await ref.read(aiRepoProvider).history();
      if (mounted) setState(() => _messages = history);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<String> _systemPrompt() async {
    final me = await ref.read(myProfileProvider.future);
    if (me == null) throw StateError('No profile loaded yet.');
    return _prompt(me);
  }

  String _prompt(Profile profile) => '''
You are the assistant inside RTC Hub, a community app for Richfield College
students, alumni and businesses. You are talking to ${profile.fullName}, a
${profile.role.toLowerCase()} whose profile is ${profile.profileCompleteness}%
complete.

Answer freeform questions about the platform — the feed, bounties (earning
Logic Points by solving other students' posted problems), connections,
opportunities, events — and give practical, specific help with their
profile when asked. Keep replies short and conversational, not a wall of
text.
''';

  Future<void> _send(String text) async {
    setState(() => _sending = true);
    try {
      final ai = ref.read(aiRepoProvider);
      await ai.send(
        text,
        systemPrompt: await _systemPrompt(),
        priorTurns: _messages ?? const [],
      );
      final history = await ai.history();
      if (mounted) setState(() => _messages = history);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: _loadError != null
          ? ErrorView(error: _loadError!, onRetry: _load)
          : _messages == null
              ? const Loading()
              : AssistantChatView(
                  messages: _messages!,
                  sending: _sending,
                  onSend: _send,
                  hint: 'Ask the assistant anything…',
                ),
    );
  }
}
