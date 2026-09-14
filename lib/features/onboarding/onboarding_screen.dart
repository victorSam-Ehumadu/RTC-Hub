import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/assistant.dart';
import '../../models/profile.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../assistant/assistant_chat_view.dart';

/// Stream A, §2.6: walks a new user through completing their profile,
/// section by section, driven by a live Gemini call rather than a fixed
/// script — the brief explicitly rejects "a hardcoded script of fixed
/// responses". Shown on first login (the redirect lives in a later step)
/// and reachable again afterwards from the profile screen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  List<ChatMessage>? _messages;
  Object? _loadError;
  bool _sending = false;
  int _exchanges = 0;

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
      final ai = ref.read(aiRepoProvider);
      var history = await ai.history();

      if (history.isEmpty) {
        // First visit — the assistant speaks first instead of leaving a new
        // user looking at an empty box wondering what to type.
        final prompt = await _buildSystemPrompt();
        final opener = await ai.startOnboarding(systemPrompt: prompt);
        history = [opener];
      }

      if (mounted) setState(() => _messages = history);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  /// Pulls in the current profile + skills so the assistant's very first
  /// message (and every one after) already knows what is and isn't filled
  /// in — this is the "context-aware feedback" §2.6 asks for, not a
  /// generic greeting.
  Future<String> _buildSystemPrompt() async {
    final me = await ref.read(myProfileProvider.future);
    if (me == null) throw StateError('No profile loaded yet.');
    final skills = await ref.read(profileRepoProvider).skills(me.id);
    return _systemPrompt(me, skills);
  }

  String _systemPrompt(Profile profile, List<Skill> skills) {
    final missing = <String>[
      if ((profile.bio ?? '').isEmpty) 'a short bio',
      if (skills.isEmpty) 'any skills',
      if ((profile.cvUrl ?? '').isEmpty) 'a CV upload',
      if ((profile.portfolioUrl ?? '').isEmpty) 'a portfolio link',
    ];

    return '''
You are the onboarding assistant inside RTC Hub, a community app for
Richfield College students, alumni and businesses. You are talking to
${profile.fullName}, a ${profile.role.toLowerCase()}.

Your job right now is to walk them through completing their profile, one
section at a time: bio, skills, work experience, CV, portfolio link. Be a
real conversational guide, not a script — read what they actually say and
respond to it specifically, ask one focused question at a time, and keep
replies short (2-4 sentences).

Their profile so far (${profile.profileCompleteness}% complete):
- Bio: ${(profile.bio ?? '').isEmpty ? 'not set' : 'set'}
- Skills listed: ${skills.isEmpty ? 'none' : skills.map((s) => s.name).join(', ')}
- CV uploaded: ${(profile.cvUrl ?? '').isEmpty ? 'no' : 'yes'}
- Portfolio link: ${(profile.portfolioUrl ?? '').isEmpty ? 'not set' : 'set'}

Missing right now: ${missing.isEmpty ? 'nothing — it looks complete' : missing.join(', ')}.

Give specific, context-aware feedback — for example, if they have no skills
listed, explain plainly that this means they will not turn up when a
business searches for those skills. When every section looks reasonably
filled in, say so clearly and tell them they can head into the app.
''';
  }

  Future<void> _send(String text) async {
    setState(() => _sending = true);
    try {
      final ai = ref.read(aiRepoProvider);
      final prompt = await _buildSystemPrompt();

      await ai.send(
        text,
        systemPrompt: prompt,
        priorTurns: _messages ?? const [],
      );
      final history = await ai.history();
      _exchanges++;
      unawaited(ai.setProfileStep(_exchanges));

      if (mounted) setState(() => _messages = history);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not read) so that coming back from /cv-skills after an
    // upload — which invalidates myProfileProvider — flips the exit
    // button's label without needing its own state.
    final hasCv = (ref.watch(myProfileProvider).valueOrNull?.cvUrl ?? '')
        .isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Getting you set up'),
        actions: [
          // An icon alone here had no label or prompt telling the user what
          // it was for — a `tooltip` needs a long-press to even discover on
          // mobile. A visible label fixes that outright.
          TextButton.icon(
            onPressed: () => context.push('/cv-skills'),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Upload CV'),
          ),
          TextButton(
            onPressed: () => context.go('/feed'),
            // "Skip" only makes sense before the user has put anything in.
            // Once a CV is on file, leaving is "done", not "skipped".
            child: Text(hasCv ? 'Done' : 'Skip for now'),
          ),
        ],
      ),
      body: _loadError != null
          ? ErrorView(error: _loadError!, onRetry: _load)
          : _messages == null
              ? const Loading()
              : AssistantChatView(
                  messages: _messages!,
                  sending: _sending,
                  onSend: _send,
                  hint: 'Tell the assistant about yourself…',
                ),
    );
  }
}
