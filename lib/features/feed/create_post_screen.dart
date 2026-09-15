import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/storage_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Composer for a normal post or a bounty.
///
/// The bounty value is not settable here on purpose: `trg_posts_guard` sets every
/// new bounty to 10 points, and `escalate_bounties()` raises unsolved ones
/// over time, so there is nothing for the client to decide.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.asBounty = false});

  final bool asBounty;

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _content = TextEditingController();
  final _code = TextEditingController();
  final _module = TextEditingController();

  late bool _isBounty = widget.asBounty;
  bool _attachCode = false;
  String _language = 'dart';
  bool _busy = false;
  bool _uploadingAttachments = false;

  // Attachment tracking: stores file paths and uploaded URLs
  final List<File> _attachedFiles = [];
  final List<String> _uploadedFileUrls = [];
  final List<File> _attachedImages = [];
  final List<String> _uploadedImageUrls = [];

  @override
  void dispose() {
    _content.dispose();
    _code.dispose();
    _module.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (images.isEmpty) return;
    setState(() => _attachedImages.addAll(images.map((i) => File(i.path))));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      onFileLoading: (status) => setState(() => _uploadingAttachments = true),
    );
    if (result?.files.isEmpty ?? true) return;
    setState(() {
      _attachedFiles.addAll(result!.files.map((f) => File(f.path!)));
      _uploadingAttachments = false;
    });
  }

  Future<void> _uploadAttachments() async {
    if (_attachedFiles.isEmpty && _attachedImages.isEmpty) return;

    setState(() => _uploadingAttachments = true);
    try {
      final storage = ref.read(storageRepoProvider);

      // Upload images
      for (final image in _attachedImages) {
        final url = await storage.upload(
          image,
          bucket: StorageRepository.postAttachments,
        );
        _uploadedImageUrls.add(url);
      }

      // Upload files
      for (final file in _attachedFiles) {
        final url = await storage.upload(
          file,
          bucket: StorageRepository.postAttachments,
        );
        _uploadedFileUrls.add(url);
      }
    } catch (error) {
      if (mounted) showError(context, error);
      rethrow;
    } finally {
      if (mounted) setState(() => _uploadingAttachments = false);
    }
  }

  Future<void> _submit() async {
    if (_content.text.trim().isEmpty) {
      showMessage(context, 'Write something first.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Upload attachments first
      await _uploadAttachments();

      // Combine all attachment URLs
      final allAttachments = [..._uploadedImageUrls, ..._uploadedFileUrls];

      await ref.read(postRepoProvider).create(
            content: _content.text,
            type: _isBounty
                ? 'BOUNTY'
                : (_attachCode ? 'CODE' : 'TEXT'),
            codeLanguage: _attachCode ? _language : null,
            codeSnippet: _attachCode && _code.text.trim().isNotEmpty
                ? _code.text
                : null,
            isBounty: _isBounty,
            bountyModule: _isBounty && _module.text.trim().isNotEmpty
                ? _module.text.trim()
                : null,
            attachmentUrls: allAttachments.isNotEmpty ? allAttachments : null,
          );

      ref.invalidate(feedProvider);
      ref.invalidate(bountiesProvider);

      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        _isBounty ? 'Bounty posted — 10 LP on offer.' : 'Posted.',
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isBounty ? 'Post a bounty' : 'New post'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const DottedProgressIndicator(size: 16)
                : const Text('Post'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isBounty,
              onChanged: (v) => setState(() {
                _isBounty = v;
                if (v) _attachCode = true;
              }),
              title: const Text('Ask as a bounty'),
              subtitle: Text(
                'Offers 10 Logic Points to whoever solves it. You pick the '
                'accepted answer.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
              secondary: const Icon(Icons.bolt, color: AppColors.points),
            ),
            const Divider(height: 24),

            TextField(
              controller: _content,
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isBounty
                    ? 'What are you stuck on? Describe what you expected and '
                        'what actually happened.'
                    : 'Share what you are building…',
              ),
            ),

            if (_isBounty) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _module,
                decoration: const InputDecoration(
                  labelText: 'Module (optional)',
                  hintText: 'e.g. Advanced Java',
                  prefixIcon: Icon(Icons.school_outlined, size: 20),
                ),
              ),
            ],

            const SectionHeader(title: 'Code'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _attachCode,
              onChanged: (v) => setState(() => _attachCode = v),
              title: const Text('Attach a snippet'),
              secondary: const Icon(Icons.code),
            ),

            if (_attachCode) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: [
                  for (final lang in kCodeLanguages)
                    DropdownMenuItem(value: lang, child: Text(lang)),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'dart'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                maxLines: 14,
                minLines: 6,
                style: monoStyle(size: 13),
                decoration: const InputDecoration(
                  hintText: 'Paste your code here',
                  alignLabelWithHint: true,
                ),
              ),
            ],

            const SizedBox(height: 24),
            const SectionHeader(title: 'Attachments'),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _uploadingAttachments ? null : _pickImages,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Add Images'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _uploadingAttachments ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Add Files'),
                ),
              ],
            ),

            // Display selected images
            if (_attachedImages.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Images (${_attachedImages.length})',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int index = 0; index < _attachedImages.length; index++)
                    Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: FileImage(_attachedImages[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => setState(
                              () => _attachedImages.removeAt(index),
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black87,
                              ),
                              padding: const EdgeInsets.all(2),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],

            // Display selected files
            if (_attachedFiles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Files (${_attachedFiles.length})',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 8),
              ...List.generate(
                _attachedFiles.length,
                (index) {
                  final fileName = _attachedFiles[index].path.split('/').last;
                  return Padding(
                    padding: EdgeInsets.only(bottom: index < _attachedFiles.length - 1 ? 4 : 0),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.attach_file, size: 20),
                        title: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () =>
                              setState(() => _attachedFiles.removeAt(index)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],

            if (_uploadingAttachments) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Uploading attachments...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
