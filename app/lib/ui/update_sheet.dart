// "Update the app" - the one screen that says why syncing stopped.
//
// It exists because the failure it reports is otherwise invisible. When the app
// and the server disagree about the wire, the honest outcomes are a row written
// wrong or no row written at all; the second is the safe one and it looks
// exactly like nothing happening. The red icon in the title bar is a hint you
// have to already understand - this is the sentence.
//
// A **sheet in the shell's Stack**, not a `showDialog` route: a modal route's
// barrier covers the title bar too, and this is a state that can last days
// (until somebody deploys or updates), so it would leave the window undraggable
// and unclosable for all of them. Same reason SoundSheet and SettingsSheet are
// sheets.
//
// And it **closes**. The mismatch is not an emergency and the app is not broken
// by it: the local database is untouched, every edit still saves, and the queue
// keeps filling so the moment the mismatch is resolved everything goes up. A
// screen you cannot dismiss would be punishing the user for the state of two
// machines - what stays behind after closing is the red sync icon and the same
// sentence in Settings, which is the right weight for something you cannot fix
// from here right now.

import 'package:flutter/material.dart';

import '../sync/protocol.dart';
import '../theme.dart';
import 'title_bar.dart';

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({
    super.key,
    required this.compatibility,
    required this.server,
    required this.accent,
    required this.onClose,
  });

  final Compatibility compatibility;
  final ServerProtocol server;

  /// The workspace colour, for the one button. Not a danger red: nothing here
  /// is destructive and nothing is lost, so shouting would be lying about the
  /// stakes.
  final Color accent;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: TitleBar.height,
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(T.bgSolid, T.danger, 0.10),
          border: Border(
            top: BorderSide(color: T.danger.withValues(alpha: 0.45)),
          ),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(12),
            bottom: Radius.circular(T.radius),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 30,
              offset: Offset(0, -10),
            ),
          ],
        ),
        // Scrolls its own body: this window is 480px tall and resizable, and a
        // Column that merely overflows becomes an unusable smear.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sync_problem_rounded,
                    size: 18,
                    color: T.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      compatibility.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: T.text,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                compatibility.summary(server),
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: T.text,
                ),
              ),
              const SizedBox(height: 12),
              // The reassurance is the most important line on the panel. The
              // first thing anybody reads "syncing is off" as is "where are my
              // tasks", and the answer - right here, all of them, still being
              // saved - is what stops this being frightening.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: T.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  'Nothing is lost. Everything on this device still works and '
                  'still saves; changes are queued and will go up on their own '
                  'once the two versions match again.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: T.muted,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _Fact(
                label: 'This app speaks',
                value: 'sync $kSyncProtocol',
              ),
              _Fact(
                label: 'This server speaks',
                value: 'sync ${server.speaks}',
              ),
              _Fact(
                label: compatibility == Compatibility.appTooOld
                    ? 'The server needs at least'
                    : 'This app needs at least',
                value: compatibility == Compatibility.appTooOld
                    ? 'sync ${server.minClient}'
                    : 'sync $kMinServerProtocol',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onClose,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: T.bgSolid,
                    minimumSize: const Size(96, 40),
                  ),
                  child: const Text(
                    'Got it',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "label: value" line. The numbers are shown rather than hidden behind the
/// prose: this is the one screen where somebody debugging a deployment needs to
/// read the actual figures off it.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: T.muted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              color: T.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
