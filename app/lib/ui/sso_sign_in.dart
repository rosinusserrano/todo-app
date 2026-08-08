// The "sign in with SSO" dialog.
//
// The whole visible half of the device grant: a short code, somewhere to type
// it, and a spinner until the provider says it has been approved. The user may
// well approve it on a different device entirely, which is the point of this
// flow and the reason nothing here waits on a redirect.
//
// A dialog rather than a sheet, like the composer and the pickers: modal by
// nature, and over in the time it takes to approve something in a browser.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sync/oidc_client.dart';
import '../theme.dart';

/// Runs the flow. Returns the tokens on success, null if it was dismissed.
Future<OidcTokens?> showSsoSignIn(BuildContext context, AuthConfig config) {
  return showDialog<OidcTokens>(
    context: context,
    // Deliberately not dismissible by tapping outside: the poll is running and
    // a stray tap would abandon a sign-in the user has already half-completed
    // in a browser.
    barrierDismissible: false,
    builder: (context) => _SignInDialog(config: config),
  );
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.config});

  final AuthConfig config;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  OidcClient? _client;
  DeviceCode? _code;
  String? _error;
  bool _cancelled = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    _client?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final client = OidcClient(config: widget.config);
    _client = client;

    try {
      final code = await client.requestCode();
      if (!mounted) return;
      setState(() => _code = code);

      final tokens = await client.awaitApproval(
        code,
        cancelled: () => _cancelled,
      );
      if (!mounted) return;
      Navigator.pop(context, tokens);
    } on OidcAuthException catch (e) {
      if (!mounted || _cancelled) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted || _cancelled) return;
      setState(() => _error = 'Could not reach the sign-in provider. $e');
    }
  }

  Future<void> _copyLink() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code.bestUri));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: T.bgSolid,
      title: const Text('Sign in', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 300, child: _body()),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context);
          },
          child: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
        ),
        if (_code != null && _error == null)
          FilledButton(
            onPressed: _copyLink,
            child: Text(
              _copied ? 'Copied' : 'Copy link',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return Text(
        _error!,
        style: const TextStyle(fontSize: 12, color: T.danger, height: 1.4),
      );
    }

    final code = _code;
    if (code == null) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Asking the provider…', style: TextStyle(fontSize: 12.5)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Open this address in a browser — on this device or any other — and '
          'enter the code:',
          style: TextStyle(fontSize: 12, color: T.muted, height: 1.4),
        ),
        const SizedBox(height: 12),
        SelectableText(
          code.verificationUri,
          style: const TextStyle(fontSize: 12.5, color: T.accent),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            // Selectable, because the browser may be on this machine and
            // retyping a code you can see is a silly thing to ask.
            child: SelectableText(
              code.userCode,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: T.text,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Waiting for approval…',
              style: TextStyle(fontSize: 11.5, color: T.muted),
            ),
          ],
        ),
      ],
    );
  }
}
