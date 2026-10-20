// What the list says before there is a list: a new account starts with no
// workspace (no seeded "Tasks" - Marco, 2026-10-20), and until one is made
// this stands where the task list goes.
//
// One screen, no scrolling on a phone if it can help it, and plain: each line
// names a thing and says where it is. It is the only map of the app a new
// person gets, so it names what the bar's parts hold rather than selling them.

import 'package:flutter/material.dart';

import '../theme.dart';

class NoWorkspace extends StatelessWidget {
  const NoWorkspace({super.key, required this.onCreate});

  final VoidCallback onCreate;

  static const _lines = [
    ('Workspace', 'A list of tasks: work, home, a side project.'),
    (
      'Notes, Parked, Collections, History',
      "Each workspace's own, in the middle of the bar.",
    ),
    ('Projects', 'A list inside a workspace.'),
    ('Thoughts, Calendar, List', 'Shared by every workspace, under More.'),
    ('＋', 'Add a task or a thought.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(T.s4, T.s4, T.s4, T.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No workspace yet',
            style: TextStyle(
              fontFamily: T.fontDisplay,
              fontSize: T.fsTitle,
              fontWeight: T.wMedium,
              color: T.text,
              height: 1.2,
            ),
          ),
          const SizedBox(height: T.s4),
          for (final (term, says) in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: T.s3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    term,
                    style: const TextStyle(
                      fontFamily: T.fontDisplay,
                      fontSize: T.fsBody,
                      fontWeight: T.wMedium,
                      color: T.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    says,
                    style: const TextStyle(
                      fontSize: T.fsLabel,
                      color: T.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: T.s2),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: T.accent,
              foregroundColor: T.inkOn(T.accent),
            ),
            onPressed: onCreate,
            child: const Text('Create a workspace'),
          ),
        ],
      ),
    );
  }
}
