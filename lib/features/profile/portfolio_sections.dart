import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../core/theme.dart';
import '../../models/portfolio.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// The §2.3 portfolio sections: projects, deployed apps, badges,
/// certifications, achievements, leadership and activities.
///
/// One widget for all seven because they are the same interaction — a list
/// the owner adds to and removes from, and everyone else reads. Building
/// seven near-identical screens would mean seven places to fix the next bug.
class PortfolioSections extends ConsumerWidget {
  const PortfolioSections({
    super.key,
    required this.userId,
    required this.isSelf,
  });

  final String userId;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ItemSection(
          userId: userId,
          isSelf: isSelf,
          kind: 'REPO',
          title: 'GitHub projects',
          icon: Icons.folder_outlined,
          emptySelf: 'Link the repositories you are proudest of.',
        ),
        _ItemSection(
          userId: userId,
          isSelf: isSelf,
          kind: 'LIVE_APP',
          title: 'Live apps and sites',
          icon: Icons.public,
          emptySelf: 'Anything you have deployed — a URL a recruiter can open.',
        ),
        _CredentialSection(
          userId: userId,
          isSelf: isSelf,
          kind: 'CERTIFICATION',
          title: 'Certifications',
          icon: Icons.workspace_premium_outlined,
        ),
        _CredentialSection(
          userId: userId,
          isSelf: isSelf,
          kind: 'BADGE',
          title: 'Digital badges',
          icon: Icons.military_tech_outlined,
        ),
        for (final kind in const ['ACHIEVEMENT', 'LEADERSHIP', 'ACTIVITY'])
          _HighlightSection(userId: userId, isSelf: isSelf, kind: kind),
      ],
    );
  }
}

// ─── Projects and deployed apps ───────────────────────────────

class _ItemSection extends ConsumerWidget {
  const _ItemSection({
    required this.userId,
    required this.isSelf,
    required this.kind,
    required this.title,
    required this.icon,
    required this.emptySelf,
  });

  final String userId;
  final bool isSelf;
  final String kind;
  final String title;
  final IconData icon;
  final String emptySelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$userId|$kind';
    final items = ref.watch(portfolioItemsProvider(key));

    return items.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        // Someone else's empty section is noise; your own is a prompt.
        if (list.isEmpty && !isSelf) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '$title (${list.length})',
              action: isSelf
                  ? TextButton(
                      onPressed: () => _add(context, ref, key),
                      child: const Text('Add'),
                    )
                  : null,
            ),
            if (list.isEmpty)
              _EmptyHint(text: emptySelf)
            else
              for (final item in list)
                _LinkCard(
                  icon: icon,
                  title: item.title,
                  subtitle: item.description,
                  url: item.url,
                  tags: item.tech,
                  onDelete: isSelf
                      ? () async {
                          await ref
                              .read(portfolioRepoProvider)
                              .removeItem(item.id);
                          ref.invalidate(portfolioItemsProvider(key));
                        }
                      : null,
                ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String key) async {
    final result = await showModalBottomSheet<PortfolioItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _ItemForm(kind: kind, heading: title),
    );
    if (result == null) return;
    try {
      await ref.read(portfolioRepoProvider).addItem(result);
      ref.invalidate(portfolioItemsProvider(key));
      ref.invalidate(myProfileProvider);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.kind, required this.heading});

  final String kind;
  final String heading;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  final _description = TextEditingController();
  final _tech = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _description.dispose();
    _tech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      heading: 'Add to ${widget.heading.toLowerCase()}',
      canSave: _title.text.trim().isNotEmpty && _url.text.trim().isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        PortfolioItem(
          id: '',
          userId: '',
          kind: widget.kind,
          title: _title.text,
          url: _url.text,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          tech: _tech.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList(),
        ),
      ),
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Link',
            hintText: widget.kind == 'REPO'
                ? 'https://github.com/you/project'
                : 'https://yourapp.co.za',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What is it?',
            hintText: 'One or two lines',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tech,
          decoration: const InputDecoration(
            labelText: 'Built with',
            hintText: 'Flutter, Postgres, Firebase',
            helperText: 'Comma separated',
          ),
        ),
      ],
    );
  }
}

// ─── Badges and certifications ────────────────────────────────

class _CredentialSection extends ConsumerWidget {
  const _CredentialSection({
    required this.userId,
    required this.isSelf,
    required this.kind,
    required this.title,
    required this.icon,
  });

  final String userId;
  final bool isSelf;
  final String kind;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$userId|$kind';
    final creds = ref.watch(credentialsProvider(key));

    return creds.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty && !isSelf) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '$title (${list.length})',
              action: isSelf
                  ? TextButton(
                      onPressed: () => _add(context, ref, key),
                      child: const Text('Add'),
                    )
                  : null,
            ),
            if (list.isEmpty)
              _EmptyHint(
                text: kind == 'BADGE'
                    ? 'Credly badges and similar. Add your Credly profile '
                        'link in Edit profile too.'
                    : 'AWS, Azure, Cisco, Scrum — anything you have earned.',
              )
            else
              for (final c in list)
                _LinkCard(
                  icon: icon,
                  title: c.title,
                  subtitle: [
                    if (c.issuer != null) c.issuer!,
                    if (c.issuedOn != null) '${c.issuedOn!.year}',
                    if (c.hasExpired) 'expired',
                  ].join(' · '),
                  url: c.url,
                  dimmed: c.hasExpired,
                  onDelete: isSelf
                      ? () async {
                          await ref
                              .read(portfolioRepoProvider)
                              .removeCredential(c.id);
                          ref.invalidate(credentialsProvider(key));
                        }
                      : null,
                ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String key) async {
    final result = await showModalBottomSheet<Credential>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CredentialForm(kind: kind, heading: title),
    );
    if (result == null) return;
    try {
      await ref.read(portfolioRepoProvider).addCredential(result);
      ref.invalidate(credentialsProvider(key));
      ref.invalidate(myProfileProvider);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _CredentialForm extends StatefulWidget {
  const _CredentialForm({required this.kind, required this.heading});

  final String kind;
  final String heading;

  @override
  State<_CredentialForm> createState() => _CredentialFormState();
}

class _CredentialFormState extends State<_CredentialForm> {
  final _title = TextEditingController();
  final _issuer = TextEditingController();
  final _url = TextEditingController();
  int? _year;

  @override
  void dispose() {
    _title.dispose();
    _issuer.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thisYear = DateTime.now().year;

    return _SheetShell(
      heading: 'Add a ${widget.kind == 'BADGE' ? 'badge' : 'certification'}',
      canSave: _title.text.trim().isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        Credential(
          id: '',
          userId: '',
          kind: widget.kind,
          title: _title.text,
          issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
          issuedOn: _year == null ? null : DateTime(_year!, 1, 1),
          url: _url.text.trim().isEmpty ? null : _url.text.trim(),
        ),
      ),
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'AWS Certified Cloud Practitioner',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _issuer,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Issued by',
            hintText: 'Amazon Web Services',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _year,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Year earned'),
          items: [
            for (var y = thisYear; y >= thisYear - 20; y--)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) => setState(() => _year = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Verification link',
            hintText: 'https://credly.com/badges/…',
          ),
        ),
      ],
    );
  }
}

// ─── Achievements, leadership, activities ─────────────────────

class _HighlightSection extends ConsumerWidget {
  const _HighlightSection({
    required this.userId,
    required this.isSelf,
    required this.kind,
  });

  final String userId;
  final bool isSelf;
  final String kind;

  IconData get _icon => switch (kind) {
        'LEADERSHIP' => Icons.groups_outlined,
        'ACTIVITY' => Icons.emoji_events_outlined,
        _ => Icons.school_outlined,
      };

  String get _hint => switch (kind) {
        'LEADERSHIP' => 'SRC, class representative, mentor, ambassador.',
        'ACTIVITY' =>
          'Clubs, societies, hackathons, competitions, volunteering.',
        _ => 'Awards, scholarships, deans list, academic recognition.',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = '$userId|$kind';
    final entries = ref.watch(highlightsProvider(key));

    return entries.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty && !isSelf) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '${ProfileHighlight.headingFor(kind)} (${list.length})',
              action: isSelf
                  ? TextButton(
                      onPressed: () => _add(context, ref, key),
                      child: const Text('Add'),
                    )
                  : null,
            ),
            if (list.isEmpty)
              _EmptyHint(text: _hint)
            else
              for (final h in list)
                _LinkCard(
                  icon: _icon,
                  title: h.title,
                  subtitle: [
                    if (h.organisation != null) h.organisation!,
                    if (h.startedOn != null) '${h.startedOn!.year}',
                  ].join(' · '),
                  body: h.description,
                  url: h.url,
                  onDelete: isSelf
                      ? () async {
                          await ref
                              .read(portfolioRepoProvider)
                              .removeHighlight(h.id);
                          ref.invalidate(highlightsProvider(key));
                        }
                      : null,
                ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, String key) async {
    final result = await showModalBottomSheet<ProfileHighlight>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _HighlightForm(kind: kind),
    );
    if (result == null) return;
    try {
      await ref.read(portfolioRepoProvider).addHighlight(result);
      ref.invalidate(highlightsProvider(key));
      ref.invalidate(myProfileProvider);
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }
}

class _HighlightForm extends StatefulWidget {
  const _HighlightForm({required this.kind});

  final String kind;

  @override
  State<_HighlightForm> createState() => _HighlightFormState();
}

class _HighlightFormState extends State<_HighlightForm> {
  final _title = TextEditingController();
  final _organisation = TextEditingController();
  final _description = TextEditingController();
  int? _year;

  @override
  void dispose() {
    _title.dispose();
    _organisation.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thisYear = DateTime.now().year;

    return _SheetShell(
      heading: 'Add to ${ProfileHighlight.headingFor(widget.kind).toLowerCase()}',
      canSave: _title.text.trim().isNotEmpty,
      onSave: () => Navigator.pop(
        context,
        ProfileHighlight(
          id: '',
          userId: '',
          kind: widget.kind,
          title: _title.text,
          organisation: _organisation.text.trim().isEmpty
              ? null
              : _organisation.text.trim(),
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          startedOn: _year == null ? null : DateTime(_year!, 1, 1),
        ),
      ),
      children: [
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'What was it?'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _organisation,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Where',
            hintText: 'Richfield, a club, a company',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _year,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Year'),
          items: [
            for (var y = thisYear; y >= thisYear - 15; y--)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) => setState(() => _year = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Details (optional)'),
        ),
      ],
    );
  }
}

// ─── Shared pieces ────────────────────────────────────────────

/// The bottom-sheet frame every form above uses.
///
/// `Navigator.pop` inside these forms uses the form's *own* context, which
/// is the fix the add-skill dialog needed: under StatefulShellRoute the
/// nearest Navigator to an outer context is not always the one the sheet was
/// pushed onto.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.heading,
    required this.children,
    required this.canSave,
    required this.onSave,
  });

  final String heading;
  final List<Widget> children;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
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
              heading,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 18),
            FilledButton(
              onPressed: canSave ? onSave : null,
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
}

/// One portfolio row. Tapping opens the link; the owner gets a delete.
class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.body,
    this.url,
    this.tags = const [],
    this.onDelete,
    this.dimmed = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? body;
  final String? url;
  final List<String> tags;
  final VoidCallback? onDelete;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final hasUrl = url != null && url!.trim().isNotEmpty;

    return Opacity(
      opacity: dimmed ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasUrl
              ? () async {
                  final ok = await launchUrlString(
                    url!,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && context.mounted) {
                    showMessage(context, 'Could not open that link.');
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: muted),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(fontSize: 11.5, color: muted)),
                      ],
                      if (body != null && body!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(body!,
                            style:
                                const TextStyle(fontSize: 12.5, height: 1.4)),
                      ],
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final t in tags)
                              TagChip(label: t, color: AppColors.accent),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasUrl)
                  Icon(Icons.open_in_new, size: 14, color: muted),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    icon: Icon(Icons.close, color: muted),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
