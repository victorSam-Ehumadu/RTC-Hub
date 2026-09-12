import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/storage_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _headline = TextEditingController();
  final _website = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactPhone = TextEditingController();

  /// Per-section overrides. Absent key means visible, matching what
  /// `profile_for_viewer()` assumes — so a section added to the app
  /// later is not silently hidden for everyone who saved settings
  /// before it existed.
  Map<String, bool> _sections = {};

  final _fullName = TextEditingController();
  final _bio = TextEditingController();
  final _company = TextEditingController();
  final _industry = TextEditingController();
  final _location = TextEditingController();
  final _portfolio = TextEditingController();

  String? _faculty;
  String? _course;
  String? _year;
  String? _avatarUrl;
  bool _visibleToBusiness = true;
  bool _visibleToPeers = true;

  bool _loaded = false;
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _headline.dispose();
    _website.dispose();
    _contactEmail.dispose();
    _contactPhone.dispose();
    _fullName.dispose();
    _bio.dispose();
    _company.dispose();
    _industry.dispose();
    _location.dispose();
    _portfolio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final url = await ref
          .read(storageRepoProvider)
          .upload(File(picked.path), bucket: StorageRepository.avatars);
      setState(() => _avatarUrl = url);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final me = ref.read(meProvider);
    if (me == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(profileRepoProvider).update(
            me.copyWith(
              fullName: _fullName.text.trim(),
              bio: _bio.text.trim(),
              avatarUrl: _avatarUrl,
              faculty: _faculty,
              course: _course,
              academicYear: _year,
              companyName: _company.text.trim(),
              industry: _industry.text.trim(),
              companyLocation: _location.text.trim(),
              portfolioUrl:
                  _portfolio.text.trim().isEmpty ? null : _portfolio.text.trim(),
              visibilityBusiness: _visibleToBusiness,
              visibilityPeers: _visibleToPeers,
              sectionVisibility: _sections,
              headline: _headline.text.trim().isEmpty
                  ? null
                  : _headline.text.trim(),
              websiteUrl:
                  _website.text.trim().isEmpty ? null : _website.text.trim(),
              contactEmail: _contactEmail.text.trim().isEmpty
                  ? null
                  : _contactEmail.text.trim(),
              contactPhone: _contactPhone.text.trim().isEmpty
                  ? null
                  : _contactPhone.text.trim(),
            ),
          );
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      context.pop();
      showMessage(context, 'Profile saved.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    if (me == null) return const Scaffold(body: Loading());

    if (!_loaded) {
      _loaded = true;
      _fullName.text = me.fullName;
      _bio.text = me.bio ?? '';
      _company.text = me.companyName ?? '';
      _industry.text = me.industry ?? '';
      _location.text = me.companyLocation ?? '';
      _portfolio.text = me.portfolioUrl ?? '';
      // Guard against stored values that no longer exist in kFaculties /
      // kAcademicYears (e.g. data from before a constants.dart edit, or a
      // profile written outside the app) — DropdownButtonFormField asserts
      // if its value doesn't match exactly one item, so anything unknown is
      // dropped back to null rather than crashing the screen.
      _faculty = kFaculties.any((f) => f.code == me.faculty) ? me.faculty : null;
      _course =
          coursesForFaculty(_faculty).contains(me.course) ? me.course : null;
      _year = kAcademicYears.contains(me.academicYear) ? me.academicYear : null;
      _avatarUrl = me.avatarUrl;
      _visibleToBusiness = me.visibilityBusiness;
      _visibleToPeers = me.visibilityPeers;
      _sections = Map<String, bool>.from(me.sectionVisibility);
      _headline.text = me.headline ?? '';
      _website.text = me.websiteUrl ?? '';
      _contactEmail.text = me.contactEmail ?? '';
      _contactPhone.text = me.contactPhone ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const DottedProgressIndicator(size: 16)
                : const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Center(
            child: Stack(
              children: [
                Avatar(
                  profile: me.copyWith(avatarUrl: _avatarUrl),
                  radius: 44,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: AppColors.button,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _uploading ? null : _pickAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: _uploading
                            ? const DottedProgressIndicator(
                                size: 15,
                                color: Colors.white,
                              )
                            : const Icon(Icons.camera_alt,
                                size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SectionHeader(title: 'About you'),
          TextField(
            controller: _fullName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bio,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Bio',
              hintText: 'What you work on, what you want to build next.',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _portfolio,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Portfolio / GitHub URL',
              prefixIcon: Icon(Icons.link, size: 20),
            ),
          ),

          if (me.isStudent || me.isAlumni) ...[
            const SectionHeader(title: 'Studies'),
            DropdownButtonFormField<String>(
              initialValue: _faculty,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Faculty'),
              items: [
                for (final f in kFaculties)
                  DropdownMenuItem(value: f.code, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() {
                _faculty = v;
                _course = null;
              }),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _course,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Course'),
              items: [
                for (final c in coursesForFaculty(_faculty))
                  DropdownMenuItem(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _course = v),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _year,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Year'),
              items: [
                for (final y in kAcademicYears)
                  DropdownMenuItem(value: y, child: Text(y)),
              ],
              onChanged: (v) => setState(() => _year = v),
            ),
          ],

          if (me.isBusiness) ...[
            const SectionHeader(title: 'Company'),
            TextField(
              controller: _company,
              decoration: const InputDecoration(labelText: 'Company name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _industry,
              decoration: const InputDecoration(labelText: 'Industry'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
          ],

          const SectionHeader(title: 'Headline'),
          TextFormField(
            controller: _headline,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 90,
            decoration: const InputDecoration(
              hintText: '3rd year BSc IT, looking for an internship',
              counterText: '',
            ),
          ),

          const SectionHeader(title: 'Contact'),
          TextFormField(
            controller: _contactEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Contact email'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Website',
              hintText: 'https://',
            ),
          ),

          const SectionHeader(title: 'What others can see'),
          Text(
            'Hidden sections are removed before your profile leaves the '
            'server, so they are not simply hidden on someone else\'s screen.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          for (final section in _kSections)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sections[section.key] ?? true,
              onChanged: (on) => setState(() => _sections[section.key] = on),
              title: Text(section.label),
              subtitle: Text(
                section.hint,
                style: const TextStyle(fontSize: 11.5),
              ),
              secondary: Icon(section.icon),
            ),

          const SectionHeader(title: 'Who can see you'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _visibleToPeers,
            onChanged: (v) => setState(() => _visibleToPeers = v),
            title: const Text('Students and alumni'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _visibleToBusiness,
            onChanged: (v) => setState(() => _visibleToBusiness = v),
            title: const Text('Businesses and recruiters'),
            subtitle: const Text(
              'Turning this off hides you from opportunity searches.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sections a user can hide, and what hiding one actually costs them.
///
/// The keys match what `profile_for_viewer()` strips in migration 0011 —
/// change one and the other stops working, so they are listed together here
/// rather than scattered through the widget tree.
class _SectionToggle {
  const _SectionToggle(this.key, this.label, this.hint, this.icon);

  final String key;
  final String label;
  final String hint;
  final IconData icon;
}

const _kSections = <_SectionToggle>[
  _SectionToggle('contact', 'Contact details',
      'Email and phone. Businesses use these to reach you.', Icons.mail_outline),
  _SectionToggle('cv', 'CV',
      'Hiding it means recruiters cannot open your CV.', Icons.description_outlined),
  _SectionToggle('portfolio', 'Portfolio link', 'Your personal site or GitHub.',
      Icons.link),
  _SectionToggle('bio', 'About and headline', 'Your written introduction.',
      Icons.notes_outlined),
  _SectionToggle('studies', 'Course and year',
      'Course, academic year and graduation year.', Icons.school_outlined),
];
