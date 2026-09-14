import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

class _TutorialStep {
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.prompt,
    required this.actionLabel,
    required this.resultLabel,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Instruction shown above the tap target — what to do, not just what to
  /// read.
  final String prompt;

  /// Label on the tap target itself before it's been tapped.
  final String actionLabel;

  /// What the tap target turns into afterwards, confirming something
  /// happened rather than just moving on.
  final String resultLabel;
}

const _steps = [
  _TutorialStep(
    icon: Icons.dynamic_feed,
    title: 'Feed',
    body: "Posts from people you're connected to — code, questions, wins. "
        'Connect with more people to grow it, or use Discover to find new '
        'faces.',
    prompt: 'Try reacting to a post:',
    actionLabel: 'React 👍',
    resultLabel: 'Nice — that\'s how it feels in the real feed.',
  ),
  _TutorialStep(
    icon: Icons.bolt,
    title: 'Bounties',
    body: 'Posts with Logic Points attached. Solve someone else\'s problem, '
        'get picked as the accepted answer, and the points land in your '
        'ledger.',
    prompt: 'Try accepting a bounty solution:',
    actionLabel: 'Accept solution',
    resultLabel: '+50 Logic Points — paid out the same way for real.',
  ),
  _TutorialStep(
    icon: Icons.work,
    title: 'Opportunities',
    body: 'Internships, learnerships and part-time roles posted by '
        'businesses. Apply straight from here — you get matched '
        'automatically when a new one fits your skills.',
    prompt: 'Try applying to a listing:',
    actionLabel: 'Apply now',
    resultLabel: 'Application sent — businesses see this instantly.',
  ),
  _TutorialStep(
    icon: Icons.forum,
    title: 'Messages',
    body: 'Direct messages with anyone you\'re connected to, live and in '
        'real time.',
    prompt: 'Try sending a quick reply:',
    actionLabel: 'Send "Sounds good 👍"',
    resultLabel: 'Delivered — messages arrive live, no refresh needed.',
  ),
  _TutorialStep(
    icon: Icons.person,
    title: 'Profile & assistant',
    body: 'Your skills, experience, CV and portfolio live here — and the '
        'AI assistant is always one tap away if you want help improving '
        'it.',
    prompt: 'Try asking the assistant something:',
    actionLabel: 'Ask "What should I add?"',
    resultLabel: '"Start with a bio and two or three skills."',
  ),
];

/// Stream A, §2.6: "an interactive first-run tutorial across the key
/// screens" — each step now requires the user to actually tap a small live
/// mock-up of that screen's core action before moving on, rather than only
/// swiping past static text. Kept self-contained in this one file rather
/// than pointing coach marks at the real `AppShell`/`_NavBar` — that file is
/// shared across every stream and already under active change elsewhere.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

  // Which steps the user has actually tapped through, not just viewed.
  final Set<int> _tried = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      await ref.read(aiRepoProvider).completeTutorial();
    } catch (_) {
      // Not worth blocking entry to the app over — worst case they see the
      // tutorial again next time.
    }
    // AppShell is still mounted underneath this screen and is watching
    // this, so it needs a fresh read or it would show the tutorial again
    // the moment we navigate away from here.
    ref.invalidate(onboardingProgressProvider);
    // Chain straight into the AI onboarding walkthrough — both are meant to
    // happen on first login, not just the tour.
    if (mounted) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _steps.length - 1;
    final canAdvance = _tried.contains(_index);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _StepView(
                  step: _steps[i],
                  tried: _tried.contains(i),
                  onTry: () => setState(() => _tried.add(i)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 20 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.accent
                                : AppColors.accent.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!canAdvance)
                    Text(
                      'Tap the card above to continue',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _finishing || !canAdvance
                        ? null
                        : last
                            ? _finish
                            : () => _controller.nextPage(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOut,
                                ),
                    child: _finishing
                        ? const DottedProgressIndicator(
                            size: 16, color: Colors.white)
                        : Text(last ? 'Get started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({
    required this.step,
    required this.tried,
    required this.onTry,
  });

  final _TutorialStep step;
  final bool tried;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.button.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 40, color: AppColors.button),
          ),
          const SizedBox(height: 28),
          Text(
            step.title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.5,
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 24),
          _TapToTryCard(step: step, tried: tried, onTry: onTry),
        ],
      ),
    );
  }
}

/// The interactive part of a step: a small mock-up of that screen's core
/// action, live enough to tap. Tapping is the thing that unlocks "Next" —
/// swiping past this without touching it isn't enough.
class _TapToTryCard extends StatelessWidget {
  const _TapToTryCard({
    required this.step,
    required this.tried,
    required this.onTry,
  });

  final _TutorialStep step;
  final bool tried;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: tried
          ? Container(
              key: const ValueKey('result'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.resultLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              key: const ValueKey('prompt'),
              children: [
                Text(
                  step.prompt,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: onTry,
                  child: Text(step.actionLabel),
                ),
              ],
            ),
    );
  }
}
