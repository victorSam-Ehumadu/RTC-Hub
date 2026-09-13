import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/verification.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Where an alumnus proves they studied here (§2.1).
///
/// This is the screen the account gate sends an unverified alumnus to, and
/// it has to do two jobs at once: collect a claim and a document, and
/// explain why it is asking. Someone who graduated in 2019 and can no longer
/// open their student mailbox has no idea why this app is treating them
/// differently from a student, and a form that does not say so reads as
/// suspicion rather than process.
class AlumniVerificationScreen extends ConsumerStatefulWidget {
  const AlumniVerificationScreen({super.key});

  @override
  ConsumerState<AlumniVerificationScreen> createState() =>
      _AlumniVerificationScreenState();
}

class _AlumniVerificationScreenState
    extends ConsumerState<AlumniVerificationScreen> {
  final _studentNumber = TextEditingController();
  final _note = TextEditingController();

  String _evidenceKind = kEvidenceKinds.first.value;
  int? _graduationYear;
  String? _course;
  String? _campus;
  File? _evidence;
  bool _busy = false;

  @override
  void dispose() {
    _studentNumber.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      _evidence != null &&
      _graduationYear != null &&
      RegExp(r'^\d{6,12}$').hasMatch(_studentNumber.text.trim());

  Future<void> _pick({required bool fromCamera}) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        // A certificate photographed at full resolution is several
        // megabytes of paper; a reviewer needs it legible, not archival.
        maxWidth: 2000,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _evidence = File(picked.path));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() => _busy = true);
    try {
      await ref.read(verificationRepoProvider).submit(
            evidence: _evidence!,
            studentNumber: _studentNumber.text,
            graduationYear: _graduationYear!,
            evidenceKind: _evidenceKind,
            course: _course,
            campus: _campus,
            note: _note.text,
          );
      ref.invalidate(myVerificationProvider);
      if (mounted) showMessage(context, 'Sent for review.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(myVerificationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your graduation')),
      body: existing.when(
        loading: () => const Loading(),
        error: (err, _) => ErrorView(
          error: err,
          onRetry: () => ref.invalidate(myVerificationProvider),
        ),
        data: (submission) {
          // A pending submission is a waiting room, not a form.
          if (submission != null && submission.isPending) {
            return _Waiting(submission: submission);
          }
          return _form(context, submission);
        },
      ),
    );
  }

  Widget _form(BuildContext context, AlumniVerification? rejected) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final thisYear = DateTime.now().year;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
      children: [
        if (rejected != null && rejected.isRejected) ...[
          _RejectionNotice(reason: rejected.reviewerNote),
          const SizedBox(height: 8),
        ],

        Text(
          'Why we are asking',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Students prove who they are with a Richfield email address. Yours '
          'has probably been closed since you graduated, so we ask for a '
          'document instead. A person at Richfield checks it — usually '
          'within a day or two — and nobody else ever sees it.',
          style: TextStyle(fontSize: 13, height: 1.5, color: muted),
        ),

        const SectionHeader(title: 'Your studies'),
        TextField(
          controller: _studentNumber,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Student number',
            helperText: 'The one on your certificate or transcript',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _graduationYear,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Year you graduated'),
          items: [
            for (var y = thisYear; y >= 1990; y--)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) => setState(() => _graduationYear = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _course,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Qualification'),
          items: [
            for (final f in kFaculties)
              for (final c in f.courses)
                DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
          ],
          onChanged: (v) => setState(() => _course = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _campus,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Campus'),
          items: [
            for (final c in kCampuses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _campus = v),
        ),

        const SectionHeader(title: 'Your proof'),
        // RadioGroup rather than per-tile groupValue/onChanged: those were
        // deprecated after Flutter 3.32.
        RadioGroup<String>(
          groupValue: _evidenceKind,
          onChanged: (v) => setState(() => _evidenceKind = v ?? _evidenceKind),
          child: Column(
            children: [
              for (final kind in kEvidenceKinds)
                RadioListTile<String>(
                  value: kind.value,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title:
                      Text(kind.label, style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    kind.hint,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        _EvidencePicker(
          file: _evidence,
          onChoose: () => _pick(fromCamera: false),
          onPhotograph: () => _pick(fromCamera: true),
          onClear: () => setState(() => _evidence = null),
        ),

        const SizedBox(height: 14),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Anything the reviewer should know (optional)',
            hintText: 'I changed my surname after graduating…',
          ),
        ),

        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: (_busy || !_ready) ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.verified_outlined, size: 18),
          label: Text(_busy ? 'Sending…' : 'Send for review'),
        ),
        if (!_ready)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _evidence == null
                  ? 'Attach a document to continue.'
                  : 'Fill in your student number and graduation year.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 14, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Your document is stored privately and is visible only to '
                'Richfield administrators. It never appears on your profile.',
                style: TextStyle(fontSize: 11.5, height: 1.45, color: muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RejectionNotice extends StatelessWidget {
  const _RejectionNotice({this.reason});

  final String? reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 17, color: AppColors.danger),
              const SizedBox(width: 9),
              const Text(
                'We could not confirm this',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reason ??
                'The document was not clear enough to read. Try again with a '
                    'better photograph.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _Waiting extends ConsumerWidget {
  const _Waiting({required this.submission});

  final AlumniVerification submission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, size: 54, color: AppColors.points),
            const SizedBox(height: 20),
            Text(
              'With a reviewer',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'We have your ${submission.evidenceLabel.toLowerCase()} and your '
              'claim to have graduated in ${submission.graduationYear}. '
              'Someone at Richfield will check it, usually within a day or '
              'two. You will get a notification either way.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.5, color: muted),
            ),
            const SizedBox(height: 26),
            OutlinedButton.icon(
              onPressed: () => ref
                ..invalidate(myVerificationProvider)
                ..invalidate(myProfileProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Check again'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () async {
                await ref.read(authRepoProvider).signOut();
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EvidencePicker extends StatelessWidget {
  const _EvidencePicker({
    required this.file,
    required this.onChoose,
    required this.onPhotograph,
    required this.onClear,
  });

  final File? file;
  final VoidCallback onChoose;
  final VoidCallback onPhotograph;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPhotograph,
              icon: const Icon(Icons.photo_camera_outlined, size: 17),
              label: const Text('Photograph'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.image_outlined, size: 17),
              label: const Text('Choose'),
            ),
          ),
        ],
      );
    }

    return Stack(
      alignment: Alignment.topRight,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            file!,
            width: double.infinity,
            height: 190,
            fit: BoxFit.cover,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: CircleAvatar(
            radius: 15,
            backgroundColor: Colors.black54,
            child: IconButton(
              tooltip: 'Remove',
              iconSize: 16,
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onClear,
            ),
          ),
        ),
      ],
    );
  }
}
