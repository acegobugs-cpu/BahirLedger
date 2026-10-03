import 'package:flutter/material.dart';

import 'auth/api_config.dart';
import 'auth/auth_transport.dart';
import 'auth/session_controller.dart';
import 'auth/verification_links.dart';
import 'pages/account_page.dart';
import 'pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';
import 'pages/verify_email_page.dart';

/// Owns and disposes the supplied session (or creates one at the app root).
class BahirLedgerApp extends StatefulWidget {
  const BahirLedgerApp({
    super.key,
    this.session,
    this.verificationLinks,
    required this.demoBuilder,
  });
  final SessionController? session;
  final VerificationLinks? verificationLinks;
  final WidgetBuilder demoBuilder;

  @override
  State<BahirLedgerApp> createState() => _BahirLedgerAppState();
}

class _BahirLedgerAppState extends State<BahirLedgerApp>
    with WidgetsBindingObserver {
  SessionController? _session;
  late final VerificationLinks _links;
  final _navigator = GlobalKey<NavigatorState>();
  SessionState? _previousState;
  int _linkRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _links = widget.verificationLinks ?? VerificationLinks();
    _linkRevision = _links.revision;
    _links.addListener(_linkChanged);
    _configure();
  }

  void _configure() {
    try {
      _session =
          widget.session ??
          SessionController(
            transport: AuthTransport(config: ApiConfig.fromEnvironment()),
          );
      _previousState = _session!.state;
      _session!.addListener(_sessionChanged);
    } on FormatException {
      // Never echo a misconfigured origin: it could contain credentials.
      _session = null;
    }
  }

  void _sessionChanged() {
    final session = _session!;
    if ((_previousState == SessionState.signedIn &&
            session.state == SessionState.signedOut) ||
        session.user?.emailVerified == true) {
      _links.clear();
    }
    _previousState = session.state;
  }

  void _linkChanged() {
    if (!mounted) return;
    setState(() {});
    if (_links.revision == _linkRevision) return;
    _linkRevision = _links.revision;
    if (_session?.user?.emailVerified == true &&
        (_links.hasPending || _links.message != null)) {
      _links.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navigator.currentState?.popUntil((route) => route.isFirst);
    });
  }

  @override
  Future<bool> didPushRoute(String route) async => _handlePlatformRoute(route);

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async => _handlePlatformRoute(routeInformation.uri.toString());

  bool _handlePlatformRoute(String route) {
    if (_links.captureRoute(route)) return true;
    // A browser hash event may arrive after our listener has scrubbed the URL.
    // Treat its clean root as returning to the gate, not a second auth page
    // which could consume/obscure the pending input on the first page.
    if (route == '/' || route == '') {
      _navigator.currentState?.popUntil((route) => route.isFirst);
      return true;
    }
    return !const {'/sign-in', '/sign-up', '/demo'}.contains(route);
  }

  @override
  void didUpdateWidget(covariant BahirLedgerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session) {
      _session?.removeListener(_sessionChanged);
      _session?.dispose();
      _links.clear();
      _configure();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _session?.checkExpiry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links.removeListener(_linkChanged);
    _links.dispose();
    _session?.removeListener(_sessionChanged);
    _session?.dispose();
    super.dispose();
  }

  void signUp(BuildContext context) =>
      Navigator.of(context).pushReplacementNamed('/sign-up');
  void signIn(BuildContext context) =>
      Navigator.of(context).pushReplacementNamed('/sign-in');

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    // Never use defaultRouteName: on web it may contain a secret. The platform
    // adapter has already captured and replaced the incoming URL synchronously.
    initialRoute: '/',
    onGenerateInitialRoutes: (_) => [
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (context) => _authPage(context),
      ),
    ],
    onUnknownRoute: (_) => MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/'),
      builder: (context) => _authPage(context),
    ),
    title: 'BahirLedger',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF005B7F),
        primary: const Color(0xFF005B7F),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    routes: {
      '/': (context) => _authPage(context),
      '/sign-up': (context) => _authPage(context, showSignUp: true),
      '/sign-in': (context) => _authPage(context),
      '/verify-email': (context) => _authPage(context),
      '/demo': (_) => _DemoRoute(builder: widget.demoBuilder),
    },
  );

  Widget _authPage(BuildContext context, {bool showSignUp = false}) {
    void exploreDemo() => Navigator.of(context).pushNamed('/demo');
    final session = _session;
    if (session == null) {
      return AccountFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sign-in configuration unavailable',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Set API_BASE_URL to a valid HTTPS API origin. HTTP is allowed only for loopback development in debug builds.',
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: exploreDemo, child: const Text(demoLabel)),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([session, _links]),
      builder: (context, _) => session.state == SessionState.signedIn
          ? session.user!.emailVerified
                ? AccountPage(session: session, onExploreDemo: exploreDemo)
                : VerifyEmailPage(
                    session: session,
                    links: _links,
                    onExploreDemo: exploreDemo,
                  )
          : showSignUp
          ? SignUpPage(
              session: session,
              onSignIn: () => signIn(context),
              onExploreDemo: exploreDemo,
              verificationMessage: _links.message,
              onCancelVerification: _links.clear,
            )
          : SignInPage(
              session: session,
              onSignUp: () => signUp(context),
              onExploreDemo: exploreDemo,
              verificationMessage: _links.message,
              onCancelVerification: _links.clear,
            ),
    );
  }
}

/// A separate navigator keeps the disclaimer visible on every sample screen.
class _DemoRoute extends StatefulWidget {
  const _DemoRoute({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_DemoRoute> createState() => _DemoRouteState();
}

class _DemoRouteState extends State<_DemoRoute> {
  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Exit demo',
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text('Local demo'),
    ),
    body: Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFE2EEF5),
          padding: const EdgeInsets.all(12),
          child: const Text(
            'Local sample data only. No tenant access, membership, or authorization is granted.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: NavigatorPopHandler<void>(
            onPopWithResult: (_) => _navigator.currentState!.pop(),
            child: Navigator(
              key: _navigator,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: widget.builder),
            ),
          ),
        ),
      ],
    ),
  );
}
