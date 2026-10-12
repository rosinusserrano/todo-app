// Collections: a workspace's tables whose fields are decided first - recipes
// (name, link), movies (title, year, seen). See *Collections* in ROADMAP.md.
//
// One view with two rungs, the way the journal has its ladder: the list of the
// workspace's collections, and one collection's entries. Esc walks back from
// the second to the first before the shell gets it and closes the view, which
// is why the pane holds a FocusNode of its own (see JournalView for why a
// pane with no text field in focus needs one to be on the key path at all).
//
// Three things are load-bearing:
//
//   - **The entry form is typed straight through.** Enter jumps to the next
//     *typed* field - a checkbox is a tap, and putting the caret on one would
//     only put a phone's keyboard away - and Enter on the last one adds the
//     entry and starts the next with the caret back in the first field. That
//     is the whole reason this is a form and not a row of cells: five movies
//     in a row is five lines of typing.
//   - **A field's kind is an input hint, not a storage format.** Every value
//     is text. The kind decides the keyboard, how the value is drawn and how
//     it sorts; changing it loses nothing.
//   - **Table or rows is decided by the width the view got**, not by platform:
//     a column per field needs room for a column per field. Below that, the
//     first typed field is the row's name and the rest is one muted line.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart' show FieldDraft;
import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'form_sheet.dart';
import 'list_rule.dart';
import 'panel_header.dart';

/// The width a typed column needs before the table is worth drawing.
const kCollectionColumn = 160.0;

/// A checkbox column: a tick and its header.
const kCollectionCheckColumn = 72.0;

/// A number column: a year, a price, a rating. Right-aligned, so it ends a
/// gap short of whatever column comes next.
const kCollectionNumberColumn = 96.0;

/// How wide a field's column is when it has a fixed width at all. Text and
/// links share what is left.
double? fixedColumnWidth(FieldKind kind) => switch (kind) {
  FieldKind.check => kCollectionCheckColumn,
  FieldKind.number => kCollectionNumberColumn,
  _ => null,
};

typedef SaveCollection =
    Future<Collection?> Function(
      Collection? existing,
      String name,
      List<FieldDraft> fields,
    );

typedef SaveEntry =
    Future<CollectionEntry?> Function(
      Collection collection,
      Map<String, String> values,
      CollectionEntry? existing,
    );

class CollectionsView extends StatefulWidget {
  const CollectionsView({
    super.key,
    required this.collections,
    required this.fields,
    required this.entries,
    required this.accent,
    required this.onSaveCollection,
    required this.onDeleteCollection,
    required this.onSaveEntry,
    required this.onDeleteEntry,
    required this.onSetChecked,
    this.onBack,
  });

  final List<Collection> collections;
  final Map<String, List<CollectionField>> fields;
  final Map<String, List<CollectionEntry>> entries;

  /// The workspace's colour: collections are the workspace's.
  final Color accent;

  final SaveCollection onSaveCollection;
  final Future<void> Function(Collection) onDeleteCollection;
  final SaveEntry onSaveEntry;
  final Future<void> Function(CollectionEntry) onDeleteEntry;
  final Future<void> Function(CollectionEntry, CollectionField, bool)
  onSetChecked;

  /// Back to the task list, from the list of collections.
  final VoidCallback? onBack;

  @override
  State<CollectionsView> createState() => _CollectionsViewState();
}

class _CollectionsViewState extends State<CollectionsView> {
  final _paneFocus = FocusNode(debugLabel: 'collections pane');
  final _search = TextEditingController();

  /// The collection on screen, or null for the list of them. A uuid rather
  /// than the row: the lists are reloaded under this constantly, and a held
  /// row would be a copy that went stale.
  String? _openUuid;

  /// The field the entries are sorted on; null is the order they were added.
  String? _sortField;
  bool _sortDescending = false;

  @override
  void dispose() {
    _paneFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  Collection? get _open {
    for (final c in widget.collections) {
      if (c.uuid == _openUuid) return c;
    }
    return null;
  }

  void _openCollection(Collection c) {
    setState(() {
      _openUuid = c.uuid;
      _search.clear();
      _sortField = null;
      _sortDescending = false;
    });
    // Onto the pane, so Esc reaches this view's ladder before the shell.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _paneFocus.requestFocus();
    });
  }

  void _closeCollection() => setState(() => _openUuid = null);

  // ----------------------------------------------------------------- forms

  Future<void> _editCollection(Collection? existing) async {
    final fields = existing == null
        ? const <CollectionField>[]
        : widget.fields[existing.uuid] ?? const <CollectionField>[];
    final entries = existing == null
        ? const <CollectionEntry>[]
        : widget.entries[existing.uuid] ?? const <CollectionEntry>[];
    final edit = await showCollectionForm(
      context,
      existing: existing,
      fields: fields,
      entries: entries,
      accent: widget.accent,
    );
    if (edit == null || !mounted) return;
    if (edit.delete) {
      if (existing != null) {
        await widget.onDeleteCollection(existing);
        if (mounted && _openUuid == existing.uuid) _closeCollection();
      }
      return;
    }
    final saved = await widget.onSaveCollection(
      existing,
      edit.name,
      edit.fields,
    );
    // A new collection opens: the next thing anyone does with one is fill it.
    if (existing == null && saved != null && mounted) _openCollection(saved);
  }

  Future<void> _editEntry(Collection c, CollectionEntry? existing) async {
    await showEntryForm(
      context,
      collection: c,
      fields: widget.fields[c.uuid] ?? const [],
      existing: existing,
      accent: widget.accent,
      onSave: (values, existing) => widget.onSaveEntry(c, values, existing),
      onDelete: widget.onDeleteEntry,
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return Focus(
      focusNode: _paneFocus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        // A search in progress is cleared first: it is the nearest thing
        // that Esc can mean.
        if (open != null && _search.text.isNotEmpty) {
          setState(_search.clear);
          return KeyEventResult.handled;
        }
        if (open != null) {
          _closeCollection();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: open == null ? _list() : _collection(open),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    final layout = Layout.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: SizedBox(
          width: layout.tapTarget,
          height: layout.tapTarget,
          child: Icon(icon, size: layout.actionIcon, color: T.muted),
        ),
      ),
    );
  }

  // ------------------------------------------------------- the collections

  Widget _list() {
    final all = widget.collections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: 'Collections',
          count: all.isEmpty ? null : all.length,
          onBack: widget.onBack,
          actions: [
            _iconButton(
              Icons.add_rounded,
              'New collection',
              () => _editCollection(null),
            ),
          ],
        ),
        Expanded(
          child: all.isEmpty
              ? _emptyList()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: T.s2),
                  itemCount: all.length,
                  itemBuilder: (context, i) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) const ListRule(),
                      _collectionRow(all[i]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyList() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Recipes, movies, books - anything you keep a list of with the '
            'same few details each time.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: T.fsLabel, color: T.muted, height: 1.4),
          ),
          const SizedBox(height: T.s3),
          FormSheet.saveButton(
            touch: Layout.of(context).touch,
            accent: widget.accent,
            label: 'New collection',
            onTap: () => _editCollection(null),
          ),
        ],
      ),
    ),
  );

  Widget _collectionRow(Collection c) {
    final fields = widget.fields[c.uuid] ?? const [];
    final count = widget.entries[c.uuid]?.length ?? 0;
    return InkWell(
      onTap: () => _openCollection(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: T.s3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: T.fsMenu,
                      fontFamily: T.fontDisplay,
                      fontWeight: T.wMedium,
                      color: T.text,
                    ),
                  ),
                  if (fields.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      fields.map((f) => f.name).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: T.fsMeta,
                        color: T.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: T.s2),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: T.fsMenu,
                fontFamily: T.fontDisplay,
                color: T.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- one collection

  Widget _collection(Collection c) {
    final fields = widget.fields[c.uuid] ?? const <CollectionField>[];
    final all = widget.entries[c.uuid] ?? const <CollectionEntry>[];
    final shown = sortEntries(
      filterEntries(all, fields, _search.text),
      fields,
      sortField: _sortField,
      descending: _sortDescending,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelHeader(
          title: c.name,
          color: widget.accent,
          count: all.isEmpty ? null : all.length,
          onBack: _closeCollection,
          backTooltip: 'Back to collections (Esc)',
          actions: [
            if (all.length > 1) _sortMenu(fields),
            _iconButton(
              Icons.tune_rounded,
              'Fields and name',
              () => _editCollection(c),
            ),
          ],
        ),
        _addPrompt(c),
        if (all.length > 1) _searchField(),
        Expanded(
          child: all.isEmpty
              ? const Center(
                  child: Text(
                    'Empty.',
                    style: TextStyle(color: T.muted, fontSize: T.fsLabel),
                  ),
                )
              : shown.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing matches.',
                    style: TextStyle(color: T.muted, fontSize: T.fsLabel),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) =>
                      fitsTable(fields, box.maxWidth - 2 * T.s4)
                      ? _table(c, fields, shown)
                      : _rows(c, fields, shown),
                ),
        ),
      ],
    );
  }

  /// The same line the task list opens its add field from, so the way in
  /// reads the same in both places.
  Widget _addPrompt(Collection c) => Padding(
    padding: const EdgeInsets.fromLTRB(T.s2, 0, T.s2, T.s1),
    child: Semantics(
      button: true,
      label: 'Add an entry',
      child: InkWell(
        onTap: () => _editEntry(c, null),
        borderRadius: BorderRadius.circular(T.radius),
        child: Padding(
          padding: const EdgeInsets.all(T.s2),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 16, color: widget.accent),
              const SizedBox(width: T.s2),
              const ExcludeSemantics(
                child: Text(
                  'Add an entry',
                  style: TextStyle(fontSize: T.fsBody, color: T.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s2),
    child: TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: T.fsBody),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search',
        prefixIcon: const Icon(Icons.search_rounded, size: 16, color: T.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 28),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 16),
                color: T.muted,
                onPressed: () => setState(_search.clear),
              ),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: T.s2),
      ),
    ),
  );

  /// Picking the field already sorted on turns it round; anything else sorts
  /// on it the natural way up.
  void _sortBy(String? field) => setState(() {
    if (field != null && field == _sortField) {
      _sortDescending = !_sortDescending;
    } else {
      _sortField = field;
      _sortDescending = false;
    }
  });

  Widget _sortMenu(List<CollectionField> fields) {
    final layout = Layout.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Sort',
      color: T.bgSolid,
      position: PopupMenuPosition.under,
      onSelected: (v) => _sortBy(v.isEmpty ? null : v),
      itemBuilder: (context) => [
        _sortItem('', 'Newest first', _sortField == null),
        for (final f in fields) _sortItem(f.uuid, f.name, _sortField == f.uuid),
      ],
      child: SizedBox(
        width: layout.tapTarget,
        height: layout.tapTarget,
        child: Icon(
          Icons.sort_rounded,
          size: layout.actionIcon,
          color: _sortField == null ? T.muted : widget.accent,
        ),
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label, bool on) =>
      PopupMenuItem<String>(
        value: value,
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: T.fsLabel,
                  color: on ? widget.accent : T.text,
                ),
              ),
            ),
            if (on && value.isNotEmpty)
              Icon(
                _sortDescending
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 14,
                color: widget.accent,
              ),
          ],
        ),
      );

  // ----------------------------------------------------------------- table

  Widget _table(
    Collection c,
    List<CollectionField> fields,
    List<CollectionEntry> shown,
  ) {
    Widget cellBox(CollectionField f, Widget child) {
      final width = fixedColumnWidth(f.kind);
      return width == null
          ? Expanded(child: child)
          : SizedBox(width: width, child: child);
    }

    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: T.s4),
      child: Row(
        children: [
          for (final f in fields)
            cellBox(
              f,
              InkWell(
                onTap: () => _sortBy(f.uuid),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    T.s1,
                    T.s2,
                    f.kind == FieldKind.number ? T.s4 : T.s1,
                    T.s2,
                  ),
                  child: Row(
                    mainAxisAlignment: f.kind == FieldKind.number
                        ? MainAxisAlignment.end
                        : f.kind == FieldKind.check
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: T.fsMeta,
                            fontWeight: T.wMedium,
                            color: _sortField == f.uuid
                                ? widget.accent
                                : T.muted,
                          ),
                        ),
                      ),
                      if (_sortField == f.uuid)
                        Icon(
                          _sortDescending
                              ? Icons.arrow_downward_rounded
                              : Icons.arrow_upward_rounded,
                          size: 12,
                          color: widget.accent,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const ListRule(),
        Expanded(
          child: ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final e = shown[i];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0) const ListRule(),
                  InkWell(
                    onTap: () => _editEntry(c, e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: T.s4,
                        vertical: T.s1,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Row(
                          children: [
                            for (final f in fields)
                              cellBox(f, _cell(e, f, first: f == fields.first)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cell(CollectionEntry e, CollectionField f, {required bool first}) {
    final value = e.valueOf(f.uuid);
    switch (f.kind) {
      case FieldKind.check:
        return Center(child: _tick(e, f));
      case FieldKind.link:
        return Align(
          alignment: Alignment.centerLeft,
          child: value.isEmpty ? const SizedBox() : _linkChip(value),
        );
      case FieldKind.number:
      case FieldKind.text:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            T.s1,
            0,
            f.kind == FieldKind.number ? T.s4 : T.s1,
            0,
          ),
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: f.kind == FieldKind.number
                ? TextAlign.right
                : TextAlign.left,
            style: TextStyle(
              fontSize: T.fsBody,
              color: first ? T.text : T.text.withValues(alpha: 0.85),
              fontFeatures: f.kind == FieldKind.number
                  ? const [FontFeature.tabularFigures()]
                  : null,
            ),
          ),
        );
    }
  }

  Widget _tick(CollectionEntry e, CollectionField f) {
    final on = e.isChecked(f.uuid);
    return Semantics(
      label: f.name,
      checked: on,
      child: InkWell(
        onTap: () => widget.onSetChecked(e, f, !on),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: Layout.of(context).tapTarget,
          height: Layout.of(context).tapTarget,
          child: Icon(
            on ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 20,
            color: on ? widget.accent : T.muted,
          ),
        ),
      ),
    );
  }

  /// A link is its own tap target, so opening it and editing the entry are
  /// never the same press.
  Widget _linkChip(String value) => Tooltip(
    message: value,
    child: InkWell(
      onTap: () => openCollectionLink(value),
      borderRadius: BorderRadius.circular(T.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s1, vertical: T.s1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                linkLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: T.fsBody, color: widget.accent),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.north_east_rounded, size: 12, color: widget.accent),
          ],
        ),
      ),
    ),
  );

  // ------------------------------------------------------------------ rows

  Widget _rows(
    Collection c,
    List<CollectionField> fields,
    List<CollectionEntry> shown,
  ) {
    final checks = [
      for (final f in fields)
        if (f.kind == FieldKind.check) f,
    ];
    final typed = [
      for (final f in fields)
        if (f.kind.typed) f,
    ];
    final lead = checks.isEmpty ? null : checks.first;
    final name = typed.isEmpty ? null : typed.first;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: T.s2),
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final e = shown[i];
        final title = name == null ? '' : e.valueOf(name.uuid);
        final link = [
          for (final f in typed)
            if (f.kind == FieldKind.link && e.valueOf(f.uuid).isNotEmpty)
              e.valueOf(f.uuid),
        ];
        final meta = [
          for (final f in typed.skip(1))
            if (e.valueOf(f.uuid).isNotEmpty)
              f.kind == FieldKind.link
                  ? linkLabel(e.valueOf(f.uuid))
                  : e.valueOf(f.uuid),
          for (final f in checks.skip(1))
            if (e.isChecked(f.uuid)) f.name,
        ];
        final ticked = lead != null && e.isChecked(lead.uuid);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) const ListRule(),
            InkWell(
              onTap: () => _editEntry(c, e),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  lead == null ? T.s2 : 0,
                  T.s2,
                  0,
                  T.s2,
                ),
                child: Row(
                  children: [
                    if (lead != null) _tick(e, lead),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isEmpty
                                ? 'Untitled'
                                : name!.kind == FieldKind.link
                                ? linkLabel(title)
                                : title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: T.fsBody,
                              color: title.isEmpty || ticked ? T.muted : T.text,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              meta.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: T.fsMeta,
                                color: T.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (link.isNotEmpty)
                      _iconButton(
                        Icons.north_east_rounded,
                        'Open ${linkLabel(link.first)}',
                        () => openCollectionLink(link.first),
                      )
                    else
                      const SizedBox(width: T.s2),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- helpers

/// Whether a column per field fits in [width].
bool fitsTable(List<CollectionField> fields, double width) {
  if (fields.length < 2) return false;
  final needed = fields.fold<double>(
    0,
    (sum, f) => sum + (fixedColumnWidth(f.kind) ?? kCollectionColumn),
  );
  return width >= needed;
}

/// A link as typed may have no scheme - "chefkoch.de/rezepte/…" is how people
/// paste them - and a browser needs one.
Uri? linkUri(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  final withScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(v)
      ? v
      : 'https://$v';
  return Uri.tryParse(withScheme);
}

/// What a link is called on screen: its host, without the "www.". The path is
/// what makes it unique and is also what nobody can read.
String linkLabel(String value) {
  final host = linkUri(value)?.host ?? '';
  if (host.isEmpty) return value.trim();
  return host.startsWith('www.') ? host.substring(4) : host;
}

Future<void> openCollectionLink(String value) async {
  final uri = linkUri(value);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// "1,5" is how half the people who will type into this write one and a half.
double? parseNumber(String value) =>
    double.tryParse(value.trim().replaceAll(' ', '').replaceAll(',', '.'));

/// Entries with [query] in any of their fields' values, case-insensitively. A
/// value under a removed field is not searched: it is not on screen either.
List<CollectionEntry> filterEntries(
  List<CollectionEntry> entries,
  List<CollectionField> fields,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries;
  return [
    for (final e in entries)
      if (fields.any(
        (f) => f.kind.typed && e.valueOf(f.uuid).toLowerCase().contains(q),
      ))
        e,
  ];
}

/// [entries] in the order asked for. A null [sortField] is the order they were
/// added, newest first, which is the order they arrive in. An empty value
/// sorts last whichever way round: a row with nothing in the sorted column is
/// never the answer to what the sort was asking.
List<CollectionEntry> sortEntries(
  List<CollectionEntry> entries,
  List<CollectionField> fields, {
  String? sortField,
  bool descending = false,
}) {
  if (sortField == null) {
    return descending ? entries.reversed.toList() : entries;
  }
  CollectionField? field;
  for (final f in fields) {
    if (f.uuid == sortField) field = f;
  }
  if (field == null) return entries;
  final f = field;

  int compare(CollectionEntry a, CollectionEntry b) {
    switch (f.kind) {
      case FieldKind.check:
        // Ticked first, read the natural way up.
        return (b.isChecked(f.uuid) ? 1 : 0) - (a.isChecked(f.uuid) ? 1 : 0);
      case FieldKind.number:
        final x = parseNumber(a.valueOf(f.uuid));
        final y = parseNumber(b.valueOf(f.uuid));
        if (x != null && y != null) return x.compareTo(y);
        if (x != null) return -1;
        if (y != null) return 1;
        return a.valueOf(f.uuid).compareTo(b.valueOf(f.uuid));
      case FieldKind.link:
        return linkLabel(
          a.valueOf(f.uuid),
        ).toLowerCase().compareTo(linkLabel(b.valueOf(f.uuid)).toLowerCase());
      case FieldKind.text:
        return a
            .valueOf(f.uuid)
            .toLowerCase()
            .compareTo(b.valueOf(f.uuid).toLowerCase());
    }
  }

  final filled = <CollectionEntry>[];
  final empty = <CollectionEntry>[];
  for (final e in entries) {
    (f.kind != FieldKind.check && e.valueOf(f.uuid).isEmpty ? empty : filled)
        .add(e);
  }
  // List.sort is not stable; the index breaks ties so equal values keep the
  // newest-first order they came in.
  final index = {for (final (i, e) in filled.indexed) e.uuid: i};
  filled.sort((a, b) {
    final c = descending ? compare(b, a) : compare(a, b);
    return c != 0 ? c : index[a.uuid]!.compareTo(index[b.uuid]!);
  });
  return [...filled, ...empty];
}

// ------------------------------------------------------- the entry form

/// Opens the entry form. [existing] null adds: Enter on the last typed field
/// writes the entry through [onSave] and starts the next one in the same
/// form, so several go in one sitting. With [existing] it edits that one.
Future<void> showEntryForm(
  BuildContext context, {
  required Collection collection,
  required List<CollectionField> fields,
  CollectionEntry? existing,
  required Color accent,
  required Future<CollectionEntry?> Function(
    Map<String, String> values,
    CollectionEntry? existing,
  )
  onSave,
  required Future<void> Function(CollectionEntry) onDelete,
}) {
  return showFormSheet<void>(
    context,
    builder: (context, layout) => _EntrySheet(
      collection: collection,
      fields: fields,
      existing: existing,
      accent: accent,
      layout: layout,
      onSave: onSave,
      onDelete: onDelete,
    ),
  );
}

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({
    required this.collection,
    required this.fields,
    required this.existing,
    required this.accent,
    required this.layout,
    required this.onSave,
    required this.onDelete,
  });

  final Collection collection;
  final List<CollectionField> fields;
  final CollectionEntry? existing;
  final Color accent;
  final Layout layout;
  final Future<CollectionEntry?> Function(
    Map<String, String> values,
    CollectionEntry? existing,
  )
  onSave;
  final Future<void> Function(CollectionEntry) onDelete;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _typed = [
    for (final f in widget.fields)
      if (f.kind.typed) f,
  ];
  late final _controllers = {
    for (final f in _typed)
      f.uuid: TextEditingController(
        text: widget.existing?.valueOf(f.uuid) ?? '',
      ),
  };
  late final _focus = {
    for (final f in _typed) f.uuid: FocusNode(debugLabel: f.name),
  };
  late final _checked = {
    for (final f in widget.fields)
      if (f.kind == FieldKind.check)
        f.uuid: widget.existing?.isChecked(f.uuid) ?? false,
  };

  /// How many went in this sitting, and what the last one was called. Said at
  /// the top of the form, because the form clearing itself is otherwise
  /// indistinguishable from the entry having been thrown away.
  int _added = 0;
  String _lastAdded = '';

  bool _busy = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _values => {
    for (final e in _controllers.entries) e.key: e.value.text,
    for (final e in _checked.entries)
      e.key: e.value ? CollectionEntry.checked : '',
  };

  bool get _blank =>
      _controllers.values.every((c) => c.text.trim().isEmpty) &&
      !_checked.values.any((v) => v);

  /// Enter in one typed field: on to the next, or - in the last - add this
  /// one and start the next. Enter in an empty form's last field closes it,
  /// the way Enter on nothing closes the task list's add field.
  Future<void> _submitted(CollectionField f) async {
    final at = _typed.indexOf(f);
    if (at < _typed.length - 1) {
      _focus[_typed[at + 1].uuid]!.requestFocus();
      return;
    }
    if (widget.existing != null) return _saveAndClose();
    if (_blank) {
      Navigator.pop(context);
      return;
    }
    await _addAndNext();
  }

  Future<void> _addAndNext() async {
    if (_busy) return;
    _busy = true;
    final title = _typed.isEmpty ? '' : _controllers[_typed.first.uuid]!.text;
    final saved = await widget.onSave(_values, null);
    _busy = false;
    if (!mounted) return;
    setState(() {
      if (saved != null) {
        _added++;
        _lastAdded = title.trim();
      }
      for (final c in _controllers.values) {
        c.clear();
      }
      for (final k in _checked.keys) {
        _checked[k] = false;
      }
    });
    if (_typed.isNotEmpty) _focus[_typed.first.uuid]!.requestFocus();
  }

  Future<void> _saveAndClose() async {
    if (_busy) return;
    final existing = widget.existing;
    if (existing == null && _blank) {
      Navigator.pop(context);
      return;
    }
    _busy = true;
    await widget.onSave(_values, existing);
    _busy = false;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await widget.onDelete(existing);
    if (mounted) Navigator.pop(context);
  }

  TextInputType _keyboard(FieldKind kind) => switch (kind) {
    FieldKind.link => TextInputType.url,
    FieldKind.number => const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    _ => TextInputType.text,
  };

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    final adding = widget.existing == null;
    final lastTyped = _typed.isEmpty ? null : _typed.last;

    Widget input(CollectionField f) {
      if (f.kind == FieldKind.check) {
        final on = _checked[f.uuid]!;
        // The same tick the list draws, flush with the fields' left edge -
        // Material's Checkbox brings a padding of its own that indents it.
        return Semantics(
          label: f.name,
          checked: on,
          button: true,
          child: InkWell(
            onTap: () => setState(() => _checked[f.uuid] = !on),
            borderRadius: BorderRadius.circular(T.radius),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: touch ? T.s3 : T.s2),
              child: Row(
                children: [
                  Icon(
                    on ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 20,
                    color: on ? widget.accent : T.muted,
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Text(
                      f.name,
                      style: const TextStyle(fontSize: T.fsBody, color: T.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return TextField(
        controller: _controllers[f.uuid],
        focusNode: _focus[f.uuid],
        autofocus: f == _typed.first,
        keyboardType: _keyboard(f.kind),
        autocorrect: f.kind == FieldKind.text,
        enableSuggestions: f.kind == FieldKind.text,
        textCapitalization: f.kind == FieldKind.text
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        inputFormatters: f.kind == FieldKind.number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,+\- ]'))]
            : null,
        // Next everywhere, the last field included: Done would put the
        // keyboard away, and on the last field of a new entry Enter starts
        // the next one, which wants the keyboard where it is.
        textInputAction: adding || f != lastTyped
            ? TextInputAction.next
            : TextInputAction.done,
        // Supplied, and empty, so the field's own idea of what Enter means
        // (move focus along the traversal order, or let go of it) does not
        // run as well as _submitted's.
        onEditingComplete: () {},
        onSubmitted: (_) => _submitted(f),
        style: const TextStyle(fontSize: T.fsBody),
        decoration: InputDecoration(
          labelText: f.name,
          isDense: true,
          suffixIcon: f.kind == FieldKind.link
              ? const Icon(Icons.link_rounded, size: 16, color: T.muted)
              : null,
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _saveAndClose,
      },
      child: FormSheet(
        accent: widget.accent,
        layout: widget.layout,
        title: adding
            ? 'Add to ${widget.collection.name}'
            : widget.collection.name,
        onClose: () => Navigator.pop(context),
        actions: [
          if (!adding) FormSheet.dangerButton(touch: touch, onTap: _delete),
          FormSheet.cancelButton(
            touch: touch,
            label: adding && _added > 0 ? 'Done' : 'Cancel',
            onTap: () => Navigator.pop(context),
          ),
          FormSheet.saveButton(
            touch: touch,
            accent: widget.accent,
            onTap: _saveAndClose,
            label: adding ? 'Add' : 'Save',
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_added > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: T.s2),
                  child: Text(
                    _lastAdded.isEmpty
                        ? 'Added · $_added'
                        : 'Added “$_lastAdded” · $_added',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: T.fsMeta, color: widget.accent),
                  ),
                ),
              if (widget.fields.isEmpty)
                const Text(
                  'This collection has no fields yet.',
                  style: TextStyle(fontSize: T.fsLabel, color: T.muted),
                ),
              for (final f in widget.fields) ...[
                input(f),
                const SizedBox(height: T.s2),
              ],
              if (adding && _typed.isNotEmpty)
                Text(
                  touch
                      ? 'Next moves on. On the last field it adds this one '
                            'and starts another.'
                      : 'Enter moves on. On the last field it adds this one '
                            'and starts another; Ctrl+Enter adds and closes.',
                  style: const TextStyle(
                    fontSize: T.fsMeta,
                    color: T.muted,
                    height: 1.4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------- the collection form

/// What the collection form hands back.
class CollectionEdit {
  const CollectionEdit({
    required this.name,
    required this.fields,
    this.delete = false,
  });

  const CollectionEdit.delete() : name = '', fields = const [], delete = true;

  final String name;
  final List<FieldDraft> fields;
  final bool delete;
}

/// A starting set of fields, so the commonest collections take one tap.
class _Starter {
  const _Starter(this.name, this.fields);

  final String name;
  final List<(String, FieldKind)> fields;
}

const _starters = [
  _Starter('Recipes', [('Name', FieldKind.text), ('Link', FieldKind.link)]),
  _Starter('Movies', [
    ('Title', FieldKind.text),
    ('Year', FieldKind.number),
    ('Seen', FieldKind.check),
  ]),
];

Future<CollectionEdit?> showCollectionForm(
  BuildContext context, {
  Collection? existing,
  List<CollectionField> fields = const [],
  List<CollectionEntry> entries = const [],
  required Color accent,
}) {
  return showFormSheet<CollectionEdit>(
    context,
    builder: (context, layout) => _CollectionSheet(
      existing: existing,
      fields: fields,
      entries: entries,
      accent: accent,
      layout: layout,
    ),
  );
}

/// One field as the form is editing it.
class _FieldRow {
  _FieldRow({this.uuid, String name = '', this.kind = FieldKind.text})
    : controller = TextEditingController(text: name);

  final String? uuid;
  final TextEditingController controller;
  FieldKind kind;

  /// Keyed per row, so moving one up does not hand its text to its neighbour.
  final key = UniqueKey();
}

class _CollectionSheet extends StatefulWidget {
  const _CollectionSheet({
    required this.existing,
    required this.fields,
    required this.entries,
    required this.accent,
    required this.layout,
  });

  final Collection? existing;
  final List<CollectionField> fields;
  final List<CollectionEntry> entries;
  final Color accent;
  final Layout layout;

  @override
  State<_CollectionSheet> createState() => _CollectionSheetState();
}

class _CollectionSheetState extends State<_CollectionSheet> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final List<_FieldRow> _rows = widget.existing == null
      // The smallest useful collection: one word to set up.
      ? [_FieldRow(name: 'Name')]
      : [
          for (final f in widget.fields)
            _FieldRow(uuid: f.uuid, name: f.name, kind: f.kind),
        ];
  final _removed = <_FieldRow>[];

  @override
  void dispose() {
    _name.dispose();
    for (final r in [..._rows, ..._removed]) {
      r.controller.dispose();
    }
    super.dispose();
  }

  void _useStarter(_Starter s) => setState(() {
    if (_name.text.trim().isEmpty) _name.text = s.name;
    _removed.addAll(_rows);
    _rows
      ..clear()
      ..addAll([for (final (n, k) in s.fields) _FieldRow(name: n, kind: k)]);
  });

  void _move(int from, int to) => setState(() {
    _rows.insert(to, _rows.removeAt(from));
  });

  void _remove(_FieldRow r) => setState(() {
    _rows.remove(r);
    _removed.add(r);
  });

  /// How many entries have something in a field.
  int _valuesIn(String uuid) =>
      widget.entries.where((e) => e.valueOf(uuid).isNotEmpty).length;

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(title, style: const TextStyle(fontSize: T.fsMenu)),
        content: Text(
          body,
          style: const TextStyle(fontSize: T.fsBody, color: T.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: T.danger),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final named = _rows.where((r) => r.controller.text.trim().isNotEmpty);
    if (named.isEmpty) return;

    // Removing a field that holds something asks first. Its values stay in
    // the rows, but nothing will show them again.
    final losing = [
      for (final r in [..._removed, ..._rows.where((r) => !named.contains(r))])
        if (r.uuid != null && _valuesIn(r.uuid!) > 0) r,
    ];
    if (losing.isNotEmpty) {
      final names = losing
          .map((r) {
            final f = widget.fields.firstWhere((f) => f.uuid == r.uuid);
            return '“${f.name}”';
          })
          .join(', ');
      final count = losing.fold<int>(0, (n, r) => n + _valuesIn(r.uuid!));
      final ok = await _confirm(
        'Remove $names?',
        'There is something in it in $count '
            '${count == 1 ? 'entry' : 'entries'}, and it will not be shown '
            'again.',
        'Remove',
      );
      if (!ok || !mounted) return;
    }

    Navigator.pop(
      context,
      CollectionEdit(
        name: name,
        fields: [
          for (final r in named)
            FieldDraft(uuid: r.uuid, name: r.controller.text, kind: r.kind),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final n = widget.entries.length;
    final ok = await _confirm(
      'Delete “${widget.existing!.name}”?',
      n == 0
          ? 'It has no entries.'
          : 'Its $n ${n == 1 ? 'entry goes' : 'entries go'} with it.',
      'Delete',
    );
    if (ok && mounted) Navigator.pop(context, const CollectionEdit.delete());
  }

  @override
  Widget build(BuildContext context) {
    final touch = widget.layout.touch;
    final adding = widget.existing == null;

    return FormSheet(
      accent: widget.accent,
      layout: widget.layout,
      title: adding ? 'New collection' : 'Collection',
      onClose: () => Navigator.pop(context),
      actions: [
        if (!adding) FormSheet.dangerButton(touch: touch, onTap: _delete),
        FormSheet.cancelButton(
          touch: touch,
          onTap: () => Navigator.pop(context),
        ),
        FormSheet.saveButton(
          touch: touch,
          accent: widget.accent,
          onTap: _save,
          label: adding ? 'Create' : 'Save',
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: adding,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: T.fsBody),
              decoration: const InputDecoration(
                hintText: 'Recipes, Movies, Books…',
              ),
              textInputAction: TextInputAction.next,
            ),
            if (adding) ...[
              const SizedBox(height: T.s3),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _starters)
                    ActionChip(
                      label: Text(
                        '${s.name}: ${s.fields.map((f) => f.$1).join(', ')}',
                        style: const TextStyle(fontSize: T.fsMeta),
                      ),
                      onPressed: () => _useStarter(s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: T.s4),
            const Text(
              'Fields',
              style: TextStyle(fontSize: T.fsLabel, color: T.muted),
            ),
            const SizedBox(height: T.s1),
            for (final (i, r) in _rows.indexed) _fieldRow(i, r, touch),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _rows.add(_FieldRow())),
                icon: Icon(Icons.add_rounded, size: 16, color: widget.accent),
                label: Text(
                  'Add a field',
                  style: TextStyle(fontSize: T.fsLabel, color: widget.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(int i, _FieldRow r, bool touch) {
    final size = touch ? 36.0 : 28.0;
    Widget button(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? T.muted.withValues(alpha: 0.3) : T.muted,
          ),
        ),
      ),
    );

    return Row(
      key: r.key,
      children: [
        Expanded(
          child: TextField(
            controller: r.controller,
            autofocus: r.controller.text.isEmpty && i > 0,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: T.fsBody),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Field name',
            ),
          ),
        ),
        const SizedBox(width: T.s1),
        PopupMenuButton<FieldKind>(
          tooltip: 'Type',
          color: T.bgSolid,
          initialValue: r.kind,
          onSelected: (k) => setState(() => r.kind = k),
          itemBuilder: (context) => [
            for (final k in FieldKind.values)
              PopupMenuItem(
                value: k,
                height: 38,
                child: Row(
                  children: [
                    Icon(_kindIcon(k), size: 16, color: T.muted),
                    const SizedBox(width: T.s2),
                    Text(k.label, style: const TextStyle(fontSize: T.fsLabel)),
                  ],
                ),
              ),
          ],
          // A fixed width, so the field names to its left all end on one
          // line whatever type each one is.
          child: Container(
            height: size,
            width: 104,
            padding: const EdgeInsets.symmetric(horizontal: T.s2),
            decoration: BoxDecoration(
              color: Color.lerp(T.bgSolid, widget.accent, 0.18),
              borderRadius: BorderRadius.circular(T.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_kindIcon(r.kind), size: 14, color: T.text),
                const SizedBox(width: T.s1),
                Text(
                  r.kind.label,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.text),
                ),
              ],
            ),
          ),
        ),
        button(
          Icons.arrow_upward_rounded,
          'Move up',
          i == 0 ? null : () => _move(i, i - 1),
        ),
        button(
          Icons.arrow_downward_rounded,
          'Move down',
          i == _rows.length - 1 ? null : () => _move(i, i + 1),
        ),
        button(
          Icons.close_rounded,
          'Remove',
          _rows.length == 1 ? null : () => _remove(r),
        ),
      ],
    );
  }
}

IconData _kindIcon(FieldKind k) => switch (k) {
  FieldKind.text => Icons.short_text_rounded,
  FieldKind.link => Icons.link_rounded,
  FieldKind.number => Icons.tag_rounded,
  FieldKind.check => Icons.check_box_outlined,
};
