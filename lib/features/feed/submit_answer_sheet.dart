import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/storage_repository.dart';
import '../../models/post.dart';
import '../../models/sheet.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Composer for an answer to a bounty.
///
/// Kept separate from the discussion reply bar on purpose: a submission has
/// to carry something — code, a spreadsheet or a file — and `trg_comments_guard`
/// rejects an empty one. Asking for that in a one-line text field would mean
/// most attempts bounce off the database.
///
/// Which tab opens first follows the bounty's faculty rather than the user's:
/// an IT bounty wants code back, a Business bounty wants a model back, and
/// guessing right saves a tap on the common path.
Future<bool?> showSubmitAnswerSheet(BuildContext context, Post post) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SubmitAnswerSheet(post: post),
  );
}

class _SubmitAnswerSheet extends ConsumerStatefulWidget {
  const _SubmitAnswerSheet({required this.post});

  final Post post;

  @override
  ConsumerState<_SubmitAnswerSheet> createState() => _SubmitAnswerSheetState();
}

enum _Mode { code, sheet, file }

class _SubmitAnswerSheetState extends ConsumerState<_SubmitAnswerSheet> {
  final _note = TextEditingController();
  final _code = TextEditingController();

  late _Mode _mode = widget.post.faculty == 'BUSINESS' ? _Mode.sheet : _Mode.code;
  String _language = 'dart';

  SheetDoc? _sheet;
  PlatformFile? _picked;
  int? _pickedSize;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A Business bounty is answered with a model, so start from the sheet the
    // asker posted when there is one — editing their numbers is the normal
    // shape of the answer, not building a grid from nothing.
    _sheet = widget.post.sheet ?? SheetDoc.blank();
    _language = widget.post.codeLanguage ?? 'dart';
  }

  @override
  void dispose() {
    _note.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _hasPayload => switch (_mode) {
        _Mode.code => _code.text.trim().isNotEmpty,
        _Mode.sheet => _sheet != null && !_sheet!.isEmpty,
        _Mode.file => _picked != null,
      };

  Future<void> _pickFile() async {
    try {
      final file = await ref.read(documentServiceProvider).pickAttachment();
      if (file?.path == null || !mounted) return;

      // PlatformFile exposes no size, so measure the file itself. Doing it
      // here keeps the rebuild path free of disk I/O.
      final bytes = await File(file!.path!).length();
      if (!mounted) return;
      setState(() {
        _picked = file;
        _pickedSize = bytes;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Imports a spreadsheet the responder built in Excel.
  ///
  /// This is the other half of the round-trip: they opened the asker's sheet
  /// in Excel, changed it, and bring it back. Reading it here rather than
  /// only uploading the raw file means the app can still preview it in the
  /// thread.
  Future<void> _importSheet() async {
    try {
      final picked = await ref
          .read(documentServiceProvider)
          .pickAttachment(extensions: ['xlsx', 'csv']);
      if (picked?.path == null || !mounted) return;

      final doc = await ref
          .read(documentServiceProvider)
          .readSheet(File(picked!.path!));
      if (!mounted) return;
      setState(() => _sheet = doc);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _submit() async {
    if (!_hasPayload) return;
    setState(() => _busy = true);

    try {
      String? url;
      String? name;
      int? size;
      String? kind;

      if (_mode == _Mode.file && _picked?.path != null) {
        // Uploads land in the private `submissions` bucket under <uid>/,
        // which is what the storage policies key ownership off.
        url = await ref.read(storageRepoProvider).upload(
              File(_picked!.path!),
              bucket: StorageRepository.submissions,
            );
        name = _picked!.name;
        size = _pickedSize;
        kind = 'FILE';
      }

      await ref.read(postRepoProvider).addSubmission(
            widget.post.id,
            content: _note.text.trim().isEmpty
                ? 'Submitted an answer.'
                : _note.text.trim(),
            codeLanguage: _mode == _Mode.code ? _language : null,
            codeSnippet: _mode == _Mode.code ? _code.text.trim() : null,
            sheetData: _mode == _Mode.sheet ? _sheet?.toMap() : null,
            attachmentUrl: url,
            attachmentName: name,
            attachmentSize: size,
            attachmentKind: kind ?? (_mode == _Mode.code ? 'CODE' : 'SHEET'),
          );

      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.bolt, size: 18, color: AppColors.points),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Answer this bounty',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                PointsChip(points: widget.post.bountyPoints),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Submissions are listed separately from the discussion, so the '
              'person who posted the bounty can find them.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
            ),

            const SizedBox(height: 16),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(
                  value: _Mode.code,
                  label: Text('Code'),
                  icon: Icon(Icons.terminal, size: 15),
                ),
                ButtonSegment(
                  value: _Mode.sheet,
                  label: Text('Sheet'),
                  icon: Icon(Icons.grid_on, size: 15),
                ),
                ButtonSegment(
                  value: _Mode.file,
                  label: Text('File'),
                  icon: Icon(Icons.attach_file, size: 15),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),

            const SizedBox(height: 14),
            if (_mode == _Mode.code) ...[
              DropdownButtonFormField<String>(
                initialValue: kCodeLanguages.contains(_language)
                    ? _language
                    : kCodeLanguages.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final l in kCodeLanguages)
                    DropdownMenuItem(value: l, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                minLines: 6,
                maxLines: 14,
                style: monoStyle(size: 12.5, weight: FontWeight.w400),
                decoration: const InputDecoration(
                  hintText: 'Paste your solution…',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ] else if (_mode == _Mode.sheet) ...[
              _SheetSummaryCard(sheet: _sheet, onImport: _importSheet),
            ] else ...[
              _FileCard(
              picked: _picked,
              sizeBytes: _pickedSize,
              onPick: _pickFile,
            ),
            ],

            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'What did you change, and why?',
              ),
            ),

            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: (_busy || !_hasPayload) ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 17),
              label: Text(_busy ? 'Submitting…' : 'Submit answer'),
            ),
            if (!_hasPayload)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  switch (_mode) {
                    _Mode.code => 'Add your code before submitting.',
                    _Mode.sheet => 'Import a spreadsheet before submitting.',
                    _Mode.file => 'Choose a file before submitting.',
                  },
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SheetSummaryCard extends StatelessWidget {
  const _SheetSummaryCard({required this.sheet, required this.onImport});

  final SheetDoc? sheet;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final empty = sheet == null || sheet!.isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_on, size: 16, color: facultyColor('BUSINESS')),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  empty ? 'No spreadsheet yet' : (sheet!.name ?? 'spreadsheet'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            empty
                ? 'Open the bounty’s sheet in Excel, make your changes, '
                    'then import the saved file here.'
                : sheet!.summary,
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file, size: 16),
            label: Text(empty ? 'Import .xlsx or .csv' : 'Replace'),
          ),
        ],
      ),
    );
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.picked,
    required this.sizeBytes,
    required this.onPick,
  });

  final PlatformFile? picked;
  final int? sizeBytes;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  picked?.name ?? 'No file chosen',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (picked != null && sizeBytes != null) ...[
            const SizedBox(height: 4),
            Text(
              '${(sizeBytes! / 1024).toStringAsFixed(0)} KB',
              style: TextStyle(fontSize: 11.5, color: muted),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(picked == null ? 'Choose a file' : 'Replace'),
          ),
        ],
      ),
    );
  }
}
