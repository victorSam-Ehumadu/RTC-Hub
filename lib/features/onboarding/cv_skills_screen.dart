import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/assistant.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Stream A, §2.8: "NLP-assisted profile building — extract skills and
/// qualifications from an uploaded CV". A self-contained screen rather than
/// a change inside `edit_profile_screen.dart` (Stream C's file): CV upload
/// had no UI anywhere in the app yet — `StorageRepository.uploadCv` existed
/// since the original schema, but nothing called it. Work experience is the
/// same story: `ProfileRepository.addExperience` existed but had no caller
/// anywhere until this screen's review step confirms extracted entries.
class CvSkillsScreen extends ConsumerStatefulWidget {
  const CvSkillsScreen({super.key});

  @override
  ConsumerState<CvSkillsScreen> createState() => _CvSkillsScreenState();
}

enum _Stage { pick, working, review, done }

class _CvSkillsScreenState extends ConsumerState<CvSkillsScreen> {
  _Stage _stage = _Stage.pick;
  Object? _error;
  List<String> _suggestedSkills = const [];
  final Set<String> _acceptedSkills = {};
  List<ExtractedExperience> _suggestedExperience = const [];
  final Set<int> _acceptedExperience = {}; // indices into _suggestedExperience
  String? _userId;

  Future<void> _pickAndAnalyse() async {
    setState(() => _error = null);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      setState(() => _error = StateError('Could not read that file.'));
      return;
    }

    setState(() => _stage = _Stage.working);
    try {
      final me = await ref.read(myProfileProvider.future);
      if (me == null) throw StateError('No profile loaded yet.');
      _userId = me.id;

      final repo = ref.read(profileRepoProvider);
      final existingSkills = {
        for (final s in await repo.skills(me.id)) s.name.toLowerCase(),
      };
      final existingExperience = {
        for (final w in await repo.experience(me.id))
          _experienceKey(w.title, w.company),
      };

      // A CV worth reading skills from is worth saving to the profile too —
      // do both in the same trip through the file picker.
      if (picked.path != null) {
        final url =
            await ref.read(storageRepoProvider).uploadCv(File(picked.path!));
        await ref.read(profileRepoProvider).update(me.copyWith(cvUrl: url));
        ref.invalidate(myProfileProvider);
      }

      final extraction = await ref.read(aiRepoProvider).extractFromCv(
            bytes: bytes,
            mimeType: _mimeFor(picked.extension),
          );

      setState(() {
        _suggestedSkills = extraction.skills
            .where((s) => !existingSkills.contains(s.toLowerCase()))
            .toList();
        _acceptedSkills
          ..clear()
          ..addAll(_suggestedSkills); // opt-out rather than opt-in — fewer taps

        _suggestedExperience = extraction.experience
            .where((e) => !existingExperience
                .contains(_experienceKey(e.title, e.company)))
            .toList();
        _acceptedExperience
          ..clear()
          ..addAll(List.generate(_suggestedExperience.length, (i) => i));

        _stage = _Stage.review;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _stage = _Stage.pick;
      });
    }
  }

  /// Dedup key for a work-experience entry — same role at the same company
  /// is treated as "already on the profile" even if wording differs
  /// slightly, so re-uploading the same CV doesn't create duplicates.
  String _experienceKey(String title, String company) =>
      '${title.toLowerCase()}@${company.toLowerCase()}';

  String _mimeFor(String? ext) => switch (ext?.toLowerCase()) {
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' =>
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        _ => 'application/octet-stream',
      };

  Future<void> _confirm() async {
    setState(() => _stage = _Stage.working);
    final repo = ref.read(profileRepoProvider);
    for (final name in _acceptedSkills) {
      try {
        await repo.addSkill(name);
      } catch (_) {
        // Already on the profile, or a stray hiccup — don't let one skill
        // block the rest of the batch.
      }
    }
    for (final i in _acceptedExperience) {
      final e = _suggestedExperience[i];
      try {
        await repo.addExperience(
          title: e.title,
          company: e.company,
          startDate: e.startDate,
          endDate: e.endDate,
          description: e.description,
        );
      } catch (_) {
        // Same tolerance as skills above — one bad entry shouldn't block
        // the rest of the batch.
      }
    }
    if (_userId != null) {
      ref.invalidate(skillsProvider(_userId!));
      ref.invalidate(experienceProvider(_userId!));
    }
    if (mounted) setState(() => _stage = _Stage.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skills & experience from your CV')),
      body: switch (_stage) {
        _Stage.pick => _PickView(error: _error, onPick: _pickAndAnalyse),
        _Stage.working => const Loading(),
        _Stage.review => _ReviewView(
            suggestedSkills: _suggestedSkills,
            acceptedSkills: _acceptedSkills,
            onToggleSkill: (name) => setState(() {
              if (!_acceptedSkills.remove(name)) _acceptedSkills.add(name);
            }),
            suggestedExperience: _suggestedExperience,
            acceptedExperience: _acceptedExperience,
            onToggleExperience: (i) => setState(() {
              if (!_acceptedExperience.remove(i)) _acceptedExperience.add(i);
            }),
            onConfirm: _confirm,
          ),
        _Stage.done => _DoneView(
            skillCount: _acceptedSkills.length,
            experienceCount: _acceptedExperience.length,
          ),
      },
    );
  }
}

class _PickView extends StatelessWidget {
  const _PickView({required this.error, required this.onPick});

  final Object? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'Upload your CV',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'PDF or Word document. The assistant will suggest skills and '
              'work experience to add to your profile based on what it '
              'reads.',
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.4,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              ErrorView(error: error!),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Choose file'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewView extends StatelessWidget {
  const _ReviewView({
    required this.suggestedSkills,
    required this.acceptedSkills,
    required this.onToggleSkill,
    required this.suggestedExperience,
    required this.acceptedExperience,
    required this.onToggleExperience,
    required this.onConfirm,
  });

  final List<String> suggestedSkills;
  final Set<String> acceptedSkills;
  final void Function(String name) onToggleSkill;
  final List<ExtractedExperience> suggestedExperience;
  final Set<int> acceptedExperience;
  final void Function(int index) onToggleExperience;
  final VoidCallback onConfirm;

  int get _acceptedTotal => acceptedSkills.length + acceptedExperience.length;

  @override
  Widget build(BuildContext context) {
    if (suggestedSkills.isEmpty && suggestedExperience.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nothing new to add',
        message: 'Everything the assistant found is already on your '
            'profile, or none were detected.',
        action: FilledButton(
          onPressed: onConfirm,
          child: const Text('Done'),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tap to remove any that don\'t belong — the rest get '
                  'added to your profile.',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                if (suggestedSkills.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionHeader(title: 'Skills (${suggestedSkills.length})'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in suggestedSkills)
                        FilterChip(
                          label: Text(name),
                          selected: acceptedSkills.contains(name),
                          onSelected: (_) => onToggleSkill(name),
                          selectedColor:
                              AppColors.accent.withValues(alpha: 0.18),
                          checkmarkColor: AppColors.accent,
                        ),
                    ],
                  ),
                ],
                if (suggestedExperience.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: 'Work experience (${suggestedExperience.length})',
                  ),
                  const SizedBox(height: 4),
                  for (var i = 0; i < suggestedExperience.length; i++)
                    _ExperienceTile(
                      experience: suggestedExperience[i],
                      selected: acceptedExperience.contains(i),
                      onToggle: () => onToggleExperience(i),
                    ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _acceptedTotal == 0 ? null : onConfirm,
            child: Text(
              _acceptedTotal == 0
                  ? 'Select at least one item'
                  : 'Add $_acceptedTotal item${_acceptedTotal == 1 ? '' : 's'}',
            ),
          ),
        ),
      ],
    );
  }
}

class _ExperienceTile extends StatelessWidget {
  const _ExperienceTile({
    required this.experience,
    required this.selected,
    required this.onToggle,
  });

  final ExtractedExperience experience;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final range =
        '${_formatMonthYear(experience.startDate)} — '
        '${experience.endDate == null ? 'Present' : _formatMonthYear(experience.endDate)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: selected,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          experience.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${experience.company} · $range'),
            if ((experience.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(experience.description!),
            ],
          ],
        ),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatMonthYear(DateTime? d) =>
    d == null ? 'Unknown' : '${_months[d.month - 1]} ${d.year}';

class _DoneView extends StatelessWidget {
  const _DoneView({required this.skillCount, required this.experienceCount});

  final int skillCount;
  final int experienceCount;

  @override
  Widget build(BuildContext context) {
    final total = skillCount + experienceCount;
    final parts = [
      if (skillCount > 0) '$skillCount skill${skillCount == 1 ? '' : 's'}',
      if (experienceCount > 0)
        '$experienceCount experience entr${experienceCount == 1 ? 'y' : 'ies'}',
    ];

    return EmptyState(
      icon: Icons.check_circle_outline,
      title: total == 0 ? 'Nothing added' : 'Profile updated',
      message: total == 0
          ? null
          : '${parts.join(' and ')} added to your profile.',
    );
  }
}
