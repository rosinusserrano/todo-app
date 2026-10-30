// The small prompts around a server token, shared by the two pages that mint
// them: People on this server (device tokens, admin only) and API tokens
// (inbox tokens for scripts, anyone's own).
//
// Dialogs rather than sheets, unlike the pages themselves: they are transient
// and genuinely modal, and one of them must be hard to dismiss by accident -
// **a token is shown once**. The server stores only a hash, so
// [showIssuedToken] is the single moment that string exists anywhere.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

Future<String?> promptTokenName(
  BuildContext context, {
  required String title,
  required String hint,
  required String help,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(title, style: const TextStyle(fontSize: T.fsBody)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(help,
                style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              style: const TextStyle(fontSize: T.fsBody),
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                counterText: '',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (name == null || name.isEmpty) ? null : name;
}

/// The one and only appearance of a token. Deliberately hard to dismiss by
/// accident - no barrier dismiss - because closing it loses the string.
/// [copyText] is what the copy button takes, when that is more than the token
/// (an API token's two .env lines); [footer] says where the token goes.
Future<void> showIssuedToken(
  BuildContext context, {
  required String token,
  required String subtitle,
  required String footer,
  String? copyText,
  String copyLabel = 'Copy & close',
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: const Text('Token', style: TextStyle(fontSize: T.fsBody)),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: const TextStyle(fontSize: T.fsMeta, color: T.muted)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(T.s2),
              decoration: BoxDecoration(
                color: T.surface,
                borderRadius: BorderRadius.circular(T.radius),
              ),
              child: SelectableText(
                token,
                style: const TextStyle(
                  fontSize: T.fsLabel,
                  height: 1.35,
                  fontFamily: T.fontMono,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'The server keeps only a hash of this, so it cannot be shown '
              'again. If it is lost, issue another and revoke this one.',
              style: TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
            ),
            const SizedBox(height: 8),
            SelectableText(
              footer,
              style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: copyText ?? token));
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(copyLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String body,
  required String danger,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: T.bgSolid,
      title: Text(title, style: const TextStyle(fontSize: T.fsBody)),
      content: SizedBox(
        width: 300,
        child: Text(body,
            style: const TextStyle(fontSize: T.fsMeta, color: T.muted, height: 1.4)),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: T.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(danger),
        ),
      ],
    ),
  );
  return ok ?? false;
}
