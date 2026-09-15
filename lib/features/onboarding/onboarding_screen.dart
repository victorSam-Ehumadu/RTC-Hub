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

  /// Pulls in the current profile (+ skills, for the student/alumni prompt)
  /// so the assistant's very first message (and every one after) already
  /// knows what is and isn't filled in — this is the "context-aware
  /// feedback" §2.6 asks for, not a generic greeting. Branches on role
  /// because a business account has none of the fields (skills, CV,
  /// portfolio) the student/alumni walkthrough is built around.
  Future<String> _buildSystemPrompt() async {
    final me = await ref.read(myProfileProvider.future);
    if (me == null) throw StateError('No profile loaded yet.');
    if (me.isBusiness) return _businessSystemPrompt(me);
    final skills = await ref.read(profileRepoProvider).skills(me.id);
    return _studentAlumniSystemPrompt(me, skills);
  }

  /// Students and alumni share the same "digital portfolio" fields — the
  /// checklist itself groups them together ("student and alumni profiles
  /// include... skills, experience... CV"). Alumni get one line of
  /// different framing: their entries are what a current student sees when
  /// looking at outcomes from their own programme, not just their own CV.
  String _studentAlumniSystemPrompt(Profile profile, List<Skill> skills) {
    final missing = <String>[
      if ((profile.bio ?? '').isEmpty) 'a short bio',
      if (skills.isEmpty) 'any skills',
      if ((profile.cvUrl ?? '').isEmpty) 'a CV upload',
      if ((profile.portfolioUrl ?? '').isEmpty) 'a portfolio link',
    ];
    final valueProp = profile.isAlumni
        ? "As an alumnus, what you list here is also what current students "
            'in your programme see as a real outcome to aim for — not just '
            'your own record.'
        : 'A complete profile is what shows up when a business searches '
            'for your skills, and what a bounty poster sees before picking '
            'a solution.';

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

$valueProp Give specific, context-aware feedback — for example, if they
have no skills listed, explain plainly that this means they will not turn
up when a business searches for those skills. When every section looks
reasonably filled in, say so clearly and tell them they can head into the
app.
''';
  }

  /// A business account has none of the fields above — no skills, no CV,
  /// no work experience. Its "digital portfolio" is the company profile:
  /// name, industry, location, and a company-facing bio. Deliberately
  /// doesn't mention `talentDescription` — that field exists in the schema
  /// but has no edit UI anywhere in the app, so asking for it would send
  /// the user looking for a field that doesn't exist.
  String _businessSystemPrompt(Profile profile) {
    final missing = <String>[
      if ((profile.companyName ?? '').isEmpty) 'a company name',
      if ((profile.industry ?? '').isEmpty) 'an industry',
      if ((profile.companyLocation ?? '').isEmpty) 'a location',
      if ((profile.bio ?? '').isEmpty) 'a short company description',
    ];

    return '''
You are the onboarding assistant inside RTC Hub, a community app for
Richfield College students, alumni and businesses. You are talking to
someone setting up ${profile.companyName?.isNotEmpty == true ? profile.companyName : 'their'} business account.

Your job right now is to walk them through completing their company
profile, one section at a time: company name, industry, location, and a
short description of the company. Be a real conversational guide, not a
script — read what they actually say and respond to it specifically, ask
one focused question at a time, and keep replies short (2-4 sentences).

Their company profile so far:
- Company name: ${(profile.companyName ?? '').isEmpty ? 'not set' : profile.companyName}
- Industry: ${(profile.industry ?? '').isEmpty ? 'not set' : profile.industry}
- Location: ${(profile.companyLocation ?? '').isEmpty ? 'not set' : profile.companyLocation}
- Description: ${(profile.bio ?? '').isEmpty ? 'not set' : 'set'}

Missing right now: ${missing.isEmpty ? 'nothing — it looks complete' : missing.join(', ')}.

Give specific, context-aware feedback — for example, explain that students
browsing opportunities see this profile before they apply, so a missing
industry or description makes the listing look less credible. Note that
each opportunity they post still goes through a separate administrator
approval step before it's visible to students — that's about the listing,
not this profile. When every section looks reasonably filled in, say so
clearly and tell them they can head into the app.
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
    final me = ref.watch(myProfileProvider).valueOrNull;
    final isBusiness = me?.isBusiness ?? false;
    // "Done" once the section this role's walkthrough is actually about is
    // filled in — a CV for student/alumni, a full company profile for
    // business. Neither concept applies to the other role.
    final hasEntered = isBusiness
        ? (me?.companyName ?? '').isNotEmpty &&
            (me?.industry ?? '').isNotEmpty &&
            (me?.companyLocation ?? '').isNotEmpty
        : (me?.cvUrl ?? '').isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Getting you set up'),
        actions: [
          // CV upload only makes sense for student/alumni accounts —
          // businesses have no CV concept, so the button would just send
          // them somewhere with nothing relevant to do.
          if (!isBusiness)
            // An icon alone here had no label or prompt telling the user
            // what it was for — a `tooltip` needs a long-press to even
            // discover on mobile. A visible label fixes that outright.
            TextButton.icon(
              onPressed: () => context.push('/cv-skills'),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Upload CV'),
            ),
          TextButton(
            onPressed: () => context.go('/feed'),
            // "Skip" only makes sense before the user has put anything in.
            // Once the key section is filled in, leaving is "done", not
            // "skipped".
            child: Text(hasEntered ? 'Done' : 'Skip for now'),
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
