import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/onboarding.dart';
import '../auth/session_controller.dart';

const demoLabel = 'Explore demo (local sample data)';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.session,
    required this.onExploreDemo,
  });

  final SessionController session;
  final VoidCallback onExploreDemo;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _activate = false;
  bool _reveal = false;
  int _privateRevision = 0;
  SessionController get session => widget.session;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _privateRevision = session.privateRevision;
    session.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !session.accountBusy) session.refreshOnboarding();
    });
  }

  void _changed() {
    if (_privateRevision != session.privateRevision) {
      _privateRevision = session.privateRevision;
      _code.clear();
      _reveal = false;
      _activate = false;
    }
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != session) {
      oldWidget.session.removeListener(_changed);
      oldWidget.session.leaveOnboarding();
      _name.clear();
      _email.clear();
      _code.clear();
      _activate = false;
      _reveal = false;
      _attach();
    }
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    session.leaveOnboarding();
    _code.clear();
    _code.dispose();
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Widget _button(String label, VoidCallback action, {String? key}) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: OutlinedButton(
      key: key == null ? null : Key(key),
      onPressed: session.accountBusy ? null : action,
      child: Text(label, textAlign: TextAlign.center),
    ),
  );

  List<Widget> _organization() {
    final value = session.onboarding;
    final membership = value?.membership;
    final setup = value?.bootstrap;
    return [
      const Divider(height: 32),
      Text('Organization', style: Theme.of(context).textTheme.titleLarge),
      if (session.onboardingBusy) ...[
        const LinearProgressIndicator(),
        const Text('Checking organization status…'),
      ],
      if (session.onboardingMessage case final message?)
        Semantics(liveRegion: true, child: Text(message)),
      if (value == null && !session.onboardingBusy)
        const Text('Organization status is not confirmed. Refresh to retry.'),
      if (membership != null) ...[
        Text(membership.organizationName),
        Text('Organization ID: ${membership.organizationId}'),
        Text('Role: ${membership.role.name.toUpperCase()}'),
        const Text('Membership only; project access not configured.'),
        if (session.isOrganizationOwner) ..._owner(),
      ] else if (value != null) ...[
        const Text('No organization assigned'),
        if (setup == null) ...[
          const Text(
            'Save a pending setup first. This grants no membership or owner access.',
          ),
          TextField(
            key: const Key('organization-name'),
            controller: _name,
            enabled: !session.accountBusy,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Organization name'),
          ),
          _button(
            'Save pending setup',
            () => session.saveOrganization(_name.text),
          ),
        ] else ...[
          Text('Pending setup: ${setup.name}'),
          Text(
            'Resume before ${setup.expiresAt.toIso8601String()} (UTC). Pending setup lasts 24 hours; it is not membership.',
          ),
          TextField(
            key: const Key('pending-organization-name'),
            controller: _name,
            enabled: !session.accountBusy,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Updated organization name',
            ),
          ),
          _button(
            'Update pending name',
            () => session.saveOrganization(_name.text),
          ),
          if (!_activate)
            _button(
              'Activate organization',
              () => setState(() => _activate = true),
            )
          else ...[
            Text(
              'Create ${setup.name} and become its OWNER? Project access will not be configured.',
            ),
            _button('Confirm activation', session.activateOrganization),
            _button('Not now', () => setState(() => _activate = false)),
          ],
          _button('Cancel pending setup', session.cancelOrganization),
        ],
        const Divider(height: 24),
        const Text('Join by invitation'),
        const Text(
          'Use the private code shared by an owner. Only the exact verified recipient email can preview and accept it. Existing members cannot switch organizations.',
        ),
        if (session.invitationPreview case final preview?) ...[
          Text('Invitation to ${preview.organizationName}'),
          Text('Expires ${preview.expiresAt.toIso8601String()} (UTC)'),
          _button('Accept invitation', session.acceptInvitation),
        ] else ...[
          TextField(
            key: const Key('invitation-code'),
            controller: _code,
            enabled: !session.accountBusy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: const InputDecoration(
              labelText: 'Private invitation code',
            ),
          ),
          _button('Preview invitation', () {
            final code = _code.text.trim();
            _code.clear();
            session.previewInvitation(code);
          }),
        ],
        TextButton(
          onPressed: session.dismissInvitation,
          child: const Text('Cancel invitation entry'),
        ),
      ],
      _button('Refresh organization status', session.refreshOnboarding),
      const Text(
        'If a response was lost, an action may already have completed. Refresh status before retrying.',
      ),
    ];
  }

  List<Widget> _owner() => [
    const Divider(height: 24),
    const Text('Organization invitations'),
    const Text(
      'Codes expire after 7 days and can be used once. No invitation email is sent. Share the code manually and privately with the intended recipient.',
    ),
    TextField(
      key: const Key('invite-email'),
      controller: _email,
      enabled: !session.accountBusy,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(labelText: 'Recipient email'),
    ),
    _button('Create invitation code', () => session.invite(_email.text)),
    if (session.shareCode != null) ...[
      const Text(
        'One-time display. Save it privately now; it disappears on dismissal, another action, sign-out, or expiry. Clear your clipboard after sharing.',
      ),
      Text(
        _reveal ? session.shareCode! : '••••••••••••••••',
        key: const Key('share-code'),
      ),
      _button(
        _reveal ? 'Hide code' : 'Reveal code',
        () => setState(() => _reveal = !_reveal),
      ),
      _button('Copy code', () async {
        session.checkExpiry();
        final code = session.shareCode;
        if (code == null) return;
        try {
          await Clipboard.setData(ClipboardData(text: code));
        } catch (_) {
          // Clipboard diagnostics must never expose a private code.
        }
      }),
      TextButton(
        onPressed: session.dismissInvitation,
        child: const Text('Dismiss code'),
      ),
    ],
    if (session.invitations.isEmpty) const Text('No invitations.'),
    // The API has no pagination contract. Bound rendering, not authorization.
    for (final invitation in session.invitations.take(100)) ...[
      const Divider(),
      Text(invitation.email),
      Text(
        '${invitation.status.name.toUpperCase()} · expires ${invitation.expiresAt.toIso8601String()} (UTC)',
      ),
      if (invitation.status == InvitationStatus.pending)
        _button(
          'Revoke ${invitation.email}',
          () => session.revokeInvitation(invitation.id),
        ),
    ],
    if (session.invitations.length > 100)
      const Text(
        'Showing the first 100 invitations. The remaining invitations are not displayed in this client.',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    if (user == null || !user.emailVerified) return const SizedBox.shrink();
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
          ..._organization(),
          const SizedBox(height: 16),
          const Text(
            'Sessions last up to 30 minutes. Closing or reloading the app signs you out locally.',
          ),
          const SizedBox(height: 24),
          const Text('Email verified'),
          if (session.message case final message?) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(message)),
          ],
          TextButton(
            onPressed: session.accountBusy ? null : session.refreshUser,
            child: const Text('Check verification status'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: session.logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              session.dismissInvitation();
              widget.onExploreDemo();
            },
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
