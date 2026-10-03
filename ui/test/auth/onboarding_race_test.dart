import 'dart:async';

import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'onboarding_test.dart' as f;

void main() {
  Future<void> issue(f.OnboardingHarness h) async {
    h.handler = (r) async {
      if (r.url.path.endsWith('/onboarding')) return f.json(h.context);
      if (r.method == 'POST') {
        return f.json({
          'invitation': f.invitation(),
          'token': f.privateCode,
        }, 201);
      }
      return f.json({
        'invitations': [f.invitation()],
      });
    };
    await h.session.invite('recipient@example.com');
  }

  for (final end in ['logout', 'dispose', 'relogin', 'expiry', 'dismiss']) {
    for (final stage in ['issue', 'context', 'list']) {
      test(
        'late owner code at $stage after $end never restores tenant or code',
        () async {
          final h = f.OnboardingHarness()..context = f.membershipContext();
          await h.start();
          final pending = Completer<http.Response>();
          final arrived = Completer<void>();
          h.handler = (r) async {
            final current = r.method == 'POST'
                ? 'issue'
                : r.url.path.endsWith('/onboarding')
                ? 'context'
                : 'list';
            if (current == stage) {
              arrived.complete();
              return pending.future;
            }
            if (current == 'issue') {
              return f.json({
                'invitation': f.invitation(),
                'token': f.privateCode,
              }, 201);
            }
            if (current == 'context') return f.json(h.context);
            return f.json({
              'invitations': [f.invitation()],
            });
          };
          final work = h.session.invite('recipient@example.com');
          await arrived.future;
          expect(h.session.shareCode, isNull);
          switch (end) {
            case 'logout':
              await h.session.logout();
            case 'dispose':
              h.dispose();
            case 'relogin':
              await h.session.logout();
              await h.login();
            case 'expiry':
              h.now = h.now.add(const Duration(minutes: 30));
              h.session.checkExpiry();
            case 'dismiss':
              h.session.dismissInvitation();
          }
          final count = h.requests.length;
          pending.complete(
            stage == 'issue'
                ? f.json({
                    'invitation': f.invitation(),
                    'token': f.privateCode,
                  }, 201)
                : stage == 'context'
                ? f.json(h.context)
                : f.json({
                    'invitations': [f.invitation()],
                  }),
          );
          await work;
          expect(h.requests.length, count);
          expect(h.session.shareCode, isNull);
          expect(h.session.onboarding, isNull);
          expect(h.session.invitations, isEmpty);
          if (end == 'relogin') expect(h.session.state, SessionState.signedIn);
          if (end != 'dispose') h.dispose();
        },
      );
    }
  }

  for (final action in ['save', 'activate', 'cancel', 'accept', 'revoke']) {
    test(
      '$action late response after logout makes no follow-up or mutation',
      () async {
        final h = f.OnboardingHarness()
          ..context = action == 'revoke'
              ? f.membershipContext()
              : action == 'activate' || action == 'cancel'
              ? f.pendingContext
              : f.emptyContext
          ..list = [f.invitation()];
        addTearDown(h.dispose);
        await h.start();
        if (action == 'accept') {
          h.handler = (_) async => f.json(f.preview);
          await h.session.previewInvitation(f.privateCode);
        }
        final pending = Completer<http.Response>();
        final arrived = Completer<void>();
        h.handler = (_) {
          arrived.complete();
          return pending.future;
        };
        final work = switch (action) {
          'save' => h.session.saveOrganization('Works'),
          'activate' => h.session.activateOrganization(),
          'cancel' => h.session.cancelOrganization(),
          'accept' => h.session.acceptInvitation(),
          _ => h.session.revokeInvitation(f.invitationId),
        };
        await arrived.future;
        await h.session.logout();
        final count = h.requests.length;
        pending.complete(
          action == 'cancel' || action == 'revoke'
              ? http.Response('', 204)
              : f.json(f.membershipContext()),
        );
        await work;
        expect(h.requests.length, count);
        expect(h.session.onboarding, isNull);
        expect(h.session.shareCode, isNull);
        expect(h.session.invitationPreview, isNull);
      },
    );
  }

  for (final action in ['save', 'activate', 'accept']) {
    test(
      '$action lost response may commit; explicit refresh recovers server state',
      () async {
        final h = f.OnboardingHarness()
          ..context = action == 'activate' ? f.pendingContext : f.emptyContext;
        addTearDown(h.dispose);
        await h.start();
        if (action == 'accept') {
          h.handler = (_) async => f.json(f.preview);
          await h.session.previewInvitation(f.privateCode);
        }
        h.handler = (_) async {
          h.context = action == 'save'
              ? f.pendingContext
              : f.membershipContext('MEMBER');
          throw http.ClientException('lost response');
        };
        await switch (action) {
          'save' => h.session.saveOrganization('Works'),
          'activate' => h.session.activateOrganization(),
          _ => h.session.acceptInvitation(),
        };
        expect(h.session.onboarding, isNull);
        expect(h.session.invitationPreview, isNull);
        h.handler = null;
        await h.session.refreshOnboarding();
        if (action == 'save') {
          expect(h.session.onboarding!.bootstrap, isNotNull);
        } else {
          expect(h.session.onboarding!.membership, isNotNull);
        }
      },
    );
  }

  for (final change in [
    'member',
    'other organization',
    'revoked',
    'missing',
    'denied',
    'malformed',
  ]) {
    test('owner code withheld when refreshed capability is $change', () async {
      final h = f.OnboardingHarness()..context = f.membershipContext();
      addTearDown(h.dispose);
      await h.start();
      h.handler = (r) async {
        if (r.method == 'POST') {
          return f.json({
            'invitation': f.invitation(),
            'token': f.privateCode,
          }, 201);
        }
        if (r.url.path.endsWith('/onboarding')) {
          if (change == 'member') return f.json(f.membershipContext('MEMBER'));
          if (change == 'other organization') {
            return f.json({
              'membership': {
                'organizationId': f.bootstrapId,
                'organizationName': 'Another',
                'role': 'OWNER',
              },
              'bootstrap': null,
            });
          }
          return f.json(h.context);
        }
        if (change == 'denied') return http.Response('forbidden private', 403);
        if (change == 'malformed') {
          return f.json({
            'invitations': [{}],
          });
        }
        return f.json({
          'invitations': change == 'missing'
              ? []
              : [f.invitation(change == 'revoked' ? 'REVOKED' : 'PENDING')],
        });
      };
      await h.session.invite('recipient@example.com');
      expect(h.session.shareCode, isNull);
      expect(h.session.isOrganizationOwner, isFalse);
      expect(h.session.onboardingMessage, isNotNull);
      expect(h.session.state, SessionState.signedIn);
    });
  }

  for (final action in [
    'dismiss',
    'refresh',
    'verification',
    'logout',
    'dispose',
    'expiry',
  ]) {
    test('published owner code clears on $action', () async {
      final h = f.OnboardingHarness()..context = f.membershipContext();
      await h.start();
      await issue(h);
      expect(h.session.shareCode, f.privateCode);
      switch (action) {
        case 'dismiss':
          h.session.dismissInvitation();
        case 'refresh':
          await h.session.refreshOnboarding();
        case 'verification':
          await h.session.refreshUser();
        case 'logout':
          await h.session.logout();
        case 'dispose':
          h.dispose();
        case 'expiry':
          h.now = h.now.add(const Duration(minutes: 30));
          h.session.checkExpiry();
      }
      expect(h.session.shareCode, isNull);
      if (action != 'dispose') h.dispose();
    });
  }

  test('issued code timer clears code independently of session timer', () {
    fakeAsync((async) {
      final h = f.OnboardingHarness()..context = f.membershipContext();
      h.start();
      async.flushMicrotasks();
      final invitation = {
        ...f.invitation(),
        'expiresAt': h.now.add(const Duration(seconds: 5)).toIso8601String(),
      };
      h.handler = (r) async {
        if (r.method == 'POST') {
          return f.json({
            'invitation': invitation,
            'token': f.privateCode,
          }, 201);
        }
        if (r.url.path.endsWith('/onboarding')) return f.json(h.context);
        return f.json({
          'invitations': [invitation],
        });
      };
      h.session.invite('recipient@example.com');
      async.flushMicrotasks();
      expect(h.session.shareCode, f.privateCode);
      async.elapse(const Duration(seconds: 5));
      expect(h.session.shareCode, isNull);
      expect(h.session.state, SessionState.signedIn);
      h.dispose();
    });
  });

  test('invalid local name/email/token make no API request', () async {
    final h = f.OnboardingHarness();
    addTearDown(h.dispose);
    await h.login();
    for (final name in ['', ' ', 'x' * 121]) {
      expect(
        () => h.transport.saveBootstrap(name),
        throwsA(isA<AuthFailure>()),
      );
    }
    for (final email in ['', 'bad', 'a b@c', 'x' * 255]) {
      expect(
        () => h.transport.createInvitation(email),
        throwsA(isA<AuthFailure>()),
      );
    }
    for (final code in ['', 'x' * 42, 'x' * 44, '${'x' * 42}+']) {
      expect(
        () => h.transport.previewInvitation(code),
        throwsA(isA<AuthFailure>()),
      );
      expect(
        () => h.transport.acceptInvitation(code),
        throwsA(isA<AuthFailure>()),
      );
    }
    expect(h.requests.length, 2);
  });
}
