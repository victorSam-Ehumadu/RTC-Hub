import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Stream A, §2.8: "NLP-assisted profile building — extract skills from an
/// uploaded CV". A self-contained screen rather than a change inside
/// `edit_profile_screen.dart` (Stream C's file): CV upload had no UI
/// anywhere in the app yet — `StorageRepository.uploadCv` existed since the
/// original schema, but nothing called it.
class CvSkillsScreen extends ConsumerStatefulWidget {
  const CvSkillsScreen({super.key});

  @override
  ConsumerState<CvSkillsScreen> createState() => _CvSkillsScreenState();
}

enum _Stage { pick, working, review, done }

class _CvSkillsScreenState extends ConsumerState<CvSkillsScreen> {
  _Stage _stage = _Stage.pick;
  Object? _error;
  List<String> _suggested = const [];
  final Set<String> _accepted = {};
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

      final existing = {
        for (final s in await ref.read(profileRepoProvider).skills(me.id))
          s.name.toLowerCase(),
      };

      // A CV worth reading skills from is worth saving to the profile too —
      // do both in the same trip through the file picker.
      if (picked.path != null) {
        final url =
            await ref.read(storageRepoProvider).uploadCv(File(picked.path!));
        await ref.read(profileRepoProvider).update(me.copyWith(cvUrl: url));
        ref.invalidate(myProfileProvider);
      }

      final skills = await ref.read(aiRepoProvider).extractSkillsFromCv(
            bytes: bytes,
            mimeType: _mimeFor(picked.extension),
          );
      //then point VS Code/Android Studio at the new path and delete the OneDrive copy once you've confirmed the clone is clean.
      setState(() {
        _suggested =
            skills.where((s) => !existing.contains(s.toLowerCase())).toList();
        _accepted
          ..clear()
          ..addAll(_suggested); // opt-out rather than opt-in — fewer taps
        _stage = _Stage.review;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _stage = _Stage.pick;
      });
    }
  }

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
    for (final name in _accepted) {
      try {
        await repo.addSkill(name);
      } catch (_) {
        // Already on the profile, or a stray hiccup — don't let one skill
        // block the rest of the batch.
      }
    }
    if (_userId != null) ref.invalidate(skillsProvider(_userId!));
    if (mounted) setState(() => _stage = _Stage.done);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Skills from your CV')),
      body: switch (_stage) {
        _Stage.pick => _PickView(error: _error, onPick: _pickAndAnalyse),
        _Stage.working => const Loading(),
        _Stage.review => _ReviewView(
            suggested: _suggested,
            accepted: _accepted,
            onToggle: (name) => setState(() {
              if (!_accepted.remove(name)) _accepted.add(name);
            }),
            onConfirm: _confirm,
          ),
        _Stage.done => _DoneView(count: _accepted.length),
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
              'PDF or Word document. The assistant will suggest skills to '
              'add to your profile based on what it reads.',
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
    required this.suggested,
    required this.accepted,
    required this.onToggle,
    required this.onConfirm,
  });

  final List<String> suggested;
  final Set<String> accepted;
  final void Function(String name) onToggle;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (suggested.isEmpty) {
      return EmptyState(
        icon: Icons.check_circle_outline,
        title: 'Nothing new to add',
        message: 'Every skill the assistant found is already on your '
            'profile, or none were detected.',
        action: FilledButton(
          onPressed: onConfirm,
          child: const Text('Done'),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            'Tap to remove any that don\'t belong — the rest get added to '
            'your profile.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in suggested)
                  FilterChip(
                    label: Text(name),
                    selected: accepted.contains(name),
                    onSelected: (_) => onToggle(name),
                    selectedColor: AppColors.accent.withValues(alpha: 0.18),
                    checkmarkColor: AppColors.accent,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: accepted.isEmpty ? null : onConfirm,
            child: Text(
              accepted.isEmpty
                  ? 'Select at least one skill'
                  : 'Add ${accepted.length} skill${accepted.length == 1 ? '' : 's'}',
            ),
          ),
        ),
      ],
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.check_circle_outline,
        title: count == 0 ? 'No skills added' : 'Skills added',
        message: count == 0
            ? null
            : '$count skill${count == 1 ? '' : 's'} added to your profile.',
      );
}
