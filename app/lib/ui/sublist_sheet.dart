// The list that belongs to one block of time.
//
// A calendar block says *when*; this is where you say *what*, in the two ways
// that actually come up: writing a todo that only exists because of this block
// ("print the slides"), and taking something already on the list and saying
// "that one, then". Both are one write to `event_uuid` - there is no sublist
// table, because a sublist is just the tasks pointing at a block.
//
// It is a **sheet in the shell's Stack, not a dialog**: a modal route's barrier
// covers the title bar, which is the window's drag handle (see
// settings_sheet.dart). It also means the block's todos can be written while
// the task list underneath is still visible, which is the point of the empty
// case - the tile said "nothing planned", and this is the way to answer that
// without leaving the list.
//
// The event editor's tick list does the same job from the other end. The two
// are deliberately not shared: that one is a section of a form about the block,
// this one is a place to *write*, so it opens with the caret in an add field
// and puts what is already planned first.

import 'package:flutter/material.dart';

import '../sync/models.dart';
import '../theme.dart';
import 'title_bar.dart';

class SublistSheet extends StatefulWidget {
  const SublistSheet({
    super.key,
    required this.event,
    required this.subtitle,
    required this.color,
    required this.accent,
    required this.planned,
    required this.candidates,
    required this.onAdd,
    required this.onPlan,
    required this.onComplete,
    required this.onClose,
  });

  final CalendarEvent event;

  /// The line under the title - the calendar's name and the block's span.
  /// Composed by the caller, which is the only place that knows how to name a
  /// calendar (a workspace calendar borrows the workspace's name).
  final String subtitle;

  /// The block's own colour, and the workspace accent. Both are here because a
  /// block can belong to a workspace that is not the one on screen.
  final Color color;
  final Color accent;

  /// What is planned into the block already, and what else could be.
  final List<Task> planned;
  final List<Task> candidates;

  /// Write a new todo straight into this block.
  final Future<void> Function(String text) onAdd;

  /// Plan an existing todo into the block, or take it back out.
  final Future<void> Function(Task task, bool into) onPlan;

  final Future<void> Function(Task task) onComplete;

  final VoidCallback onClose;

  @override
  State<SublistSheet> createState() => _SublistSheetState();
}

class _SublistSheetState extends State<SublistSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// The workspace's other open todos, folded away by default. The sheet is
  /// opened to *write* a block's list; a long list of everything else on the
  /// first screen would bury the field that does that.
  bool _showCandidates = false;

  @override
  void initState() {
    super.initState();
    // Straight into the field: the sheet exists because there is nothing in
    // this block yet, and the first thing to do is say what there is.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    _controller.clear();
    if (text.isEmpty) return;
    await widget.onAdd(text);
    // Always back to the field: writing a block's list is several lines in a
    // row, not one. Enter therefore chains here, unlike the main add field.
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final unplanned = [
      for (final t in widget.candidates)
        if (t.eventUuid != widget.event.uuid) t,
    ];

    return Positioned(
      top: TitleBar.height,
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, widget.color, 0.14),
          border: Border(top: BorderSide(color: widget.color.withValues(alpha: 0.35))),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(12),
            bottom: Radius.circular(T.radius),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x73000000), blurRadius: 30, offset: Offset(0, -10)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(),
            _addField(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                children: [
                  if (widget.planned.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(2, 6, 2, 8),
                      child: Text(
                        'Nothing in this block yet. Type above, or take '
                        'something off your list below.',
                        style: TextStyle(
                            fontSize: 11.5, color: T.muted, height: 1.35),
                      ),
                    )
                  else
                    for (final t in widget.planned)
                      _PlannedRow(
                        key: ValueKey(t.uuid),
                        task: t,
                        accent: widget.accent,
                        onComplete: () => widget.onComplete(t),
                        onRemove: () => widget.onPlan(t, false),
                      ),
                  if (unplanned.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _CandidatesHeader(
                      count: unplanned.length,
                      open: _showCandidates,
                      onToggle: () =>
                          setState(() => _showCandidates = !_showCandidates),
                    ),
                    if (_showCandidates)
                      for (final t in unplanned)
                        _CandidateRow(
                          key: ValueKey(t.uuid),
                          task: t,
                          accent: widget.accent,
                          // Planned into some *other* block. Ticking it moves
                          // it here - a task is in at most one block, and the
                          // mark is what stops that being a surprise.
                          elsewhere: t.eventUuid != null,
                          onPlan: () => widget.onPlan(t, true),
                        ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.text,
                  ),
                ),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: T.muted),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(7),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close, size: 15, color: T.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Add a todo for this block…',
          filled: true,
          fillColor: T.surface,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: widget.color.withValues(alpha: 0.6)),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

/// A todo already in the block: check it off, or take it back out onto the
/// plain list. Deliberately not a [TaskRow] - focus, parking and reminders all
/// belong to the list, and this is a short list you are assembling.
class _PlannedRow extends StatelessWidget {
  const _PlannedRow({
    super.key,
    required this.task,
    required this.accent,
    required this.onComplete,
    required this.onRemove,
  });

  final Task task;
  final Color accent;
  final Future<void> Function() onComplete;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Semantics(
            label: 'Check off task',
            button: true,
            child: InkWell(
              onTap: onComplete,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: accent.withValues(alpha: 0.7), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              task.text,
              style: const TextStyle(fontSize: 12.5, color: T.text, height: 1.3),
            ),
          ),
          Tooltip(
            message: 'Take it out of this block',
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(Icons.remove_circle_outline, size: 15, color: T.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidatesHeader extends StatelessWidget {
  const _CandidatesHeader({
    required this.count,
    required this.open,
    required this.onToggle,
  });

  final int count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 15,
              color: T.muted,
            ),
            const SizedBox(width: 6),
            Text(
              'From your list · $count',
              style: const TextStyle(
                fontSize: 11.5,
                color: T.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.task,
    required this.accent,
    required this.elsewhere,
    required this.onPlan,
  });

  final Task task;
  final Color accent;
  final bool elsewhere;
  final Future<void> Function() onPlan;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlan,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline, size: 15, color: T.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                task.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: T.muted),
              ),
            ),
            if (elsewhere)
              const Tooltip(
                message: 'Planned into another block — this moves it here',
                child: Icon(Icons.event_available_rounded,
                    size: 12, color: T.muted),
              ),
          ],
        ),
      ),
    );
  }
}
