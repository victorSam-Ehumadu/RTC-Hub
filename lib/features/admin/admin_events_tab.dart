import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/opportunity.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeleton.dart';

/// Institutional event management — §2.2.
///
/// *"The administrator is the only user type who can create, edit, and
/// publish official Richfield institutional events (career fairs, workshops,
/// networking events). These events appear in the event listings visible to
/// all users."*
///
/// The events table, the students' events feed and the notification trigger
/// all existed; there was simply no way to make an event except by hand in
/// SQL. There is no separate "publish" action because there is no draft
/// state: `trg_event_notify` (0009) fans the announcement out to the
/// matching audience the moment the row lands, so creating *is* publishing.
/// The form says so rather than leaving an administrator to discover it by
/// notifying four hundred people with a half-finished title.
class AdminEventsTab extends ConsumerWidget {
  const AdminEventsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(allEventsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New event'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(allEventsProvider),
        child: events.when(
          loading: () => const TileListSkeleton(count: 4, hasAvatar: false),
          error: (err, _) => ErrorView(
            error: err,
            onRetry: () => ref.invalidate(allEventsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.55,
                    child: const EmptyState(
                      icon: Icons.event_outlined,
                      title: 'No events yet',
                      message: 'Career fairs, workshops and networking '
                          'evenings show up in every student’s events '
                          'feed.',
                    ),
                  ),
                ],
              );
            }

            final upcoming = list.where((e) => !e.isPast).toList()
              ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
            final past = list.where((e) => e.isPast).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
              children: [
                if (upcoming.isNotEmpty) ...[
                  SectionHeader(title: 'Upcoming (${upcoming.length})'),
                  for (final e in upcoming)
                    _EventCard(
                      event: e,
                      onEdit: () => _edit(context, ref, e),
                      onDelete: () => _delete(context, ref, e),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  SectionHeader(title: 'Past (${past.length})'),
                  for (final e in past)
                    _EventCard(
                      event: e,
                      past: true,
                      onEdit: () => _edit(context, ref, e),
                      onDelete: () => _delete(context, ref, e),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CampusEvent? existing,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _EventForm(existing: existing),
    );
    if (saved != true) return;
    ref
      ..invalidate(allEventsProvider)
      ..invalidate(upcomingEventsProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CampusEvent event,
  ) async {
    final gone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this event?'),
        content: Text(
          event.isPast
              ? 'It has already happened, so nobody will be surprised.'
              : 'Anyone who was notified will not be told it was cancelled. '
                  'Consider editing it to say so instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (gone != true) return;

    try {
      await ref.read(eventRepoProvider).remove(event.id);
      ref
        ..invalidate(allEventsProvider)
        ..invalidate(upcomingEventsProvider);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onEdit,
    required this.onDelete,
    this.past = false,
  });

  final CampusEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Opacity(
      opacity: past ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Text(
                    _month(event.eventDate.month),
                    style: monoStyle(
                      size: 10,
                      weight: FontWeight.w700,
                      color: AppColors.points,
                    ),
                  ),
                  Text(
                    '${event.eventDate.day}',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        _time(event.eventDate),
                        if (event.location != null) event.location!,
                        if (event.isVirtual) 'online',
                      ].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (event.faculty != null ||
                        event.targetRoles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (event.faculty != null)
                            FacultyChip(faculty: event.faculty, compact: true),
                          for (final r in event.targetRoles)
                            TagChip(label: r, color: roleColor(r)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Event options',
                icon: Icon(Icons.more_vert, size: 18, color: muted),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _month(int m) => const [
        'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
        'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
      ][m - 1];

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class _EventForm extends ConsumerStatefulWidget {
  const _EventForm({this.existing});

  final CampusEvent? existing;

  @override
  ConsumerState<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends ConsumerState<_EventForm> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late final _link =
      TextEditingController(text: widget.existing?.virtualLink ?? '');

  late DateTime _when = widget.existing?.eventDate ??
      DateTime.now().add(const Duration(days: 7));
  late String? _faculty = widget.existing?.faculty;
  late final Set<String> _roles = {...?widget.existing?.targetRoles};
  bool _busy = false;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted) return;

    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showMessage(context, 'Give the event a name.');
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(eventRepoProvider);
      final roles = _roles.isEmpty ? null : _roles.toList();

      if (_isNew) {
        await repo.create(
          title: _title.text,
          eventDate: _when,
          description: _text(_description),
          location: _text(_location),
          virtualLink: _text(_link),
          targetRoles: roles,
          faculty: _faculty,
        );
      } else {
        await repo.update(
          widget.existing!.id,
          title: _title.text,
          eventDate: _when,
          description: _text(_description),
          location: _text(_location),
          virtualLink: _text(_link),
          targetRoles: roles,
          faculty: _faculty,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isNew ? 'New institutional event' : 'Edit event',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (_isNew) ...[
              const SizedBox(height: 6),
              Text(
                'Everyone in the audience you pick is notified as soon as you '
                'save. There is no draft.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Autumn Career Fair',
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickWhen,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'When'),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 17),
                    const SizedBox(width: 10),
                    Text(
                      '${_when.day}/${_when.month}/${_when.year} at '
                      '${_when.hour.toString().padLeft(2, '0')}:'
                      '${_when.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _location,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Where',
                hintText: 'Braamfontein campus, Hall B',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Online link',
                hintText: 'https://teams.microsoft.com/…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Details'),
            ),

            const SectionHeader(title: 'Who sees it'),
            Text(
              'Leave both open to reach everyone. Narrowing the audience also '
              'narrows who gets notified.',
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _faculty,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Faculty'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Both')),
                for (final f in kFaculties)
                  DropdownMenuItem(value: f.code, child: Text(f.name)),
              ],
              onChanged: (v) => setState(() => _faculty = v),
            ),
            const SizedBox(height: 8),
            for (final role in const ['STUDENT', 'ALUMNI', 'BUSINESS'])
              CheckboxListTile(
                value: _roles.contains(role),
                onChanged: (on) => setState(() {
                  on == true ? _roles.add(role) : _roles.remove(role);
                }),
                title: Text(
                  role[0] + role.substring(1).toLowerCase(),
                  style: const TextStyle(fontSize: 13.5),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            if (_roles.isEmpty)
              Text(
                'No roles ticked — everyone sees it.',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),

            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isNew ? Icons.campaign_outlined : Icons.check,
                      size: 18),
              label: Text(
                _busy
                    ? 'Saving…'
                    : _isNew
                        ? 'Publish and notify'
                        : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
