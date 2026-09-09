// Reviewing a shelf, one task at a time.
//
// A parked group asks to be looked at on its own schedule
// (ParkedGroup.reviewEveryDays), and until now "looking at it" was a button
// called *Mark reviewed* under a list. That is a promise, not a review: the
// list is collapsed by default, the tasks on it are one muted line each, and
// the button is reachable without having read any of them. The shelves it is
// meant to keep out of landfill went to landfill anyway, with a fresh
// timestamp on them.
//
// So the review is a funnel. One task fills the pane, with everything about it
// that is worth a decision - its notes, how long it has been sitting there, an
// armed reminder - and four ways out, exactly one of which is "leave it alone".
// You cannot reach the end without answering for every task on the shelf, and
// reaching the end is what restarts the clock.
//
// Three things about the shape:
//
//   - **The queue is a snapshot.** Every decision except Keep takes the task
//     off the shelf, so a funnel reading `parked[group]` live would renumber
//     itself under the hand and skip whatever moved up into the current slot.
//     The list is taken once, at the start, and the decisions are applied to
//     the database as they are made.
//   - **Leaving early keeps what you decided and does not restart the clock.**
//     Those are two different facts and they should not be traded for each
//     other: the tasks you dealt with are dealt with, and a shelf you got a
//     third of the way through has not been reviewed.
//   - **Keep is the safe answer and it is the one on the Enter key**, because
//     the failure mode of a review under time pressure is bulk-answering it,
//     and the answer that should be cheap to give is the one that changes
//     nothing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout.dart';
import '../sync/models.dart';
import '../theme.dart';
import 'markdown_text.dart';
import 'panel_header.dart';
import 'reminder_menu.dart';

/// What was decided about one task. Ordered as the buttons are.
enum ReviewChoice { keep, activate, complete, drop }

class ParkedReview extends StatefulWidget {
  const ParkedReview({
    super.key,
    required this.group,
    required this.tasks,
    required this.accent,
    required this.onDecide,
    required this.onFinished,
    required this.onClose,
  });

  final ParkedGroup group;

  /// The queue, as it stood when the review began. See the header.
  final List<Task> tasks;

  final Color accent;

  /// Apply one decision. [ReviewChoice.keep] is not routed here - it writes
  /// nothing, which is the whole point of it.
  final Future<void> Function(Task, ReviewChoice) onDecide;

  /// Every task answered for. This is what restarts the group's clock.
  final Future<void> Function() onFinished;

  /// Out of the review, back to the shelves. Also what Esc does.
  final VoidCallback onClose;

  @override
  State<ParkedReview> createState() => ParkedReviewState();
}

class ParkedReviewState extends State<ParkedReview> {
  int _index = 0;
  bool _busy = false;

  /// The funnel's own node, autofocused so Enter lands on Keep without anything
  /// having to be clicked first.
  ///
  /// A node rather than a [CallbackShortcuts], and that is not a style choice:
  /// key events travel from the primary focus *upwards*, and the panel around
  /// this one already holds a node so it can intercept Esc. A shortcut widget
  /// nested under that node would never be reached. Unhandled keys are returned
  /// as ignored, which is what lets Esc go on up to the panel.
  final _focus = FocusNode(debugLabel: 'parked review');

  @override
  void initState() {
    super.initState();
    // An empty shelf is reviewed by looking at it: there is no card to answer,
    // so opening the funnel *is* reaching the end of it. Deferred, because the
    // owner reacts to this by writing a row and calling setState, and doing
    // that from inside another widget's build is the crash it looks like.
    if (done) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Tallies for the closing line, so the end of a review says what it was.
  final _counts = <ReviewChoice, int>{};

  /// True once the last task has been answered for; the pane then shows the
  /// summary rather than a card.
  bool get done => _index >= widget.tasks.length;

  Future<void> choose(ReviewChoice choice) async {
    if (_busy || done) return;
    final task = widget.tasks[_index];

    setState(() {
      _busy = true;
      _counts[choice] = (_counts[choice] ?? 0) + 1;
    });

    if (choice != ReviewChoice.keep) await widget.onDecide(task, choice);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _index++;
    });

    // Reaching the end is the review; the summary is only what it looks like.
    if (done) await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        choose(ReviewChoice.keep);
        return KeyEventResult.handled;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelHeader(
            title: 'Review: ${widget.group.title}',
            onBack: widget.onClose,
            backTooltip: 'Back to the shelves (Esc)',
          ),
          Expanded(child: done ? _summary(layout) : _card(layout)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- card

  Widget _card(Layout layout) {
    final task = widget.tasks[_index];
    final notes = markdownPlainText(task.notes);
    final remind = task.remindAtTime;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(T.s4, 0, T.s4, T.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Progress(
            index: _index,
            total: widget.tasks.length,
            accent: widget.accent,
          ),
          const SizedBox(height: T.s4),
          Text(
            task.text,
            style: TextStyle(
              fontSize: T.fsMenu,
              color: T.text,
              height: 1.3,
              fontWeight: task.isHighPriority ? T.wStrong : T.wMedium,
            ),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: T.s2),
            Text(
              notes,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: T.fsLabel,
                color: T.muted,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: T.s3),
          Text(
            [
              _shelvedFor(task),
              if (remind != null) 'reminder ${describeReminder(remind)}',
            ].join(' - '),
            style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
          ),
          const SizedBox(height: T.s5),
          Wrap(
            spacing: T.s2,
            runSpacing: T.s2,
            children: [
              _Choice(
                label: 'Keep',
                hint: layout.touch ? null : 'Enter',
                icon: Icons.inventory_2_outlined,
                color: widget.accent,
                filled: true,
                touch: layout.touch,
                onTap: _busy ? null : () => choose(ReviewChoice.keep),
              ),
              _Choice(
                label: 'Do it now',
                icon: Icons.north_east_rounded,
                color: widget.accent,
                touch: layout.touch,
                onTap: _busy ? null : () => choose(ReviewChoice.activate),
              ),
              _Choice(
                label: 'Done',
                icon: Icons.check_rounded,
                color: T.ok,
                touch: layout.touch,
                onTap: _busy ? null : () => choose(ReviewChoice.complete),
              ),
              _Choice(
                label: 'Drop',
                icon: Icons.close_rounded,
                color: T.danger,
                touch: layout.touch,
                onTap: _busy ? null : () => choose(ReviewChoice.drop),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "parked 24 days ago" - the number that makes the decision, and the one
  /// thing a collapsed shelf never showed.
  static String _shelvedFor(Task task) {
    final at = DateTime.tryParse(task.createdAt);
    if (at == null) return 'parked';
    final days = DateTime.now().difference(at.toLocal()).inDays;
    if (days < 1) return 'parked today';
    if (days == 1) return 'parked yesterday';
    if (days < 60) return 'parked $days days ago';
    return 'parked ${(days / 30).round()} months ago';
  }

  // ---------------------------------------------------------------- summary

  Widget _summary(Layout layout) {
    final kept = _counts[ReviewChoice.keep] ?? 0;
    final moved = widget.tasks.length - kept;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all_rounded, size: 28, color: widget.accent),
            const SizedBox(height: T.s3),
            Text(
              widget.tasks.isEmpty
                  ? 'Nothing on this shelf.'
                  : 'Reviewed ${widget.tasks.length} '
                      '${widget.tasks.length == 1 ? "todo" : "todos"}.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: T.fsBody, color: T.text),
            ),
            const SizedBox(height: T.s2),
            Text(
              moved == 0
                  ? 'All still parked. The clock starts again.'
                  : '$kept still parked, $moved dealt with.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: T.fsLabel,
                color: T.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: T.s4),
            _Choice(
              label: 'Back to the shelves',
              icon: Icons.arrow_back_rounded,
              color: widget.accent,
              filled: true,
              touch: layout.touch,
              onTap: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

/// How far through, as dots while they fit and as a count always.
///
/// Dots because the question a review makes you ask is "how much more of this
/// is there", and a bar answers it in a shape nobody counts. They stop at a
/// shelf worth of them; past that the number is the honest answer.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.index,
    required this.total,
    required this.accent,
  });

  final int index;
  final int total;
  final Color accent;

  static const maxDots = 12;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (total <= maxDots)
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (var i = 0; i < total; i++)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < index
                          ? accent
                          : i == index
                              ? accent.withValues(alpha: 0.55)
                              : T.surfaceHover,
                    ),
                  ),
              ],
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: T.s2),
        Text(
          '${index + 1} of $total',
          style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
        ),
      ],
    );
  }
}

/// One answer. Sized off [Layout.touch] like every other control that has to
/// be hit with a thumb; a null [onTap] is the busy state, not a missing action.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.icon,
    required this.color,
    required this.touch,
    required this.onTap,
    this.hint,
    this.filled = false,
  });

  final String label;
  final String? hint;
  final IconData icon;
  final Color color;
  final bool touch;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.radius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: T.s3,
            vertical: touch ? T.s3 : T.s2,
          ),
          decoration: BoxDecoration(
            color: filled ? color.withValues(alpha: 0.16) : T.surface,
            borderRadius: BorderRadius.circular(T.radius),
            border: Border.all(
              color: filled ? color.withValues(alpha: 0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: touch ? 17 : 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: T.fsLabel,
                  color: T.text,
                  fontWeight: T.wMedium,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 6),
                Text(
                  hint!,
                  style: const TextStyle(fontSize: T.fsMeta, color: T.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
