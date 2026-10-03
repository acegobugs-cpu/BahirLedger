import 'package:flutter/material.dart';

import 'auth/api_config.dart';
import 'auth/auth_transport.dart';
import 'auth/session_controller.dart';
import 'pages/account_page.dart';
import 'pages/sign_in_page.dart';
import 'pages/sign_up_page.dart';

/// Owns and disposes the supplied session (or creates one at the app root).
class BahirLedgerApp extends StatefulWidget {
  const BahirLedgerApp({super.key, this.session, required this.demoBuilder});
  final SessionController? session;
  final WidgetBuilder demoBuilder;

  @override
  State<BahirLedgerApp> createState() => _BahirLedgerAppState();
}

class _BahirLedgerAppState extends State<BahirLedgerApp>
    with WidgetsBindingObserver {
  SessionController? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configure();
  }

  void _configure() {
    try {
      _session =
          widget.session ??
          SessionController(
            transport: AuthTransport(config: ApiConfig.fromEnvironment()),
          );
    } on FormatException {
      // Never echo a misconfigured origin: it could contain credentials.
      _session = null;
    }
  }

  @override
  void didUpdateWidget(covariant BahirLedgerApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session != oldWidget.session) {
      _session?.dispose();
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
    _session?.dispose();
    super.dispose();
  }

  void signUp(BuildContext context) => Navigator.of(context).pushReplacementNamed('/sign-up');
  void signIn(BuildContext context) => Navigator.of(context).pushReplacementNamed('/sign-in');

  @override
  Widget build(BuildContext context) => MaterialApp(
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
      '/sign-up': (context) => _authPage(context, showSignUp: true),
      '/sign-in': (context) => _authPage(context),
      '/demo': (_) => _DemoRoute(builder: widget.demoBuilder)},
    home: Builder(builder: (context) => _authPage(context)),
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
                TextButton(
                  onPressed: exploreDemo,
                  child: const Text(demoLabel),
                ),
              ],
            ),
          );
        }
        return ListenableBuilder(
          listenable: session,
          builder: (context, _) => session.state == SessionState.signedIn
              ? AccountPage(session: session, onExploreDemo: exploreDemo)
              : showSignUp
              ? SignUpPage(session: session, onSignIn: () => signIn(context), onExploreDemo: exploreDemo)
              : SignInPage(session: session, onSignUp:() => signUp(context), onExploreDemo: exploreDemo,),
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
