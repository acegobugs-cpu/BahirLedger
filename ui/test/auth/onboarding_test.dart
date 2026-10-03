import 'dart:async';
import 'dart:convert';

import 'package:bahir_ledger/src/auth/api_config.dart';
import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/onboarding.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const organizationId = '12345678-1234-1234-1234-123456789abc';
const bootstrapId = '22345678-1234-1234-1234-123456789abc';
const invitationId = '32345678-1234-1234-1234-123456789abc';
const privateCode = 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE';
const emptyContext = {'membership': null, 'bootstrap': null};
const account = {
  'id': 'account-1',
  'email': 'person@example.com',
  'displayName': 'Verified Person',
  'emailVerified': true,
};
final epoch = DateTime.utc(2026, 10, 3);
final pendingContext = {
  'membership': null,
  'bootstrap': {
    'id': bootstrapId,
    'name': 'ሰላም Works',
    'expiresAt': '2026-10-04T00:00:00Z',
  },
};
Map<String, Object?> membershipContext([String role = 'OWNER']) => {
  'membership': {
    'organizationId': organizationId,
    'organizationName': 'ሰላም Works',
    'role': role,
  },
  'bootstrap': null,
};
Map<String, Object?> invitation([String status = 'PENDING']) => {
  'id': invitationId,
  'email': 'recipient@example.com',
  'status': status,
  'expiresAt': '2026-10-10T00:00:00Z',
};
const preview = {
  'organizationName': 'ሰላም Works',
  'expiresAt': '2026-10-10T00:00:00Z',
};
http.Response json(Object? value, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), status);

class OnboardingHarness {
  OnboardingHarness({bool verified = true}) {
    user = {...account, 'emailVerified': verified};
    transport = AuthTransport(
      config: ApiConfig('https://api.example.com'),
      clock: () => now,
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/login')) {
          return json({
            'accessToken': 'memory-only-bearer',
            'expiresAt': now.add(const Duration(minutes: 30)).toIso8601String(),
            'user': user,
          });
        }
        if (path.endsWith('/logout')) return http.Response('', 204);
        if (path.endsWith('/me')) return meHandler?.call(request) ?? json(user);
        if (handler != null) return handler!(request);
        if (path.endsWith('/onboarding')) return json(context);
        if (path.endsWith('/organization/invitations') &&
            request.method == 'GET') {
          return json({'invitations': list});
        }
        throw StateError('Unexpected test route');
      }),
    );
    session = SessionController(transport: transport, clock: () => now);
  }
  DateTime now = epoch;
  late Map<String, Object> user;
  Object? context = emptyContext;
  List<Object?> list = [];
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? handler;
  Future<http.Response> Function(http.Request)? meHandler;
  late final AuthTransport transport;
  late final SessionController session;
  Future<void> login() => session.login('person@example.com', 'password');
  Future<void> start() async {
    await login();
    await session.refreshOnboarding();
  }

  void dispose() => session.dispose();
}

void main() {
  group('strict organization parser', () {
    for (final value in [
      null,
      [],
      {},
      {'membership': null},
      {'bootstrap': null},
      {
        'membership': membershipContext()['membership'],
        'bootstrap': pendingContext['bootstrap'],
      },
    ]) {
      test('rejects incomplete/ambiguous context ${jsonEncode(value)}', () {
        expect(() => OnboardingContext.fromJson(value), throwsFormatException);
      });
    }
    for (final role in [null, 'owner', 'ADMIN', true, 1]) {
      test('rejects role $role without capabilities', () {
        final data = membershipContext();
        data['membership'] = {...data['membership'] as Map, 'role': role};
        expect(() => OnboardingContext.fromJson(data), throwsFormatException);
      });
    }
    for (final id in [null, '', 'org-1', '$organizationId/', 123]) {
      test('rejects malformed UUID $id', () {
        expect(
          () => OrganizationMembership.fromJson({
            'organizationId': id,
            'organizationName': 'Works',
            'role': 'OWNER',
          }),
          throwsFormatException,
        );
      });
    }
    for (final name in [
      null,
      '',
      ' ',
      ' padded',
      'x' * 121,
      'line\nbreak',
      3,
    ]) {
      test('rejects malformed name ${name.runtimeType} ${name.hashCode}', () {
        expect(
          () => InvitationPreview.fromJson({
            ...preview,
            'organizationName': name,
          }),
          throwsFormatException,
        );
      });
    }
    for (final date in [
      null,
      '',
      '2026-10-03',
      '2026-10-03T00:00:00',
      '2026-02-30T00:00:00Z',
      '2026-13-01T00:00:00Z',
      '2026-10-03T24:00:00Z',
      '2026-10-03T00:00:00+03:00',
    ]) {
      test('rejects date $date', () {
        expect(
          () => InvitationPreview.fromJson({...preview, 'expiresAt': date}),
          throwsFormatException,
        );
      });
    }
    for (final status in [null, 'pending', 'OWNER', 1]) {
      test('rejects invitation status $status', () {
        expect(
          () => OrganizationInvitation.fromJson({
            ...invitation(),
            'status': status,
          }),
          throwsFormatException,
        );
      });
    }
    test('requires invitation list and rejects duplicate ids', () {
      for (final value in [
        {},
        {'invitations': null},
        {
          'invitations': [invitation(), invitation()],
        },
      ]) {
        expect(
          () => OrganizationInvitation.listFromJson(value),
          throwsFormatException,
        );
      }
    });
    test('valid data preserves Unicode and permits all statuses', () {
      expect(
        OnboardingContext.fromJson(pendingContext).bootstrap!.name,
        'ሰላም Works',
      );
      for (final status in ['PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED']) {
        expect(
          OrganizationInvitation.fromJson(
            invitation(status),
          ).status.name.toUpperCase(),
          status,
        );
      }
      expect(
        onboardingDate('2026-10-03T00:00:00.123456789+00:00').isUtc,
        isTrue,
      );
    });
    test('issued codes are strict and redacted in diagnostics', () {
      final value = IssuedInvitation.fromJson({
        'invitation': invitation(),
        'token': privateCode,
      });
      expect(value.toString(), isNot(contains(privateCode)));
      for (final token in [null, '', 'x' * 42, '${'x' * 42}+', 'x' * 44]) {
        expect(
          () => IssuedInvitation.fromJson({
            'invitation': invitation(),
            'token': token,
          }),
          throwsFormatException,
        );
      }
    });
  });

  test(
    'verified-only controller AND transport gate; no implicit onboarding on login',
    () async {
      final h = OnboardingHarness(verified: false);
      addTearDown(h.dispose);
      await h.login();
      await h.session.refreshOnboarding();
      await h.session.previewInvitation(privateCode);
      expect(h.requests.length, 2);
      await expectLater(
        h.transport.loadOnboarding(),
        throwsA(isA<AuthFailure>()),
      );
      expect(h.requests.length, 2);
      expect(h.session.onboarding, isNull);
    },
  );

  test(
    'all routes use exact bearer-only requests and normalized payloads',
    () async {
      final h = OnboardingHarness();
      addTearDown(h.dispose);
      await h.login();
      h.handler = (r) async {
        if (r.url.path.endsWith('/cancel') || r.url.path.endsWith('/revoke')) {
          return http.Response('', 204);
        }
        if (r.url.path.endsWith('/preview')) return json(preview);
        if (r.url.path.endsWith('/organization/invitations')) {
          return r.method == 'GET'
              ? json({'invitations': []})
              : json({'invitation': invitation(), 'token': privateCode}, 201);
        }
        return json(emptyContext);
      };
      await h.transport.loadOnboarding();
      await h.transport.saveBootstrap('  ሰላም Works  ');
      await h.transport.activateBootstrap(bootstrapId);
      await h.transport.cancelBootstrap(bootstrapId);
      await h.transport.loadInvitations();
      await h.transport.createInvitation(' Recipient@Example.COM ');
      await h.transport.revokeInvitation(invitationId);
      await h.transport.previewInvitation(privateCode);
      await h.transport.acceptInvitation(privateCode);
      final requests = h.requests.skip(2).toList();
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'GET /api/v1/onboarding',
        'POST /api/v1/onboarding/bootstrap',
        'POST /api/v1/onboarding/bootstrap/activate',
        'POST /api/v1/onboarding/bootstrap/cancel',
        'GET /api/v1/organization/invitations',
        'POST /api/v1/organization/invitations',
        'POST /api/v1/organization/invitations/$invitationId/revoke',
        'POST /api/v1/onboarding/invitations/preview',
        'POST /api/v1/onboarding/invitations/accept',
      ]);
      expect(jsonDecode(requests[1].body), {'name': 'ሰላም Works'});
      expect(jsonDecode(requests[2].body), {'bootstrapId': bootstrapId});
      expect(jsonDecode(requests[3].body), {'bootstrapId': bootstrapId});
      expect(jsonDecode(requests[5].body), {'email': 'recipient@example.com'});
      expect(jsonDecode(requests[7].body), {'token': privateCode});
      expect(jsonDecode(requests[8].body), {'token': privateCode});
      for (final r in requests) {
        expect(r.headers['authorization'], 'Bearer memory-only-bearer');
        expect(r.headers['accept'], 'application/json');
        expect(r.headers.containsKey('cookie'), isFalse);
        expect(r.followRedirects, isFalse);
        expect(r.url.hasQuery, isFalse);
        if (r.body.isNotEmpty) {
          expect(r.headers['content-type'], contains('application/json'));
        }
      }
    },
  );

  test(
    'save resume activate and cancel refresh use durable server context',
    () async {
      final h = OnboardingHarness();
      addTearDown(h.dispose);
      await h.start();
      h.handler = (_) async => json(pendingContext);
      await h.session.saveOrganization(' Works ');
      expect(h.session.onboarding!.bootstrap!.id, bootstrapId);
      expect(h.session.isOrganizationOwner, isFalse);
      await h.session.refreshOnboarding();
      expect(h.session.onboarding!.bootstrap, isNotNull);
      h.handler = (r) async => r.url.path.endsWith('/invitations')
          ? json({'invitations': []})
          : json(membershipContext());
      await h.session.activateOrganization();
      expect(h.session.isOrganizationOwner, isTrue);
      expect(h.session.onboarding!.bootstrap, isNull);
      h.handler = (_) async => json(pendingContext);
      await h.session.refreshOnboarding();
      h.handler = (r) async => r.url.path.endsWith('/cancel')
          ? http.Response('', 204)
          : json(emptyContext);
      await h.session.cancelOrganization();
      expect(h.requests[h.requests.length - 2].url.path, endsWith('/cancel'));
      expect(h.requests.last.url.path, endsWith('/onboarding'));
      expect(h.session.onboarding!.bootstrap, isNull);
    },
  );

  test(
    'preview never accepts automatically; accept clears private state',
    () async {
      final h = OnboardingHarness();
      addTearDown(h.dispose);
      await h.start();
      h.handler = (_) async => json(preview);
      await h.session.previewInvitation(privateCode);
      expect(h.session.invitationPreview!.organizationName, 'ሰላም Works');
      expect(h.requests.where((r) => r.url.path.endsWith('/accept')), isEmpty);
      h.handler = (_) async => json(membershipContext('MEMBER'));
      await h.session.acceptInvitation();
      expect(h.session.onboarding!.membership!.role, OrganizationRole.member);
      expect(h.session.invitationPreview, isNull);
      expect(h.session.shareCode, isNull);
      expect(h.session.isOrganizationOwner, isFalse);
      final count = h.requests.length;
      await h.session.invite('recipient@example.com');
      await h.session.previewInvitation(privateCode);
      await h.session.acceptInvitation();
      expect(h.requests.length, count);
    },
  );

  for (final status in [400, 401, 403, 404, 409, 429, 500, 302]) {
    test(
      'denial $status clears owner capabilities and secrets; safe recovery',
      () async {
        final h = OnboardingHarness()..context = membershipContext();
        addTearDown(h.dispose);
        await h.start();
        expect(h.session.isOrganizationOwner, isTrue);
        h.handler = (_) async =>
            http.Response('private body $privateCode', status);
        await h.session.refreshOnboarding();
        expect(h.session.isOrganizationOwner, isFalse);
        expect(h.session.onboarding, isNull);
        expect(h.session.invitations, isEmpty);
        expect(h.session.shareCode, isNull);
        expect(h.session.onboardingBusy, isFalse);
        expect(
          '${h.session.onboardingMessage} ${h.session.message}',
          isNot(contains(privateCode)),
        );
        expect(
          h.session.state,
          status == 401 ? SessionState.signedOut : SessionState.signedIn,
        );
        if (status != 401) {
          h.handler = null;
          h.context = membershipContext('MEMBER');
          await h.session.refreshOnboarding();
          expect(
            h.session.onboarding!.membership!.role,
            OrganizationRole.member,
          );
        }
      },
    );
  }

  test(
    'wrong identity/expired/replayed invitation failure is generic, no preview',
    () async {
      final h = OnboardingHarness();
      addTearDown(h.dispose);
      await h.start();
      h.handler = (_) async => json({
        'code': 'invalid_invitation',
        'email': 'other@example.com',
      }, 400);
      await h.session.previewInvitation(privateCode);
      expect(h.session.invitationPreview, isNull);
      expect(h.session.onboardingMessage, AuthTransport.invitationUnavailable);
      expect(h.session.onboardingMessage, isNot(contains('other@example.com')));
      await h.session.acceptInvitation();
      expect(h.requests.last.url.path, endsWith('/preview'));
    },
  );

  test(
    'network failure and malformed response discard stale owner; refresh recovers',
    () async {
      final h = OnboardingHarness()..context = membershipContext();
      addTearDown(h.dispose);
      await h.start();
      h.handler = (_) async => throw http.ClientException(privateCode);
      await h.session.invite('recipient@example.com');
      expect(h.session.onboarding, isNull);
      expect(h.session.onboardingMessage, isNot(contains(privateCode)));
      h.handler = null;
      await h.session.refreshOnboarding();
      expect(h.session.isOrganizationOwner, isTrue);
      h.context = {
        'membership': {'role': 'OWNER'},
        'bootstrap': null,
      };
      await h.session.refreshOnboarding();
      expect(h.session.isOrganizationOwner, isFalse);
    },
  );

  test('owner issue reload revoke and downgrade clear code and list', () async {
    final h = OnboardingHarness()..context = membershipContext();
    addTearDown(h.dispose);
    await h.start();
    h.handler = (r) async {
      if (r.url.path.endsWith('/onboarding')) return json(h.context);
      if (r.method == 'POST') {
        return json({'invitation': invitation(), 'token': privateCode}, 201);
      }
      return json({
        'invitations': [invitation()],
      });
    };
    await h.session.invite('recipient@example.com');
    expect(h.session.shareCode, privateCode);
    expect(h.session.invitations.length, 1);
    h.handler = (r) async {
      if (r.url.path.endsWith('/revoke')) return http.Response('', 204);
      if (r.url.path.endsWith('/onboarding')) return json(h.context);
      return json({
        'invitations': [invitation('REVOKED')],
      });
    };
    final revoke = h.session.revokeInvitation(invitationId);
    expect(h.session.shareCode, isNull);
    await revoke;
    expect(h.session.invitations.single.status, InvitationStatus.revoked);
    h.context = membershipContext('MEMBER');
    await h.session.refreshOnboarding();
    expect(h.session.isOrganizationOwner, isFalse);
    expect(h.session.invitations, isEmpty);
  });

  for (final end in [
    'logout',
    'expiry',
    'dispose',
    'relogin',
    'dismiss',
    'leave',
  ]) {
    for (final responseKind in ['valid', 'malformed', '401']) {
      test(
        'late preview $responseKind after $end cannot restore state or affect newer session',
        () async {
          final h = OnboardingHarness();
          await h.start();
          final pending = Completer<http.Response>();
          h.handler = (_) => pending.future;
          final work = h.session.previewInvitation(privateCode);
          await Future<void>.delayed(Duration.zero);
          switch (end) {
            case 'logout':
              await h.session.logout();
            case 'relogin':
              await h.session.logout();
              await h.login();
            case 'expiry':
              h.now = h.now.add(const Duration(minutes: 30));
              h.session.checkExpiry();
            case 'dispose':
              h.dispose();
            case 'dismiss':
              h.session.dismissInvitation();
            case 'leave':
              h.session.leaveOnboarding();
          }
          pending.complete(
            responseKind == 'valid'
                ? json(preview)
                : http.Response('{private', responseKind == '401' ? 401 : 200),
          );
          await work;
          expect(h.session.invitationPreview, isNull);
          expect(h.session.shareCode, isNull);
          expect(h.session.onboarding, isNull);
          if (end == 'relogin') expect(h.session.state, SessionState.signedIn);
          if (end != 'dispose') h.dispose();
        },
      );
    }
  }

  test('shared verification serialization works in both directions', () async {
    final h = OnboardingHarness();
    addTearDown(h.dispose);
    await h.start();
    final pending = Completer<http.Response>();
    h.handler = (_) => pending.future;
    final refresh = h.session.refreshOnboarding();
    final count = h.requests.length;
    await h.session.refreshUser();
    await h.session.refreshOnboarding();
    expect(h.requests.length, count);
    pending.complete(json(emptyContext));
    await refresh;
    final me = Completer<http.Response>();
    h.meHandler = (_) => me.future;
    final verify = h.session.refreshUser();
    await Future<void>.delayed(Duration.zero);
    await h.session.refreshOnboarding();
    expect(h.requests.last.url.path, endsWith('/me'));
    me.complete(json({...account, 'emailVerified': false}));
    await verify;
    expect(h.session.user!.emailVerified, isFalse);
    expect(h.session.onboarding, isNull);
    await h.session.refreshOnboarding();
    expect(h.requests.last.url.path, endsWith('/me'));
  });

  test(
    'preview expiry and session absolute deadline never extend on actions',
    () {
      fakeAsync((async) {
        final h = OnboardingHarness();
        h.start();
        async.flushMicrotasks();
        h.handler = (_) async => json({
          ...preview,
          'expiresAt': epoch.add(const Duration(seconds: 10)).toIso8601String(),
        });
        h.session.previewInvitation(privateCode);
        async.flushMicrotasks();
        expect(h.session.invitationPreview, isNotNull);
        async.elapse(const Duration(seconds: 10));
        expect(h.session.invitationPreview, isNull);
        h.handler = (_) async => json(emptyContext);
        h.session.refreshOnboarding();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 30));
        expect(h.session.state, SessionState.signedOut);
        expect(h.session.onboarding, isNull);
        h.dispose();
      });
    },
  );
}
