import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

class CreateOpportunityScreen extends ConsumerStatefulWidget {
  const CreateOpportunityScreen({super.key});

  @override
  ConsumerState<CreateOpportunityScreen> createState() =>
      _CreateOpportunityScreenState();
}

class _CreateOpportunityScreenState
    extends ConsumerState<CreateOpportunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _skills = TextEditingController();

  String _type = 'INTERNSHIP';
  String? _faculty;
  String? _year;
  bool _remote = false;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _skills.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await ref.read(opportunityRepoProvider).create(
            title: _title.text,
            description: _description.text,
            type: _type,
            location: _location.text.trim().isEmpty ? null : _location.text.trim(),
            remote: _remote,
            requiredSkills: _skills.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            requiredFaculty: _faculty,
            requiredYear: _year,
          );
      ref.invalidate(myOpportunitiesProvider);
      if (!mounted) return;
      context.pop();
      showMessage(
        context,
        'Submitted. An administrator will review it before students see it.',
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
        title: const Text('Post an opportunity'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const DottedProgressIndicator(size: 16)
                : const Text('Submit'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Role title',
                hintText: 'e.g. Junior Flutter Developer',
              ),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? 'Give the role a title'
                  : null,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final t in kOpportunityTypes)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t.replaceAll('_', ' ').toLowerCase()),
                  ),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'INTERNSHIP'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 7,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What the person will do, and what you expect.',
                alignLabelWithHint: true,
              ),
              validator: (v) => (v == null || v.trim().length < 20)
                  ? 'Describe the role in a little more detail'
                  : null,
            ),

            const SectionHeader(title: 'Where'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remote,
              onChanged: (v) => setState(() => _remote = v),
              title: const Text('Remote'),
            ),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. Johannesburg',
              ),
            ),

            const SectionHeader(title: 'Who it is for'),
            Text(
              'Used to rank this against student profiles.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skills,
              decoration: const InputDecoration(
                labelText: 'Required skills',
                hintText: 'Comma separated — Dart, SQL, Git',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _faculty,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Faculty (optional)',
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any faculty')),
                for (final f in kFaculties)
                  DropdownMenuItem(value: f.code, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => _faculty = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Year (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any year')),
                for (final y in kAcademicYears)
                  DropdownMenuItem(value: y, child: Text(y)),
              ],
              onChanged: (v) => setState(() => _year = v),
            ),
          ],
        ),
      ),
    );
  }
}
