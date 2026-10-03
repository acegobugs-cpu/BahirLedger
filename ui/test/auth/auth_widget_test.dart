import 'dart:async';
import 'dart:convert';

import 'package:bahir_ledger/main.dart';
import 'package:bahir_ledger/src/auth/api_config.dart';
import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:bahir_ledger/src/pages/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const user = {
  'id': 'user-1',
  'email': 'person@example.com',
  'displayName': 'Local User',
};

void main() {
  late int calls;
  late DateTime now;
  setUp(() {
    calls = 0;
    now = DateTime.utc(2026, 10, 3);
  });

  Future<http.Response> success(http.Request request) async {
    if (request.url.path.endsWith('/login') ||
        request.url.path.endsWith('/register')) {
      return http.Response(
        jsonEncode({
          'accessToken': 'private-token',
          'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
          'user': user,
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/logout')) return http.Response('', 204);
    return http.Response(jsonEncode(user), 200);
  }

  Future<SessionController> mount(
    WidgetTester tester, {
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    final session = SessionController(
      transport: AuthTransport(
        config: ApiConfig('https://api.example.com'),
        client: MockClient((request) {
          calls++;
          return (handler ?? success)(request);
        }),
        clock: () => now,
      ),
      clock: () => now,
    );
    await tester.pumpWidget(
      BahirLedgerApp(session: session, demoBuilder: (_) => const Shell()),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('email')),
      'person@example.com',
    );
    await tester.enterText(find.byKey(const Key('password')), 'secret');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pump();
  }

  testWidgets('root starts signed out and rejects empty/invalid input', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(Shell), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('sign-in')));
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byKey(const Key('email')), 'not-an-email');
    await tester.ensureVisible(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
    'loading disables repeat submit and clears password immediately',
    (tester) async {
      final pending = Completer<http.Response>();
      await mount(tester, handler: (_) => pending.future);
      await submit(tester);
      expect(find.text('Signing in…'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('sign-in'))).onPressed,
        isNull,
      );
      final password = tester.widget<TextFormField>(
        find.byKey(const Key('password')),
      );
      expect(password.controller!.text, isEmpty);
      expect(password.enabled, isFalse);
      expect(calls, 1);
      pending.complete(http.Response('private server diagnostics', 401));
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.text('private server diagnostics'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('sign-in'))).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'success shows me identity, no tenant projects; signout returns to form',
    (tester) async {
      await mount(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
      expect(find.text('Local User'), findsOneWidget);
      expect(find.text('person@example.com'), findsOneWidget);
      expect(find.text('No organization assigned'), findsOneWidget);
      expect(find.byType(Shell), findsNothing);
      expect(calls, 2);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsNothing);
      expect(find.text('You have signed out.'), findsOneWidget);
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(calls, 3);
    },
  );

  testWidgets(
    'unreachable logout clears account and displays revocation warning',
    (tester) async {
      await mount(
        tester,
        handler: (request) => request.url.path.endsWith('/logout')
            ? Future.error(http.ClientException('private-token'))
            : success(request),
      );
      await submit(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sign out'));
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text(SessionController.revocationWarning), findsOneWidget);
      expect(find.text('Local User'), findsNothing);
    },
  );

  testWidgets(
    'signup route rebuilds for loading, failure, and account success',
    (tester) async {
      final pending = Completer<http.Response>();
      var registrationAttempts = 0;
      await mount(
        tester,
        handler: (request) {
          if (request.url.path.endsWith('/register')) {
            registrationAttempts++;
            if (registrationAttempts == 1) return pending.future;
          }
          return success(request);
        },
      );
      final signupLink = find.text("Don't have an account? Sign up");
      await tester.ensureVisible(signupLink);
      await tester.pumpAndSettle();
      await tester.tap(signupLink);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('userName')), 'Local User');
      await tester.enterText(
        find.byKey(const Key('email')),
        'person@example.com',
      );
      await tester.enterText(find.byKey(const Key('password')), 'secret');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Sign up');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      pending.complete(http.Response('private details', 409));
      await tester.pumpAndSettle();
      expect(
        find.text('Email is already registered. Please sign in.'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('password')), 'secret');
      await tester.pumpAndSettle();
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
      expect(find.text('Local User'), findsOneWidget);
      expect(calls, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('expiry while resumed returns to sign-in', (tester) async {
    await mount(tester);
    await submit(tester);
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 30));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text(AuthTransport.expired), findsOneWidget);
    expect(find.text('Your account'), findsNothing);
  });

  testWidgets(
    'demo is explicit, stays labeled on child screens, returns to sign-in',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(find.text(demoLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(demoLabel));
      await tester.pumpAndSettle();
      expect(find.byType(Shell), findsOneWidget);
      const disclaimer =
          'Local sample data only. No tenant access, membership, or authorization is granted.';
      expect(find.text(disclaimer), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Add Project'),
      );
      await tester.pumpAndSettle();
      expect(find.text('New Project'), findsOneWidget);
      expect(find.text(disclaimer), findsOneWidget);
      await tester.tap(find.byTooltip('Exit demo'));
      await tester.pumpAndSettle();
      expect(find.byType(Shell), findsNothing);
      expect(find.byKey(const Key('sign-in')), findsOneWidget);
      expect(calls, 0);
    },
  );

  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets('responsive sign-in and account at $size with large text', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await mount(tester);
      expect(tester.takeException(), isNull);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Your account'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-in')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disposing the app during login ignores the response', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final session = await mount(tester, handler: (_) => pending.future);
    await submit(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete(
      await success(
        http.Request(
          'POST',
          Uri.https('api.example.com', '/api/v1/auth/login'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(session.user, isNull);
    expect(tester.takeException(), isNull);
  });
}
