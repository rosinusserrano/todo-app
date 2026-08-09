// The "sign in with SSO" dialog.
//
// The visible half of the device grant. The browser is opened *for* the user,
// at the provider's `verification_uri_complete` - the URL with the code already
// in it - so the experience is the ordinary one: your identity provider's own
// login page, Google or otherwise, then a single "grant access" confirmation.
// Nobody types a code unless something went wrong.
//
// The code is still shown, and still selectable, because it is the fallback
// that makes this flow worth having: a machine with no usable browser, a
// launcher that silently fails, or simply wanting to approve it on your phone
// instead. The dialog keeps polling either way, so approval anywhere finishes
// the sign-in here.
//
// A dialog rather than a sheet, like the composer and the pickers: modal by
// nature, and over in the time it takes to approve something in a browser.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Whether the browser was opened for them. False means they have to use the
  /// code, and the wording changes to say so rather than claiming otherwise.
  bool _opened = false;

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

      // Straight to the provider, before the poll starts waiting.
      await _open(code);

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

  /// Send them to the provider. Never throws: a launcher that fails is a
  /// fallback to the code on screen, not an error - the sign-in is still live.
  Future<void> _open(DeviceCode code) async {
    try {
      final ok = await launchUrl(
        Uri.parse(code.bestUri),
        mode: LaunchMode.externalApplication,
      );
      if (mounted) setState(() => _opened = ok);
    } catch (_) {
      if (mounted) setState(() => _opened = false);
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
        if (_code != null && _error == null) ...[
          TextButton(
            onPressed: _copyLink,
            child: Text(
              _copied ? 'Copied' : 'Copy link',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          // The primary action once the browser is already open is to open it
          // again - the window may have been dismissed, or landed behind this
          // always-on-top one.
          FilledButton(
            onPressed: () => _open(_code!),
            child: Text(
              _opened ? 'Open again' : 'Open browser',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
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
        Text(
          _opened
              ? 'Finish signing in in your browser. It should be open already '
                    '— check that the code below matches.'
              : 'Your browser did not open. Go to this address on any device '
                    'and enter the code:',
          style: const TextStyle(fontSize: 12, color: T.muted, height: 1.4),
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
