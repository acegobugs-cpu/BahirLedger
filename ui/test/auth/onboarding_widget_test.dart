import 'dart:async';

import 'package:bahir_ledger/src/app.dart';
import 'package:bahir_ledger/src/pages/account_page.dart';
import 'package:bahir_ledger/src/pages/verify_email_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'onboarding_test.dart' as fixture;

void main() {
  Future<fixture.OnboardingHarness> mount(
    WidgetTester tester, {
    Object? context = fixture.emptyContext,
    bool verified = true,
    Future<http.Response> Function(http.Request)? handler,
  }) async {
    final h = fixture.OnboardingHarness(verified: verified)..context = context;
    h.handler = handler;
    await h.login();
    await tester.pumpWidget(
      BahirLedgerApp(
        session: h.session,
        demoBuilder: (_) => const Text('Unrelated sample project'),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'copy requires explicit action and explains clipboard retention',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final h = await mount(tester, context: fixture.membershipContext());
      h.handler = (r) async {
        if (r.url.path.endsWith('/onboarding')) return fixture.json(h.context);
        if (r.method == 'POST') {
          return fixture.json({
            'invitation': fixture.invitation(),
            'token': fixture.privateCode,
          }, 201);
        }
        return fixture.json({
          'invitations': [fixture.invitation()],
        });
      };
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        'recipient@example.com',
      );
      await tap(tester, 'Create invitation code');
      expect(copied, isEmpty);
      expect(
        find.textContaining('Clear your clipboard after sharing.'),
        findsOneWidget,
      );
      await tap(tester, 'Copy code');
      expect(copied, [fixture.privateCode]);
      await tap(tester, 'Sign out');
      expect(h.session.shareCode, isNull);
      expect(find.byKey(const Key('share-code')), findsNothing);
      await close(tester);
    },
  );

  testWidgets('owner list is bounded and only pending rows have revoke actions', (
    tester,
  ) async {
    final list = List.generate(
      101,
      (index) => {
        ...fixture.invitation(index == 0 ? 'ACCEPTED' : 'PENDING'),
        'id':
            '${index.toRadixString(16).padLeft(8, '0')}-1234-1234-1234-123456789abc',
        'email': 'recipient$index@example.com',
      },
    );
    await mount(
      tester,
      context: fixture.membershipContext(),
      handler: (r) async {
        if (r.url.path.endsWith('/onboarding')) {
          return fixture.json(fixture.membershipContext());
        }
        return fixture.json({'invitations': list});
      },
    );
    expect(find.text('recipient99@example.com'), findsOneWidget);
    expect(find.text('recipient100@example.com'), findsNothing);
    expect(find.text('Revoke recipient0@example.com'), findsNothing);
    expect(find.text('Revoke recipient1@example.com'), findsOneWidget);
    expect(
      find.textContaining('Showing the first 100 invitations.'),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('pending name update is separate from activation', (
    tester,
  ) async {
    final h = await mount(tester, context: fixture.pendingContext);
    h.handler = (_) async => fixture.json({
      'membership': null,
      'bootstrap': {
        ...fixture.pendingContext['bootstrap'] as Map,
        'name': 'Updated Works',
      },
    });
    await tester.enterText(
      find.byKey(const Key('pending-organization-name')),
      'Updated Works',
    );
    await tap(tester, 'Update pending name');
    expect(find.text('Pending setup: Updated Works'), findsOneWidget);
    expect(h.requests.last.url.path, endsWith('/bootstrap'));
    expect(find.text('Confirm activation'), findsNothing);
    await close(tester);
  });

  testWidgets(
    '429 is retryable and verification refresh clears private input',
    (tester) async {
      final h = await mount(tester);
      await tester.enterText(
        find.byKey(const Key('invitation-code')),
        fixture.privateCode,
      );
      final controller = tester
          .widget<TextField>(find.byKey(const Key('invitation-code')))
          .controller!;
      await tap(tester, 'Check verification status');
      expect(controller.text, isEmpty);
      h.handler = (_) async =>
          http.Response('rate_limited private detail', 429);
      await tap(tester, 'Refresh organization status');
      expect(
        find.text(
          'Too many organization requests. Please wait, then refresh status.',
        ),
        findsOneWidget,
      );
      expect(find.text('rate_limited private detail'), findsNothing);
      h.handler = null;
      await tap(tester, 'Refresh organization status');
      expect(find.byKey(const Key('invitation-code')), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('unverified stays gated and never loads organization', (
    tester,
  ) async {
    final h = await mount(tester, verified: false);
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    expect(find.byType(AccountPage), findsNothing);
    expect(h.requests.length, 2);
    await close(tester);
  });

  testWidgets(
    'lifecycle fetches once; save does not activate until confirmation',
    (tester) async {
      final h = await mount(tester);
      expect(h.requests.length, 3);
      await tester.pump();
      await tester.pump();
      expect(h.requests.length, 3);
      h.handler = (_) async => fixture.json(fixture.pendingContext);
      await tester.enterText(
        find.byKey(const Key('organization-name')),
        ' Works ',
      );
      await tap(tester, 'Save pending setup');
      expect(find.text('Pending setup: ሰላም Works'), findsOneWidget);
      expect(find.text('Organization invitations'), findsNothing);
      expect(h.requests.last.url.path, endsWith('/bootstrap'));
      final count = h.requests.length;
      await tap(tester, 'Activate organization');
      expect(h.requests.length, count);
      expect(find.text('Confirm activation'), findsOneWidget);
      await tap(tester, 'Not now');
      expect(h.requests.length, count);
      await tap(tester, 'Activate organization');
      h.handler = (r) async => r.url.path.endsWith('/invitations')
          ? fixture.json({'invitations': []})
          : fixture.json(fixture.membershipContext());
      await tap(tester, 'Confirm activation');
      expect(find.text('Role: OWNER'), findsOneWidget);
      expect(
        find.text('Membership only; project access not configured.'),
        findsOneWidget,
      );
      expect(find.text('Unrelated sample project'), findsNothing);
      await close(tester);
    },
  );

  testWidgets('pending context resumes and cancel refreshes context', (
    tester,
  ) async {
    final h = await mount(tester, context: fixture.pendingContext);
    expect(find.text('Pending setup: ሰላም Works'), findsOneWidget);
    h.handler = (r) async => r.url.path.endsWith('/cancel')
        ? http.Response('', 204)
        : fixture.json(fixture.emptyContext);
    await tap(tester, 'Cancel pending setup');
    expect(find.byKey(const Key('organization-name')), findsOneWidget);
    expect(h.requests.last.url.path, endsWith('/onboarding'));
    await close(tester);
  });

  testWidgets(
    'private input is cleared at preview, explicit accept, no owner UI for member',
    (tester) async {
      final h = await mount(tester);
      h.handler = (_) async => fixture.json(fixture.preview);
      final field = find.byKey(const Key('invitation-code'));
      await tester.enterText(field, fixture.privateCode);
      final input = tester.widget<TextField>(field).controller!;
      expect(h.requests.length, 3);
      await tap(tester, 'Preview invitation');
      expect(input.text, isEmpty);
      expect(find.text('Invitation to ሰላም Works'), findsOneWidget);
      expect(h.requests.last.url.path, endsWith('/preview'));
      h.handler = (_) async =>
          fixture.json(fixture.membershipContext('MEMBER'));
      await tap(tester, 'Accept invitation');
      expect(find.text('Role: MEMBER'), findsOneWidget);
      expect(find.byKey(const Key('invite-email')), findsNothing);
      expect(find.text('Organization invitations'), findsNothing);
      expect(find.text('Unrelated sample project'), findsNothing);
      await tap(tester, demoLabel);
      expect(find.text('Unrelated sample project'), findsOneWidget);
      expect(
        find.text(
          'Local sample data only. No tenant access, membership, or authorization is granted.',
        ),
        findsOneWidget,
      );
      await close(tester);
    },
  );

  testWidgets(
    'wrong recipient shows generic error with refresh and logout, not acceptance',
    (tester) async {
      final h = await mount(tester);
      h.handler = (_) async => http.Response('private wrong identity', 400);
      await tester.enterText(
        find.byKey(const Key('invitation-code')),
        fixture.privateCode,
      );
      await tap(tester, 'Preview invitation');
      expect(find.text('Accept invitation'), findsNothing);
      expect(find.text('private wrong identity'), findsNothing);
      expect(find.text('Refresh organization status'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      h.handler = null;
      await tap(tester, 'Refresh organization status');
      expect(find.byKey(const Key('invitation-code')), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'owner code masked by default, reveal/dismiss; later action clears it',
    (tester) async {
      final h = await mount(tester, context: fixture.membershipContext());
      h.handler = (r) async {
        if (r.url.path.endsWith('/onboarding')) return fixture.json(h.context);
        if (r.method == 'POST') {
          return fixture.json({
            'invitation': fixture.invitation(),
            'token': fixture.privateCode,
          }, 201);
        }
        return fixture.json({
          'invitations': [fixture.invitation()],
        });
      };
      await tester.enterText(
        find.byKey(const Key('invite-email')),
        'recipient@example.com',
      );
      await tap(tester, 'Create invitation code');
      expect(h.session.shareCode, fixture.privateCode);
      expect(find.text(fixture.privateCode), findsNothing);
      expect(
        find.textContaining('No invitation email is sent.'),
        findsOneWidget,
      );
      await tap(tester, 'Reveal code');
      expect(find.text(fixture.privateCode), findsOneWidget);
      await tap(tester, 'Dismiss code');
      expect(h.session.shareCode, isNull);
      expect(find.byKey(const Key('share-code')), findsNothing);
      await tap(tester, 'Create invitation code');
      expect(h.session.shareCode, fixture.privateCode);
      await tap(tester, 'Refresh organization status');
      expect(h.session.shareCode, isNull);
      expect(find.byKey(const Key('share-code')), findsNothing);
      await close(tester);
    },
  );

  testWidgets('denial removes owner form and failure has refresh recovery', (
    tester,
  ) async {
    final h = await mount(tester, context: fixture.membershipContext());
    h.handler = (_) async =>
        http.Response('organization_unavailable secret', 403);
    await tap(tester, 'Refresh organization status');
    expect(find.byKey(const Key('invite-email')), findsNothing);
    expect(find.text('Role: OWNER'), findsNothing);
    h.handler = null;
    h.context = fixture.membershipContext('MEMBER');
    await tap(tester, 'Refresh organization status');
    expect(find.text('Role: MEMBER'), findsOneWidget);
    expect(find.text('Organization invitations'), findsNothing);
    await close(tester);
  });

  testWidgets(
    'loading serializes actions; cancel and disposal ignore late private data',
    (tester) async {
      final h = await mount(tester);
      final pending = Completer<http.Response>();
      h.handler = (_) => pending.future;
      await tester.enterText(
        find.byKey(const Key('invitation-code')),
        fixture.privateCode,
      );
      final button = find.text('Preview invitation');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(h.session.onboardingBusy, isTrue);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(
                OutlinedButton,
                'Refresh organization status',
              ),
            )
            .onPressed,
        isNull,
      );
      // No pumpAndSettle while the progress indicator is active.
      await tester.ensureVisible(find.text('Cancel invitation entry'));
      await tester.tap(find.text('Cancel invitation entry'));
      await tester.pump();
      expect(h.session.onboardingBusy, isFalse);
      await close(tester);
      pending.complete(fixture.json(fixture.preview));
      await tester.pump();
      expect(h.session.invitationPreview, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final role in ['NONE', 'OWNER', 'MEMBER']) {
    testWidgets('tiny width and large text scroll without overflow: $role', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(240, 480);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await mount(
        tester,
        context: role == 'NONE'
            ? fixture.emptyContext
            : fixture.membershipContext(role),
      );
      expect(tester.takeException(), isNull);
      await tap(tester, 'Sign out');
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }
}
