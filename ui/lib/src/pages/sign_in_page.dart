import 'package:flutter/material.dart';

import '../auth/session_controller.dart';
import 'account_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.session,
    required this.onSignUp,
    required this.onExploreDemo,
    this.verificationMessage,
    this.onCancelVerification,
  });
  final SessionController session;
  final VoidCallback onSignUp;
  final VoidCallback onExploreDemo;
  final String? verificationMessage;
  final VoidCallback? onCancelVerification;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  void _submit() {
    if (widget.session.isSigningIn) return;
    if (!_form.currentState!.validate()) return;
    final password = _password.text;
    _password.clear();
    FocusScope.of(context).unfocus();
    widget.session.login(_email.text, password);
  }

  @override
  void dispose() {
    _password.clear();
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.isSigningIn;
    return AccountFrame(
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Sign in', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const Text(
              'Sign in with your account email and password. Unverified accounts can verify their email after signing in.',
            ),
            if (widget.verificationMessage case final message?) ...[
              const SizedBox(height: 12),
              Text(message),
              TextButton(
                onPressed: widget.onCancelVerification,
                child: const Text('Cancel pending verification'),
              ),
            ],
            const SizedBox(height: 24),
            TextFormField(
              key: const Key('email'),
              controller: _email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your email.';
                }
                if (!RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value.trim())) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('password'),
              controller: _password,
              enabled: !busy,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: busy
                      ? null
                      : () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
            ),
            if (widget.session.message case final message?) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  key: const Key('session-message'),
                  style: const TextStyle(color: Color(0xFF803613)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('sign-in'),
              onPressed: busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: busy
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Flexible(child: Text('Signing in…')),
                        ],
                      )
                    : const Text('Sign in'),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'New here? Create an account below. Signing in or verifying email does not grant organization membership or project access.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: busy ? null : widget.onSignUp,
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 12, height: 1.5),
              ),
              child: const Text(
                'Don\'t have an account? Sign up',
                textAlign: TextAlign.center,
              ),
            ),
            TextButton(
              onPressed: busy ? null : widget.onExploreDemo,
              child: const Text(demoLabel, textAlign: TextAlign.center),
            ),
            const Text(
              'Demo data is local only, not an authorized tenant workspace.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
