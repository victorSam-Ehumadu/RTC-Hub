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
  final _fullName = TextEditingController();
  final _bio = TextEditingController();
  final _studentInvolvement = TextEditingController();
  final _company = TextEditingController();
  final _industry = TextEditingController();
  final _location = TextEditingController();
  final _portfolio = TextEditingController();
  final _linkedinUrl = TextEditingController();
  final _credlyUrl = TextEditingController();

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
    _fullName.dispose();
    _bio.dispose();
    _studentInvolvement.dispose();
    _company.dispose();
    _industry.dispose();
    _location.dispose();
    _portfolio.dispose();
    _linkedinUrl.dispose();
    _credlyUrl.dispose();
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
              studentInvolvement: _studentInvolvement.text.trim(),
              avatarUrl: _avatarUrl,
              faculty: _faculty,
              course: _course,
              academicYear: _year,
              companyName: _company.text.trim(),
              industry: _industry.text.trim(),
              companyLocation: _location.text.trim(),
              portfolioUrl:
                  _portfolio.text.trim().isEmpty ? null : _portfolio.text.trim(),
              linkedinUrl: _linkedinUrl.text.trim().isEmpty ? null : _linkedinUrl.text.trim(),
              credlyUrl: _credlyUrl.text.trim().isEmpty ? null : _credlyUrl.text.trim(),
              visibilityBusiness: _visibleToBusiness,
              visibilityPeers: _visibleToPeers,
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
      // TODO: Pre-fill with AI assistant during onboarding flow (§2.6)
      _studentInvolvement.text = me.studentInvolvement ?? '';
      _company.text = me.companyName ?? '';
      _industry.text = me.industry ?? '';
      _location.text = me.companyLocation ?? '';
      _portfolio.text = me.portfolioUrl ?? '';
      _linkedinUrl.text = me.linkedinUrl ?? '';
      _credlyUrl.text = me.credlyUrl ?? '';
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
            controller: _studentInvolvement,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Involvement',
              hintText: 'Club activities, volunteer work, competitions, community involvement.',
            ),
          ),
          const SizedBox(height: 14),
          const SectionHeader(title: 'Portfolio & Links'),
          TextField(
            controller: _portfolio,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Portfolio / GitHub URL',
              prefixIcon: Icon(Icons.link, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _linkedinUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'LinkedIn Profile',
              prefixIcon: Icon(Icons.work_outline, size: 20),
              hintText: 'https://linkedin.com/in/yourprofile',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _credlyUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Credly Badge Collection',
              prefixIcon: Icon(Icons.verified_user_outlined, size: 20),
              hintText: 'https://www.credly.com/users/yourprofile',
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
