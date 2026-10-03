import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import '../auth/verification_links.dart';
import 'account_page.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.session,
    required this.links,
    required this.onExploreDemo,
  });
  final SessionController session;
  final VerificationLinks links;
  final VoidCallback onExploreDemo;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  final _token = TextEditingController();
  Timer? _ticker;
  String? _inputMessage;

  @override
  void initState() {
    super.initState();
    _receiveLink();
    widget.links.addListener(_receiveLink);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _receiveLink() {
    final message = widget.links.message;
    final pending = widget.links.takePending();
    if (pending != null) {
      _token.text = pending;
      _inputMessage = null;
    } else if (message == null) {
      _token.clear();
    }
    if (message == VerificationLinks.invalidLink) {
      _token.clear();
      _inputMessage = message;
    }
  }

  void _clear() {
    _token.clear();
    widget.links.clear();
    setState(() => _inputMessage = null);
  }

  void _confirm() {
    if (widget.session.verificationBusy) return;
    final token = parseVerificationToken(
      _token.text,
      trustedOrigin: widget.links.trustedOrigin,
    );
    _clear();
    FocusScope.of(context).unfocus();
    if (token == null) {
      setState(
        () => _inputMessage =
            'Enter a valid 43-character verification token or a trusted app verification link, not your password.',
      );
      return;
    }
    widget.session.confirmEmail(token);
  }

  @override
  void dispose() {
    widget.links.removeListener(_receiveLink);
    _ticker?.cancel();
    _token.clear();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final busy = session.verificationBusy;
    final cooldown = session.resendCooldownSeconds;
    return AccountFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.mark_email_unread_outlined,
            size: 56,
            color: Color(0xFF005B7F),
          ),
          const SizedBox(height: 16),
          Text(
            'Verify your email',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          SelectableText(session.user!.email),
          const SizedBox(height: 12),
          const Text(
            'Use the token sent to this email. Tokens expire after 30 minutes and can be used once. Confirm only while signed in to the matching account. Verification does not grant organization membership or project access.',
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('verification-token'),
            controller: _token,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Verification token or trusted link',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          if (_inputMessage ?? session.message case final message?)
            Semantics(
              liveRegion: true,
              child: Text(message, key: const Key('verification-message')),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('confirm-email'),
            onPressed: busy ? null : _confirm,
            child: Text(busy ? 'Please wait…' : 'Confirm email'),
          ),
          TextButton(
            onPressed: _clear,
            child: const Text('Clear token / cancel input'),
          ),
          OutlinedButton(
            key: const Key('resend-verification'),
            onPressed: busy || cooldown > 0
                ? null
                : () {
                    _clear();
                    session.resendVerification();
                  },
            child: Text(
              cooldown > 0
                  ? 'Resend available in ${cooldown}s'
                  : 'Resend verification email',
            ),
          ),
          TextButton(
            key: const Key('check-verification'),
            onPressed: busy
                ? null
                : () {
                    _clear();
                    session.refreshUser();
                  },
            child: const Text('Check verification status'),
          ),
          const Text(
            'Mail may be delayed or unavailable. Resend is limited locally to once per 60 seconds; server limits still apply.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () {
              _clear();
              session.logout();
            },
            child: const Text('Sign out'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () {
                    _clear();
                    widget.onExploreDemo();
                  },
            child: const Text(demoLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
