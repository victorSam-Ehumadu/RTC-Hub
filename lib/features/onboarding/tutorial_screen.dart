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
  });

  final IconData icon;
  final String title;
  final String body;
}

const _steps = [
  _TutorialStep(
    icon: Icons.dynamic_feed,
    title: 'Feed',
    body: "Posts from people you're connected to — code, questions, wins. "
        'Connect with more people to grow it, or use Discover to find new '
        'faces.',
  ),
  _TutorialStep(
    icon: Icons.bolt,
    title: 'Bounties',
    body: 'Posts with Logic Points attached. Solve someone else\'s problem, '
        'get picked as the accepted answer, and the points land in your '
        'ledger.',
  ),
  _TutorialStep(
    icon: Icons.work,
    title: 'Opportunities',
    body: 'Internships, learnerships and part-time roles posted by '
        'businesses. Apply straight from here — you get matched '
        'automatically when a new one fits your skills.',
  ),
  _TutorialStep(
    icon: Icons.forum,
    title: 'Messages',
    body: 'Direct messages with anyone you\'re connected to, live and in '
        'real time.',
  ),
  _TutorialStep(
    icon: Icons.person,
    title: 'Profile & assistant',
    body: 'Your skills, experience, CV and portfolio live here — and the '
        'AI assistant is always one tap away if you want help improving '
        'it.',
  ),
];

/// Stream A, §2.6: "an interactive first-run tutorial across the key
/// screens". A short swipeable walkthrough rather than on-screen coach
/// marks pointing at live widgets — coach marks would mean reaching into
/// `AppShell`/`_NavBar`, which nearly every stream touches, just to explain
/// five tabs.
class TutorialScreen extends ConsumerStatefulWidget {
  const TutorialScreen({super.key});

  @override
  ConsumerState<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends ConsumerState<TutorialScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _finishing = false;

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
                itemBuilder: (_, i) => _StepView(step: _steps[i]),
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
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _finishing
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
  const _StepView({required this.step});

  final _TutorialStep step;

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
        ],
      ),
    );
  }
}
