// The shopping list: one throwaway list, read in a shop with a full hand.
//
// See *The shopping list* in ROADMAP.md. Three things shape this file:
//
//   - **Two modes, and the switch is big.** Use is the default and can do one
//     thing: tick. Nothing on a row edits or deletes, because in a shop the
//     screen is half-looked-at and a mis-tap must cost nothing. Edit is where
//     items are added, renamed, deleted and reordered. The button between them
//     is the largest thing in the header, not a pencil in a menu.
//   - **Ticked items slide down, not away.** In Use every row is placed by an
//     [AnimatedPositioned] keyed on its uuid, at a position worked out from its
//     index in "still to get, then the Ticked header, then ticked". A tick
//     changes the index, so the row glides to its new place and the rows it
//     passes glide out of its way - no list diffing, no per-row controllers.
//     That needs a fixed row height, which is why an item is one line: they
//     are "2× milk", not paragraphs.
//   - **The archive is quiet on purpose.** Finishing archives the list and you
//     are not expected to go back; the way in is a small muted line, and what
//     is behind it is read-only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';

class ShoppingListView extends StatefulWidget {
  const ShoppingListView({super.key, required this.state});

  final AppState state;

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

enum _Rung { list, archive, archived }

class _ShoppingListViewState extends State<ShoppingListView> {
  AppState get s => widget.state;

  /// Null means "decide from the list": an empty list opens in Edit, since
  /// there is nothing to tick and the add field is the only useful thing.
  bool? _editingChoice;
  bool get _editing => _editingChoice ?? s.listItems.isEmpty;

  _Rung _rung = _Rung.list;
  ShoppingList? _reading;

  final _add = TextEditingController();
  final _addFocus = FocusNode();
  final _name = TextEditingController();

  /// One controller per item while editing, so a retitle typed into one row
  /// survives the list being reloaded under it.
  final _edits = <String, TextEditingController>{};

  @override
  void dispose() {
    _add.dispose();
    _addFocus.dispose();
    _name.dispose();
    for (final c in _edits.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _setEditing(bool editing) {
    if (!editing) _saveEdits();
    setState(() => _editingChoice = editing);
    if (editing) {
      _name.text = s.currentList?.name ?? AppState.defaultListName;
    }
  }

  /// Write every retitle typed in Edit. Done is the save, as it is in the
  /// composer, so a half-typed row is never lost by leaving the mode.
  void _saveEdits() {
    for (final item in s.listItems) {
      final c = _edits[item.uuid];
      if (c != null && c.text.trim() != item.text) {
        s.editListItem(item, c.text);
      }
    }
    if (_name.text.trim().isNotEmpty) s.renameList(_name.text);
    for (final c in _edits.values) {
      c.dispose();
    }
    _edits.clear();
  }

  /// Enter adds and stays: the caret is still in the field for the next item,
  /// and the list stays in Edit until Done is pressed. A new list used to be
  /// in Edit only *because* it was empty (see [_editing]), so the first item
  /// dropped it into Use and every item after that cost a press on Edit.
  /// Pinning the choice on the first add is what keeps it.
  Future<void> _submitAdd() async {
    final text = _add.text;
    if (text.trim().isEmpty) return;
    // Before the write, not after: the write notifies, and one frame of
    // Use would unmount this field and take the keyboard with it.
    if (_editingChoice == null) _setEditing(true);
    _add.clear();
    _addFocus.requestFocus();
    await s.addListItem(text);
  }

  Future<void> _doneFromKeyboard() async {
    final text = _add.text;
    if (text.trim().isNotEmpty) {
      _add.clear();
      await s.addListItem(text);
    }
    if (!mounted || s.listItems.isEmpty) return;
    _setEditing(false);
  }

  void _tick(ListItem item) {
    HapticFeedback.selectionClick();
    s.setListItemChecked(item, !item.isChecked);
  }

  Future<void> _finish() async {
    _saveEdits();
    await s.finishList();
    if (mounted) setState(() => _editingChoice = null);
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    return Focus(
      // Esc walks back down the rungs before the shell closes the screen.
      // Ctrl+Enter is Done: whatever is in the add field goes in first, so
      // the last item typed is not left behind in a field that is going.
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
            HardwareKeyboard.instance.isControlPressed &&
            _rung == _Rung.list &&
            _editing) {
          _doneFromKeyboard();
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        switch (_rung) {
          case _Rung.archived:
            setState(() => _rung = _Rung.archive);
          case _Rung.archive:
            setState(() => _rung = _Rung.list);
          case _Rung.list:
            if (!_editing || s.listItems.isEmpty) {
              return KeyEventResult.ignored;
            }
            _setEditing(false);
        }
        return KeyEventResult.handled;
      },
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) => switch (_rung) {
          _Rung.list => _list(layout),
          _Rung.archive => _ArchiveView(
            state: s,
            onBack: () => setState(() => _rung = _Rung.list),
            onOpen: (l) => setState(() {
              _reading = l;
              _rung = _Rung.archived;
            }),
          ),
          _Rung.archived => _ArchivedListView(
            state: s,
            list: _reading!,
            onBack: () => setState(() => _rung = _Rung.archive),
          ),
        },
      ),
    );
  }

  Widget _list(Layout layout) {
    final current = s.currentList;
    final items = s.listItems;
    final open = [
      for (final i in items)
        if (!i.isChecked) i,
    ];
    final allTicked = items.isNotEmpty && open.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                _saveEdits();
                setState(() => _rung = _Rung.archive);
              },
              style: TextButton.styleFrom(
                foregroundColor: T.muted,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Archived lists →',
                style: TextStyle(fontSize: T.fsMeta),
              ),
            ),
          ),
          const SizedBox(height: T.s1),
          _header(layout, current, allTicked),
          for (final other in s.otherOpenLists)
            _AlsoOpen(state: s, list: other),
          const SizedBox(height: T.s2),
          if (_editing) _addField(layout),
          Expanded(
            child: _editing
                ? _EditItems(
                    state: s,
                    layout: layout,
                    controllerFor: (item) => _edits.putIfAbsent(
                      item.uuid,
                      () => TextEditingController(text: item.text),
                    ),
                    onTick: _tick,
                  )
                : _UseItems(items: items, layout: layout, onTick: _tick),
          ),
        ],
      ),
    );
  }

  Widget _header(Layout layout, ShoppingList? current, bool allTicked) {
    final title = _editing && current != null
        ? TextField(
            controller: _name,
            style: const TextStyle(
              fontSize: T.fsTitle,
              fontFamily: T.fontDisplay,
              fontWeight: T.wMedium,
              color: T.text,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: AppState.defaultListName,
            ),
            onSubmitted: s.renameList,
          )
        : Text(
            current?.name ?? 'New list',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: T.fsTitle,
              fontFamily: T.fontDisplay,
              fontWeight: T.wMedium,
              color: T.text,
            ),
          );
    final height = layout.touch ? 40.0 : 32.0;

    return Row(
      children: [
        Expanded(child: title),
        if (current != null && s.listItems.isNotEmpty) ...[
          // Prominent once everything is ticked; available before, because
          // leaving the shop without the tomatoes is allowed.
          SizedBox(
            height: height,
            child: allTicked
                ? FilledButton(
                    onPressed: _finish,
                    style: FilledButton.styleFrom(backgroundColor: T.ok),
                    child: const Text('Finished'),
                  )
                : OutlinedButton(
                    onPressed: _finish,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: T.muted,
                      side: const BorderSide(color: T.surfaceHover),
                    ),
                    child: const Text('Finished'),
                  ),
          ),
          const SizedBox(width: T.s2),
        ],
        if (s.listItems.isNotEmpty)
          SizedBox(
            height: height,
            child: FilledButton.icon(
              onPressed: () => _setEditing(!_editing),
              style: FilledButton.styleFrom(backgroundColor: T.accent),
              icon: Icon(
                _editing ? Icons.check : Icons.edit_outlined,
                size: 18,
              ),
              label: Text(_editing ? 'Done' : 'Edit'),
            ),
          ),
      ],
    );
  }

  Widget _addField(Layout layout) => Padding(
    padding: const EdgeInsets.only(bottom: T.s2),
    child: TextField(
      controller: _add,
      focusNode: _addFocus,
      autofocus: s.listItems.isEmpty,
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontSize: T.fsMenu, color: T.text),
      decoration: InputDecoration(
        hintText: 'Add an item',
        hintStyle: const TextStyle(color: T.muted),
        // A line like the task list's "Add a task", not a filled box:
        // the field is the first row of the list, not a form above it.
        prefixIcon: const Padding(
          padding: EdgeInsets.only(right: T.s3),
          child: Icon(Icons.add, color: T.muted),
        ),
        prefixIconConstraints: const BoxConstraints(),
        isDense: !layout.touch,
        border: InputBorder.none,
      ),
      // Enter adds and keeps the caret, as the task add field does. On
      // editing-complete rather than submitted: the default for a "done"
      // key is to drop focus first, which on a phone folds the keyboard away
      // and back between every item.
      onEditingComplete: _submitAdd,
    ),
  );
}

/// Use mode: tap to tick, and every row slides to where it now belongs.
class _UseItems extends StatelessWidget {
  const _UseItems({
    required this.items,
    required this.layout,
    required this.onTick,
  });

  final List<ListItem> items;
  final Layout layout;
  final void Function(ListItem) onTick;

  static const _slide = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    final rowHeight = layout.touch ? 52.0 : 40.0;
    const headerHeight = 36.0;

    final open = [
      for (final i in items)
        if (!i.isChecked) i,
    ];
    // Newest tick first: the thing just put in the basket is the one most
    // likely to be unticked again.
    final ticked = [
      for (final i in items)
        if (i.isChecked) i,
    ]..sort((a, b) => b.checkedAt!.compareTo(a.checkedAt!));

    final placed = <Widget>[];
    var y = 0.0;
    for (final item in open) {
      placed.add(_place(item, y, rowHeight));
      y += rowHeight;
    }
    if (ticked.isNotEmpty) {
      placed.add(
        AnimatedPositioned(
          key: const ValueKey('ticked-header'),
          duration: _slide,
          curve: T.heroEase,
          top: y,
          left: 0,
          right: 0,
          height: headerHeight,
          child: _TickedHeader(count: ticked.length),
        ),
      );
      y += headerHeight;
      for (final item in ticked) {
        placed.add(_place(item, y, rowHeight));
        y += rowHeight;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: T.s5),
      child: AnimatedContainer(
        duration: _slide,
        curve: T.heroEase,
        height: y,
        child: Stack(children: placed),
      ),
    );
  }

  Widget _place(ListItem item, double top, double height) => AnimatedPositioned(
    key: ValueKey(item.uuid),
    duration: _slide,
    curve: T.heroEase,
    top: top,
    left: 0,
    right: 0,
    height: height,
    child: _ItemRow(item: item, onTap: () => onTick(item)),
  );
}

class _TickedHeader extends StatelessWidget {
  const _TickedHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        'Ticked · $count',
        style: const TextStyle(fontSize: T.fsLabel, color: T.muted),
      ),
      const SizedBox(width: T.s2),
      const Expanded(child: Divider(color: T.surfaceHover, height: 1)),
    ],
  );
}

/// One row in Use: the whole width is the tap target.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final ListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = item.isChecked;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: Row(
          children: [
            const SizedBox(width: T.s1),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(done),
                color: done ? T.ok.withValues(alpha: 0.6) : T.muted,
                size: 24,
              ),
            ),
            const SizedBox(width: T.s3),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: T.fsMenu,
                  color: done ? T.muted : T.text,
                  decoration: done
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: T.muted,
                ),
                child: Text(
                  item.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit mode: retitle in place, ✕ to delete, drag to reorder what is still
/// to get. Ticked items are listed below and can be unticked or deleted.
class _EditItems extends StatelessWidget {
  const _EditItems({
    required this.state,
    required this.layout,
    required this.controllerFor,
    required this.onTick,
  });

  final AppState state;
  final Layout layout;
  final TextEditingController Function(ListItem) controllerFor;
  final void Function(ListItem) onTick;

  @override
  Widget build(BuildContext context) {
    final open = [
      for (final i in state.listItems)
        if (!i.isChecked) i,
    ];
    final ticked = [
      for (final i in state.listItems)
        if (i.isChecked) i,
    ];

    Widget row(ListItem item, {Widget? handle}) => Row(
      children: [
        IconButton(
          tooltip: item.isChecked ? 'Untick' : 'Tick',
          onPressed: () => onTick(item),
          icon: Icon(
            item.isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
            color: item.isChecked ? T.ok.withValues(alpha: 0.6) : T.muted,
          ),
        ),
        Expanded(
          child: TextField(
            controller: controllerFor(item),
            style: TextStyle(
              fontSize: T.fsMenu,
              color: item.isChecked ? T.muted : T.text,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
            ),
            onSubmitted: (text) => state.editListItem(item, text),
          ),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => state.deleteListItem(item),
          icon: const Icon(Icons.close, color: T.muted, size: 20),
        ),
        ?handle,
      ],
    );

    return CustomScrollView(
      slivers: [
        SliverReorderableList(
          itemCount: open.length,
          onReorderItem: (from, to) {
            final ids = [for (final i in open) i.uuid];
            ids.insert(to, ids.removeAt(from));
            state.reorderListItems(ids);
          },
          itemBuilder: (context, index) {
            final item = open[index];
            final handle = ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: T.s2),
                child: Icon(Icons.drag_handle, color: T.muted, size: 20),
              ),
            );
            return Material(
              key: ValueKey(item.uuid),
              type: MaterialType.transparency,
              child: row(item, handle: handle),
            );
          },
        ),
        if (ticked.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: T.s2),
              child: _TickedHeader(count: ticked.length),
            ),
          ),
          SliverList.list(children: [for (final i in ticked) row(i)]),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: T.s5)),
      ],
    );
  }
}

/// An older open list, from two devices each starting one offline. Offered
/// for merging rather than hidden, so nothing written on either is lost.
class _AlsoOpen extends StatelessWidget {
  const _AlsoOpen({required this.state, required this.list});

  final AppState state;
  final ShoppingList list;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: T.s2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Also open: ${list.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: T.fsLabel, color: T.warn),
          ),
        ),
        TextButton(
          onPressed: () => state.mergeListIntoCurrent(list),
          child: const Text('Merge here'),
        ),
        TextButton(
          onPressed: () => state.finishList(list),
          style: TextButton.styleFrom(foregroundColor: T.muted),
          child: const Text('Finish'),
        ),
      ],
    ),
  );
}

/// Finished lists, newest first. Read-only; delete is the one thing to do.
class _ArchiveView extends StatefulWidget {
  const _ArchiveView({
    required this.state,
    required this.onBack,
    required this.onOpen,
  });

  final AppState state;
  final VoidCallback onBack;
  final void Function(ShoppingList) onOpen;

  @override
  State<_ArchiveView> createState() => _ArchiveViewState();
}

class _ArchiveViewState extends State<_ArchiveView> {
  late Future<(List<ShoppingList>, Map<String, int>)> _load = _fetch();

  Future<(List<ShoppingList>, Map<String, int>)> _fetch() async =>
      (await widget.state.archivedLists(), await widget.state.listItemCounts());

  Future<void> _delete(ShoppingList list) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: T.bgSolid,
        title: Text(
          'Delete ${list.name}?',
          style: const TextStyle(fontSize: T.fsMenu),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: T.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.state.deleteList(list);
    setState(() => _load = _fetch());
  }

  @override
  Widget build(BuildContext context) => _Rung2(
    title: 'Archived lists',
    onBack: widget.onBack,
    child: FutureBuilder(
      future: _load,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final (lists, counts) = data;
        if (lists.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(T.s4),
            child: Text(
              'Nothing finished yet.',
              style: TextStyle(color: T.muted),
            ),
          );
        }
        return ListView(
          children: [
            for (final l in lists)
              ListTile(
                title: Text(
                  l.name,
                  style: const TextStyle(color: T.text, fontSize: T.fsMenu),
                ),
                subtitle: Text(
                  '${_day(l.archivedAt)} · ${_items(counts[l.uuid] ?? 0)}',
                  style: const TextStyle(color: T.muted, fontSize: T.fsMeta),
                ),
                onTap: () => widget.onOpen(l),
                trailing: IconButton(
                  tooltip: 'Delete',
                  onPressed: () => _delete(l),
                  icon: const Icon(Icons.delete_outline, color: T.muted),
                ),
              ),
          ],
        );
      },
    ),
  );

  static String _items(int n) => n == 1 ? '1 item' : '$n items';

  static String _day(String? stamp) {
    final d = stamp == null ? null : DateTime.tryParse(stamp)?.toLocal();
    if (d == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

/// One finished list, as it was when it was finished.
class _ArchivedListView extends StatelessWidget {
  const _ArchivedListView({
    required this.state,
    required this.list,
    required this.onBack,
  });

  final AppState state;
  final ShoppingList list;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _Rung2(
    title: list.name,
    onBack: onBack,
    child: FutureBuilder(
      future: state.itemsOfList(list.uuid),
      builder: (context, snap) => ListView(
        children: [
          for (final i in snap.data ?? const <ListItem>[])
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  Icon(
                    i.isChecked
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: T.muted,
                    size: 20,
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Text(
                      i.text,
                      style: TextStyle(
                        color: T.muted,
                        fontSize: T.fsMenu,
                        decoration: i.isChecked
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: T.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A rung below the list: a back line and a title over its own body.
class _Rung2 extends StatelessWidget {
  const _Rung2({
    required this.title,
    required this.onBack,
    required this.child,
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(T.s4, T.s2, T.s4, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onBack,
            style: TextButton.styleFrom(foregroundColor: T.muted),
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('Back'),
          ),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: T.fsTitle,
            fontFamily: T.fontDisplay,
            fontWeight: T.wMedium,
            color: T.text,
          ),
        ),
        const SizedBox(height: T.s2),
        Expanded(child: child),
      ],
    ),
  );
}
