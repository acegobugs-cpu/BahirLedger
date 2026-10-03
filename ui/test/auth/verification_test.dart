import 'dart:async';
import 'dart:convert';

import 'package:bahir_ledger/src/auth/api_config.dart';
import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:bahir_ledger/src/auth/verification_link_source.dart';
import 'package:bahir_ledger/src/auth/verification_links.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const verificationToken = 'abcdefghijklmnopqrstuvwxyz0123456789_-ABCDE';
const pendingUser = {
  'id': 'user-1',
  'email': 'person@example.com',
  'displayName': 'ሰላም · Zoë',
  'emailVerified': false,
};
const verifiedUser = {
  'id': 'user-1',
  'email': 'person@example.com',
  'displayName': 'ሰላም · Zoë',
  'emailVerified': true,
};
final epoch = DateTime.utc(2026, 10, 3);

http.Response jsonResponse(Object? value, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), status);

http.Response signedInResponse({Object? user = pendingUser}) => jsonResponse({
  'accessToken': 'account-bearer',
  'expiresAt': epoch.add(const Duration(minutes: 30)).toIso8601String(),
  'user': user,
});

/// Deterministic browser seam: replace removes the old entry, no push/history.
class FakeLinkSource implements VerificationLinkSource {
  FakeLinkSource([this.url]);
  String? url;
  int scrubs = 0;
  bool disposed = false;
  void Function()? changed;
  @override
  Uri get trustedOrigin => Uri.parse('https://app.example.com');
  @override
  String? get currentUrl => url;
  @override
  void scrub() {
    scrubs++;
    url = 'https://app.example.com/#/';
  }

  @override
  void listen(void Function() onChange) => changed = onChange;
  void navigate(String value) {
    url = value;
    changed?.call();
  }

  @override
  void dispose() {
    disposed = true;
    changed = null;
  }
}

void main() {
  late SessionController session;
  late List<http.Request> requests;
  late DateTime now;

  void setup(
    Future<http.Response> Function(http.Request)? operation, {
    Object? handshake = pendingUser,
    Object? me = pendingUser,
  }) {
    now = epoch;
    requests = [];
    var initialMe = true;
    session = SessionController(
      clock: () => now,
      transport: AuthTransport(
        config: ApiConfig('https://api.example.com'),
        clock: () => now,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/login') ||
              request.url.path.endsWith('/register')) {
            return signedInResponse(user: handshake);
          }
          if (request.url.path.endsWith('/me') && initialMe) {
            initialMe = false;
            return jsonResponse(me);
          }
          if (request.url.path.endsWith('/logout')) {
            return http.Response('', 204);
          }
          return operation == null
              ? jsonResponse(pendingUser)
              : operation(request);
        }),
      ),
    );
  }

  Future<void> login() => session.login('person@example.com', 'password');

  group('required verification boolean', () {
    for (final value in [null, 'false', 'true', 0, 1, [], {}]) {
      test('rejects non-boolean ${value.runtimeType}', () {
        expect(
          () => AccountUser.fromJson({...pendingUser, 'emailVerified': value}),
          throwsFormatException,
        );
      });
    }
    test('rejects missing boolean', () {
      final missing = {...pendingUser}..remove('emailVerified');
      expect(() => AccountUser.fromJson(missing), throwsFormatException);
    });
    for (final signup in [true, false]) {
      for (final badMe in [true, false]) {
        test(
          'fails closed in ${signup ? 'signup' : 'login'} ${badMe ? 'me' : 'user'}',
          () async {
            final missing = {...pendingUser}..remove('emailVerified');
            setup(
              null,
              handshake: badMe ? pendingUser : missing,
              me: badMe ? missing : pendingUser,
            );
            addTearDown(session.dispose);
            if (signup) {
              await session.signUp('User', 'person@example.com', 'password');
            } else {
              await login();
            }
            expect(session.state, SessionState.signedOut);
            expect(session.message, AuthTransport.invalidResponse);
            final count = requests.length;
            await session.logout();
            expect(requests.length, count);
          },
        );
      }
    }
  });

  test(
    'signup 503 keeps no session and provides sign-in/resend recovery',
    () async {
      var calls = 0;
      final controller = SessionController(
        transport: AuthTransport(
          config: ApiConfig('https://api.example.com'),
          client: MockClient((_) async {
            calls++;
            return http.Response('secret mail diagnostics', 503);
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.signUp('User', 'person@example.com', 'password');
      expect(controller.state, SessionState.signedOut);
      expect(controller.message, AuthTransport.signupMailUnavailable);
      await controller.logout();
      expect(calls, 1);
    },
  );

  test(
    'confirm uses exact suffix route/body and same bearer, preserving Unicode',
    () async {
      setup((_) async => jsonResponse(verifiedUser));
      addTearDown(session.dispose);
      await login();
      expect(session.user!.emailVerified, isFalse);
      await session.confirmEmail(verificationToken);
      expect(session.user!.emailVerified, isTrue);
      expect(session.user!.displayName, pendingUser['displayName']);
      final request = requests.last;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.example.com/api/v1/auth/email-verification/confirm',
      );
      expect(jsonDecode(request.body), {'token': verificationToken});
      expect(request.headers['authorization'], 'Bearer account-bearer');
      expect(request.followRedirects, isFalse);
      expect(request.headers.containsKey('cookie'), isFalse);
      await session.logout();
      expect(requests.last.headers['authorization'], 'Bearer account-bearer');
    },
  );

  test(
    'invalid manual token never makes a request or mentions passwords',
    () async {
      setup(null);
      addTearDown(session.dispose);
      await login();
      await session.confirmEmail('not a token');
      expect(requests.length, 2);
      expect(session.message, AuthTransport.invalidVerification);
      expect(session.message, isNot(contains('password')));
    },
  );

  for (final operation in ['confirm', 'refresh', 'resend']) {
    for (final status in [400, 401, 429, 503, 302]) {
      test(
        '$operation sanitizes $status and 401 clears entire session',
        () async {
          setup(
            (_) async => http.Response(
              'private backend body $verificationToken',
              status,
            ),
          );
          addTearDown(session.dispose);
          await login();
          switch (operation) {
            case 'confirm':
              await session.confirmEmail(verificationToken);
            case 'refresh':
              await session.refreshUser();
            case 'resend':
              await session.resendVerification();
          }
          expect(session.message, isNot(contains(verificationToken)));
          expect(session.message, isNot(contains('private backend')));
          expect(session.message, isNot(contains('password')));
          expect(session.verificationBusy, isFalse);
          if (status == 401) {
            expect(session.state, SessionState.signedOut);
            expect(session.user, isNull);
            expect(session.message, AuthTransport.expired);
            await session.logout();
            expect(requests.length, 3);
          } else {
            expect(session.user!.emailVerified, isFalse);
            if (status == 400) {
              expect(session.message, AuthTransport.invalidVerification);
            }
            if (status == 429) expect(session.resendCooldownSeconds, 60);
          }
        },
      );
    }
  }

  test(
    'replayed confirmation gets safe invalid/expired/reused/wrong-account message',
    () async {
      var confirmations = 0;
      setup(
        (_) async => ++confirmations == 1
            ? jsonResponse(verifiedUser)
            : jsonResponse({'code': 'invalid_verification_token'}, 400),
      );
      addTearDown(session.dispose);
      await login();
      await session.confirmEmail(verificationToken);
      await session.confirmEmail(verificationToken);
      expect(session.message, AuthTransport.invalidVerification);
      expect(session.user!.emailVerified, isTrue);
    },
  );

  test('resend 204 sends bearer without body, respects 60s cooldown', () {
    fakeAsync((async) {
      setup((_) async => http.Response('', 204));
      session.login('person@example.com', 'password');
      async.flushMicrotasks();
      session.resendVerification();
      async.flushMicrotasks();
      expect(requests.last.url.path, '/api/v1/auth/email-verification/resend');
      expect(requests.last.method, 'POST');
      expect(requests.last.body, isEmpty);
      expect(requests.last.headers['authorization'], 'Bearer account-bearer');
      expect(requests.last.headers.containsKey('content-type'), isFalse);
      expect(session.message, contains('accepted'));
      expect(session.resendCooldownSeconds, 60);
      session.resendVerification();
      async.flushMicrotasks();
      expect(requests.length, 3);
      now = epoch.add(const Duration(seconds: 59));
      expect(session.resendCooldownSeconds, 1);
      session.resendVerification();
      async.flushMicrotasks();
      expect(requests.length, 3);
      now = epoch.add(const Duration(seconds: 60));
      session.resendVerification();
      async.flushMicrotasks();
      expect(requests.length, 4);
      session.dispose();
    });
  });

  test('already verified resend 204 never claims a mail was sent', () async {
    setup(
      (_) async => http.Response('', 204),
      handshake: verifiedUser,
      me: verifiedUser,
    );
    addTearDown(session.dispose);
    await login();
    await session.resendVerification();
    expect(
      session.message,
      contains('already verified accounts receive no new mail'),
    );
    expect(session.user!.emailVerified, isTrue);
  });

  test('refresh detects both false to true and true to false', () async {
    var verified = true;
    setup(
      (_) async => jsonResponse({...pendingUser, 'emailVerified': verified}),
    );
    addTearDown(session.dispose);
    await login();
    await session.refreshUser();
    expect(session.user!.emailVerified, isTrue);
    expect(requests.last.method, 'GET');
    expect(requests.last.url.path, '/api/v1/me');
    verified = false;
    await session.refreshUser();
    expect(session.user!.emailVerified, isFalse);
  });

  for (final confirm in [true, false]) {
    for (final bad in [
      {...verifiedUser, 'id': 'different-account'},
      {...verifiedUser, 'emailVerified': 'true'},
      {},
      if (confirm) pendingUser,
    ]) {
      test(
        '${confirm ? 'confirm' : 'refresh'} rejects malformed/mismatched response ${bad.length}/${bad['id']}/${bad['emailVerified']}',
        () async {
          setup((_) async => jsonResponse(bad));
          addTearDown(session.dispose);
          await login();
          if (confirm) {
            await session.confirmEmail(verificationToken);
          } else {
            await session.refreshUser();
          }
          expect(session.state, SessionState.signedOut);
          expect(session.user, isNull);
          expect(session.message, AuthTransport.invalidResponse);
          await session.logout();
          expect(requests.length, 3);
        },
      );
    }
  }

  for (final confirm in [true, false]) {
    for (final cancellation in ['logout', 'dispose', 'expiry', 'new-login']) {
      test(
        'late ${confirm ? 'confirm' : 'refresh'} cannot resurrect after $cancellation',
        () async {
          final response = Completer<http.Response>();
          final reached = Completer<void>();
          setup((request) {
            if (!reached.isCompleted) {
              reached.complete();
              return response.future;
            }
            return Future.value(jsonResponse(pendingUser));
          });
          await login();
          var notifications = 0;
          session.addListener(() => notifications++);
          final pending = confirm
              ? session.confirmEmail(verificationToken)
              : session.refreshUser();
          await reached.future;
          await session.refreshUser();
          await session.confirmEmail(verificationToken);
          await session.resendVerification();
          expect(
            requests.length,
            3,
            reason: 'all overlapping account operations ignored',
          );
          switch (cancellation) {
            case 'logout':
              await session.logout();
            case 'dispose':
              session.dispose();
            case 'expiry':
              now = epoch.add(const Duration(minutes: 30));
              session.checkExpiry();
            case 'new-login':
              await session.logout();
              await login();
          }
          final before = notifications;
          response.complete(jsonResponse(verifiedUser));
          await pending;
          expect(notifications, before);
          if (cancellation == 'new-login') {
            expect(session.user!.emailVerified, isFalse);
          } else {
            expect(session.state, SessionState.signedOut);
            expect(session.user, isNull);
          }
          if (cancellation != 'dispose') session.dispose();
        },
      );
    }
  }

  test('stale 401 cannot expire a newer login', () async {
    final old = Completer<http.Response>();
    final reached = Completer<void>();
    setup((_) {
      if (!reached.isCompleted) {
        reached.complete();
        return old.future;
      }
      return Future.value(jsonResponse(pendingUser));
    });
    addTearDown(session.dispose);
    await login();
    final pending = session.refreshUser();
    await reached.future;
    await session.logout();
    await login();
    old.complete(http.Response('', 401));
    await pending;
    expect(session.state, SessionState.signedIn);
    expect(session.user!.emailVerified, isFalse);
  });

  test('verification success never extends absolute session expiry', () {
    fakeAsync((async) {
      setup((_) async => jsonResponse(verifiedUser));
      session.login('person@example.com', 'password');
      async.flushMicrotasks();
      now = epoch.add(const Duration(minutes: 29));
      async.elapse(const Duration(minutes: 29));
      session.confirmEmail(verificationToken);
      async.flushMicrotasks();
      expect(session.user!.emailVerified, isTrue);
      now = epoch.add(const Duration(minutes: 30));
      async.elapse(const Duration(minutes: 1));
      expect(session.state, SessionState.signedOut);
      session.dispose();
    });
  });

  test('timeout ignores late verification success', () {
    fakeAsync((async) {
      final pending = Completer<http.Response>();
      setup((_) => pending.future);
      session.login('person@example.com', 'password');
      async.flushMicrotasks();
      session.confirmEmail(verificationToken);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 15));
      expect(session.message, contains('timed out'));
      expect(session.verificationBusy, isFalse);
      pending.complete(jsonResponse(verifiedUser));
      async.flushMicrotasks();
      expect(session.user!.emailVerified, isFalse);
      session.dispose();
    });
  });

  group('ephemeral verification links', () {
    final origin = Uri.parse('https://app.example.com');
    test('raw token and exact trusted fragment/path links only', () {
      for (final value in [
        verificationToken,
        'https://app.example.com/#/verify-email?token=$verificationToken',
        'https://app.example.com/verify-email?token=$verificationToken',
      ]) {
        expect(
          parseVerificationToken(value, trustedOrigin: origin),
          verificationToken,
        );
      }
      expect(
        parseVerificationToken(
          '/verify-email?token=$verificationToken',
          trustedOrigin: origin,
          allowRoute: true,
        ),
        verificationToken,
      );
      expect(parseVerificationToken(verificationToken), verificationToken);
    });
    final invalid = [
      '',
      'short',
      '${verificationToken}a',
      '${verificationToken.substring(1)}=',
      'https://evil.example/#/verify-email?token=$verificationToken',
      'http://app.example.com/#/verify-email?token=$verificationToken',
      'https://app.example.com:444/#/verify-email?token=$verificationToken',
      'https://user:pass@app.example.com/#/verify-email?token=$verificationToken',
      'https://app.example.com/?token=$verificationToken',
      'https://app.example.com/#/other?token=$verificationToken',
      'https://app.example.com/path/#/verify-email?token=$verificationToken',
      'https://app.example.com/#/verify-email',
      'https://app.example.com/#/verify-email?token=',
      'https://app.example.com/#/verify-email?token=$verificationToken&token=$verificationToken',
      'https://app.example.com/#/verify-email?token=$verificationToken&next=https://evil.example',
      '//app.example.com/#/verify-email?token=$verificationToken',
      'javascript:alert(1)',
      '%',
    ];
    for (var i = 0; i < invalid.length; i++) {
      test('rejects malformed/untrusted input case $i', () {
        expect(
          parseVerificationToken(invalid[i], trustedOrigin: origin),
          isNull,
        );
      });
    }
    test('native full links require configured trusted frontend origin', () {
      expect(
        parseVerificationToken(
          'https://app.example.com/#/verify-email?token=$verificationToken',
        ),
        isNull,
      );
    });
    test(
      'initial and navigated URL scrub precedes listeners; consume once; dispose',
      () {
        final source = FakeLinkSource(
          'https://app.example.com/#/verify-email?token=$verificationToken',
        );
        final links = VerificationLinks(source: source);
        expect(source.scrubs, 1);
        expect(source.url, 'https://app.example.com/#/');
        expect(links.hasPending, isTrue);
        expect(links.takePending(), verificationToken);
        expect(links.takePending(), isNull);
        links.addListener(
          () => expect(source.url, 'https://app.example.com/#/'),
        );
        source.navigate(
          'https://app.example.com/#/verify-email?token=$verificationToken',
        );
        expect(source.scrubs, 2);
        expect(links.hasPending, isTrue);
        links.clear();
        expect(links.hasPending, isFalse);
        source.navigate('https://app.example.com/#/verify-email');
        expect(links.message, VerificationLinks.invalidLink);
        expect(links.hasPending, isFalse);
        links.dispose();
        expect(source.disposed, isTrue);
      },
    );
  });
}
