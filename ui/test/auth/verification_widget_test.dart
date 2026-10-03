import 'dart:async';
import 'dart:convert';

import 'package:bahir_ledger/src/app.dart';
import 'package:bahir_ledger/src/auth/api_config.dart';
import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:bahir_ledger/src/auth/verification_links.dart';
import 'package:bahir_ledger/src/pages/account_page.dart';
import 'package:bahir_ledger/src/pages/verify_email_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'verification_test.dart'
    show
        FakeLinkSource,
        pendingUser,
        verifiedUser,
        verificationToken,
        epoch,
        jsonResponse,
        signedInResponse;

void main() {
  late SessionController session;
  late VerificationLinks links;
  late FakeLinkSource source;
  late List<http.Request> requests;
  late DateTime now;

  Future<void> mount(
    WidgetTester tester, {
    String? initialUrl,
    Object? handshake = pendingUser,
    Object? me = pendingUser,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    now = epoch;
    requests = [];
    source = FakeLinkSource(initialUrl);
    links = VerificationLinks(source: source);
    session = SessionController(
      clock: () => now,
      transport: AuthTransport(
        config: ApiConfig('https://api.example.com'),
        clock: () => now,
        client: MockClient((request) async {
          requests.add(request);
          if (handler != null) return handler(request);
          if (request.url.path.endsWith('/login') ||
              request.url.path.endsWith('/register')) {
            return signedInResponse(user: handshake);
          }
          if (request.url.path.endsWith('/me')) return jsonResponse(me);
          if (request.url.path.endsWith('/confirm')) {
            return jsonResponse(verifiedUser);
          }
          return http.Response('', 204);
        }),
      ),
    );
    await tester.pumpWidget(
      BahirLedgerApp(
        session: session,
        verificationLinks: links,
        demoBuilder: (_) => const Text('Unprotected sample'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester, {bool signup = false}) async {
    if (signup) {
      await tap(tester, find.text("Don't have an account? Sign up"));
      await tester.enterText(find.byKey(const Key('userName')), 'User');
    }
    await tester.enterText(
      find.byKey(const Key('email')),
      'person@example.com',
    );
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('sign-in')));
  }

  TextEditingController tokenController(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('verification-token')))
      .controller!;

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final signup in [true, false]) {
    testWidgets(
      'unverified ${signup ? 'signup' : 'login'} gates account until explicit confirmation',
      (tester) async {
        await mount(tester);
        await signIn(tester, signup: signup);
        expect(find.byType(VerifyEmailPage), findsOneWidget);
        expect(find.byType(AccountPage), findsNothing);
        expect(find.text('person@example.com'), findsOneWidget);
        expect(requests.length, 2);
        await tester.enterText(
          find.byKey(const Key('verification-token')),
          verificationToken,
        );
        await tap(tester, find.byKey(const Key('confirm-email')));
        expect(find.byType(AccountPage), findsOneWidget);
        expect(find.byType(VerifyEmailPage), findsNothing);
        expect(find.text('No organization assigned'), findsOneWidget);
        expect(find.text('Unprotected sample'), findsNothing);
        expect(requests.length, 3);
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'initial secret route is scrubbed and held through signup/signin, never auto-confirmed',
    (tester) async {
      final route = '/verify-email?token=$verificationToken';
      tester.platformDispatcher.defaultRouteNameTestValue = route;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await mount(tester, initialUrl: 'https://app.example.com/#$route');
      expect(source.url, 'https://app.example.com/#/');
      expect(source.scrubs, 1);
      expect(requests, isEmpty);
      expect(find.textContaining('Verification link ready'), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byKey(const Key('email'))),
        )!.settings.name,
        '/',
      );
      await tap(tester, find.text("Don't have an account? Sign up"));
      expect(links.hasPending, isTrue);
      await tap(tester, find.text('Already have an account? Sign in'));
      expect(links.hasPending, isTrue);
      await signIn(tester);
      expect(tokenController(tester).text, verificationToken);
      expect(links.hasPending, isFalse);
      expect(requests.length, 2);
      await tap(tester, find.byKey(const Key('confirm-email')));
      expect(find.byType(AccountPage), findsOneWidget);
      expect(requests.last.url.path, '/api/v1/auth/email-verification/confirm');
      expect(jsonDecode(requests.last.body), {'token': verificationToken});
      await unmount(tester);
    },
  );

  testWidgets(
    'navigation link prefills while signed in and leaves demo safely',
    (tester) async {
      await mount(tester);
      await signIn(tester);
      await tap(tester, find.text(demoLabel));
      expect(find.text('Unprotected sample'), findsOneWidget);
      source.navigate(
        'https://app.example.com/#/verify-email?token=$verificationToken',
      );
      expect(source.url, 'https://app.example.com/#/');
      await tester.pumpAndSettle();
      expect(find.byType(VerifyEmailPage), findsOneWidget);
      expect(tokenController(tester).text, verificationToken);
      expect(requests.length, 2);
      await unmount(tester);
    },
  );

  testWidgets(
    'framework navigation scrubs before route settings and requires sign-in',
    (tester) async {
      await mount(tester);
      await tester.binding.handlePushRoute(
        '/verify-email?token=$verificationToken',
      );
      await tester.pumpAndSettle();
      expect(source.scrubs, 1);
      expect(requests, isEmpty);
      expect(find.textContaining('Verification link ready'), findsOneWidget);
      expect(
        ModalRoute.of(
          tester.element(find.byKey(const Key('email'))),
        )!.settings.name,
        '/',
      );
      await signIn(tester);
      expect(tokenController(tester).text, verificationToken);
      await unmount(tester);
    },
  );

  testWidgets(
    'malformed and missing initial links are scrubbed without route crash or body echo',
    (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue =
          '/verify-email?token=private-invalid';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await mount(
        tester,
        initialUrl:
            'https://app.example.com/#/verify-email?token=private-invalid',
      );
      expect(source.scrubs, 1);
      expect(find.text(VerificationLinks.invalidLink), findsOneWidget);
      expect(find.textContaining('private-invalid'), findsNothing);
      await signIn(tester);
      expect(tokenController(tester).text, isEmpty);
      source.navigate('https://app.example.com/#/verify-email');
      await tester.pumpAndSettle();
      expect(find.text(VerificationLinks.invalidLink), findsOneWidget);
      expect(requests.length, 2);
      await unmount(tester);
    },
  );

  testWidgets(
    'cancel pending link and clear manual input remove ephemeral tokens',
    (tester) async {
      await mount(
        tester,
        initialUrl:
            'https://app.example.com/#/verify-email?token=$verificationToken',
      );
      await tap(tester, find.text('Cancel pending verification'));
      expect(links.hasPending, isFalse);
      expect(find.textContaining('Verification link ready'), findsNothing);
      await signIn(tester);
      expect(tokenController(tester).text, isEmpty);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        verificationToken,
      );
      await tap(tester, find.text('Clear token / cancel input'));
      expect(tokenController(tester).text, isEmpty);
      expect(requests.length, 2);
      await unmount(tester);
    },
  );

  testWidgets(
    'manual malformed/untrusted input is cleared without network lookup',
    (tester) async {
      await mount(tester);
      await signIn(tester);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        'https://evil.example/#/verify-email?token=$verificationToken',
      );
      await tap(tester, find.byKey(const Key('confirm-email')));
      expect(tokenController(tester).text, isEmpty);
      expect(find.textContaining('not your password'), findsOneWidget);
      expect(find.textContaining('evil.example'), findsNothing);
      expect(requests.length, 2);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        'https://app.example.com/#/verify-email?token=$verificationToken',
      );
      await tap(tester, find.byKey(const Key('confirm-email')));
      expect(find.byType(AccountPage), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets(
    'confirmation loading clears input and disables repeat/overlapping requests; logout remains available',
    (tester) async {
      final pending = Completer<http.Response>();
      await mount(
        tester,
        handler: (request) async {
          if (request.url.path.endsWith('/login')) return signedInResponse();
          if (request.url.path.endsWith('/me')) {
            return jsonResponse(pendingUser);
          }
          if (request.url.path.endsWith('/confirm')) return pending.future;
          return http.Response('', 204);
        },
      );
      await signIn(tester);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        verificationToken,
      );
      await tap(tester, find.byKey(const Key('confirm-email')));
      expect(tokenController(tester).text, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('confirm-email')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('resend-verification')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('check-verification')))
            .onPressed,
        isNull,
      );
      expect(requests.length, 3);
      await tap(tester, find.text('Sign out'));
      pending.complete(jsonResponse(verifiedUser));
      await tester.pumpAndSettle();
      expect(find.byType(AccountPage), findsNothing);
      expect(find.byKey(const Key('password')), findsOneWidget);
      expect(links.hasPending, isFalse);
      await unmount(tester);
    },
  );

  for (final status in [400, 401, 429, 503]) {
    testWidgets('confirmation $status safe visible failure, no token echo', (
      tester,
    ) async {
      await mount(
        tester,
        handler: (request) async {
          if (request.url.path.endsWith('/login')) return signedInResponse();
          if (request.url.path.endsWith('/me')) {
            return jsonResponse(pendingUser);
          }
          return http.Response('private detail $verificationToken', status);
        },
      );
      await signIn(tester);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        verificationToken,
      );
      await tap(tester, find.byKey(const Key('confirm-email')));
      expect(find.textContaining('private detail'), findsNothing);
      expect(find.textContaining(verificationToken), findsNothing);
      expect(find.byType(AccountPage), findsNothing);
      if (status == 401) {
        expect(find.text(AuthTransport.expired), findsOneWidget);
        expect(find.byKey(const Key('password')), findsOneWidget);
      } else {
        expect(tokenController(tester).text, isEmpty);
        expect(find.byKey(const Key('verification-message')), findsOneWidget);
      }
      await unmount(tester);
    });
  }

  for (final status in [204, 429, 503]) {
    testWidgets(
      'resend $status displays actual outcome and appropriate cooldown',
      (tester) async {
        await mount(
          tester,
          handler: (request) async {
            if (request.url.path.endsWith('/login')) return signedInResponse();
            if (request.url.path.endsWith('/me')) {
              return jsonResponse(pendingUser);
            }
            return http.Response('private detail', status);
          },
        );
        await signIn(tester);
        await tap(tester, find.byKey(const Key('resend-verification')));
        expect(find.textContaining('private detail'), findsNothing);
        expect(
          find.textContaining('Verification request accepted'),
          status == 204 ? findsOneWidget : findsNothing,
        );
        final button = tester.widget<OutlinedButton>(
          find.byKey(const Key('resend-verification')),
        );
        expect(button.onPressed, status == 503 ? isNotNull : isNull);
        if (status != 503) {
          now = epoch.add(const Duration(seconds: 60));
          await tester.pump(const Duration(seconds: 60));
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('resend-verification')),
                )
                .onPressed,
            isNotNull,
          );
        }
        await unmount(tester);
      },
    );
  }

  testWidgets(
    'signup mail failure directs user to sign in and resend, no retries',
    (tester) async {
      await mount(
        tester,
        handler: (_) async => http.Response('mail diagnostics', 503),
      );
      await signIn(tester, signup: true);
      expect(find.text(AuthTransport.signupMailUnavailable), findsOneWidget);
      expect(find.text('Already have an account? Sign in'), findsOneWidget);
      expect(find.byType(AccountPage), findsNothing);
      expect(find.byType(VerifyEmailPage), findsNothing);
      expect(requests.length, 1);
      await unmount(tester);
    },
  );

  testWidgets(
    'check-status and login me downgrade verified claims fail closed',
    (tester) async {
      var verified = false;
      await mount(
        tester,
        handler: (request) async {
          if (request.url.path.endsWith('/login')) {
            return signedInResponse(user: verifiedUser);
          }
          return jsonResponse({...pendingUser, 'emailVerified': verified});
        },
      );
      await signIn(tester);
      expect(find.byType(VerifyEmailPage), findsOneWidget);
      verified = true;
      await tap(tester, find.text('Check verification status'));
      expect(find.byType(AccountPage), findsOneWidget);
      verified = false;
      await tap(tester, find.text('Check verification status'));
      expect(find.byType(VerifyEmailPage), findsOneWidget);
      expect(find.byType(AccountPage), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'expiry clears pending/manual input and no token returns on next login',
    (tester) async {
      await mount(
        tester,
        initialUrl:
            'https://app.example.com/#/verify-email?token=$verificationToken',
      );
      await signIn(tester);
      expect(tokenController(tester).text, verificationToken);
      now = epoch.add(const Duration(minutes: 30));
      session.checkExpiry();
      await tester.pumpAndSettle();
      expect(links.hasPending, isFalse);
      expect(find.text(AuthTransport.expired), findsOneWidget);
      now = epoch;
      await signIn(tester);
      expect(tokenController(tester).text, isEmpty);
      await unmount(tester);
      expect(source.disposed, isTrue);
    },
  );

  testWidgets(
    'disposing verification page in flight does not notify or resurrect',
    (tester) async {
      final pending = Completer<http.Response>();
      await mount(
        tester,
        handler: (request) async {
          if (request.url.path.endsWith('/login')) return signedInResponse();
          if (request.url.path.endsWith('/me')) {
            return jsonResponse(pendingUser);
          }
          return pending.future;
        },
      );
      await signIn(tester);
      await tester.enterText(
        find.byKey(const Key('verification-token')),
        verificationToken,
      );
      await tap(tester, find.byKey(const Key('confirm-email')));
      await unmount(tester);
      pending.complete(jsonResponse(verifiedUser));
      await tester.pumpAndSettle();
      expect(session.user, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(1440, 900)]) {
    testWidgets(
      'verification responsive at $size with large text, demo stays unprotected',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        await mount(tester);
        await signIn(tester);
        expect(find.byType(VerifyEmailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tap(tester, find.text(demoLabel));
        expect(find.text('Unprotected sample'), findsOneWidget);
        expect(
          find.textContaining('No tenant access, membership'),
          findsOneWidget,
        );
        await tap(tester, find.byTooltip('Exit demo'));
        expect(find.byType(VerifyEmailPage), findsOneWidget);
        await unmount(tester);
      },
    );
  }
}
