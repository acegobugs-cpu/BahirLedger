import 'package:flutter/material.dart';

import '../auth/session_controller.dart';

const demoLabel = 'Explore demo (local sample data)';

class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.session,
    required this.onExploreDemo,
  });

  final SessionController session;
  final VoidCallback onExploreDemo;

  @override
  Widget build(BuildContext context) {
    final user = session.user!;
    return AccountFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.account_circle_outlined,
            size: 56,
            color: Color(0xFF005B7F),
          ),
          const SizedBox(height: 20),
          Text(
            'Your account',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          SelectableText(
            user.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SelectableText(user.email),
          const SizedBox(height: 8),
          SelectableText(
            'Account ID: ${user.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          const Text(
            'No organization assigned',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is an account-only sign-in. Organization membership is not available in this client yet. Signing in does not grant access to a tenant workspace or project data.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Sessions last up to 30 minutes. Closing or reloading the app signs you out locally.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: session.logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onExploreDemo,
            child: const Text(demoLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

/// Shared readable, scrollable layout for phones, keyboards, and wide desktops.
class AccountFrame extends StatelessWidget {
  const AccountFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF1F6FA),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.layers_outlined,
                      color: Color(0xFF005B7F),
                      size: 32,
                    ),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'BahirLedger',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF005B7F),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Color(0xFFD7E4EC)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
