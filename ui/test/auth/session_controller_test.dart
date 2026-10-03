import 'dart:async';
import 'dart:convert';

import 'package:bahir_ledger/src/auth/api_config.dart';
import 'package:bahir_ledger/src/auth/auth_transport.dart';
import 'package:bahir_ledger/src/auth/session_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const user = {
  'id': 'user-1',
  'email': 'person@example.com',
  'displayName': 'Local User',
  'emailVerified': true,
};
final start = DateTime.utc(2026, 10, 3, 12);

http.Response loginResponse({
  String token = 'private-token',
  DateTime? expiry,
}) => http.Response(
  jsonEncode({
    'accessToken': token,
    'expiresAt': (expiry ?? start.add(const Duration(minutes: 30)))
        .toIso8601String(),
    'user': user,
  }),
  200,
);

void main() {
  late DateTime now;
  late List<http.Request> requests;
  late SessionController session;
  late AuthTransport transport;

  void setupClient(
    Future<http.Response> Function(http.Request) handler, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    transport = AuthTransport(
      config: ApiConfig('https://api.example.com'),
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
      clock: () => now,
      timeout: timeout,
    );
    session = SessionController(transport: transport, clock: () => now);
  }

  Future<http.Response> success(http.Request request) async {
    if (request.url.path.endsWith('/login') ||
        request.url.path.endsWith('/register')) {
      return loginResponse();
    }
    if (request.url.path.endsWith('/logout')) return http.Response('', 204);
    return http.Response(
      jsonEncode({...user, 'displayName': 'Verified by me'}),
      200,
    );
  }

  setUp(() {
    now = start;
    requests = [];
  });

  group('API origin validation', () {
    test('HTTPS and exact debug loopbacks accepted, including IPv6', () {
      expect(
        ApiConfig('https://api.example.com/').endpoint('/api/v1/me').toString(),
        'https://api.example.com/api/v1/me',
      );
      for (final host in ['localhost', '127.0.0.1', '[::1]']) {
        expect(
          ApiConfig(
            'http://$host:8080',
            allowDevelopmentHttp: true,
          ).origin.port,
          8080,
        );
      }
    });
    for (final value in [
      '',
      'not a url',
      '//api.example.com',
      'ftp://api.example.com',
      'http://api.example.com',
      'http://192.168.1.2:8080',
      'http://localhost.evil.test',
      'https://user:secret@api.example.com',
      'https://api.example.com/api',
      'https://api.example.com?token=secret',
      'https://api.example.com#fragment',
      ' https://api.example.com',
      'https://api.example.com:0',
      'https://api.example.com:99999',
    ]) {
      test('rejects invalid/unsafe origin $value', () {
        expect(() => ApiConfig(value), throwsFormatException);
      });
    }
    test('production disallows loopback HTTP', () {
      expect(
        () => ApiConfig('http://localhost:8080', allowDevelopmentHttp: false),
        throwsFormatException,
      );
    });
  });

  test(
    'login JSON, trimmed email, exact password, then Bearer me, no cookies or redirects',
    () async {
      setupClient(success);
      addTearDown(session.dispose);
      await session.login(' person@example.com ', '  keep password spaces  ');
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/v1/auth/login',
        'GET /api/v1/me',
      ]);
      expect(jsonDecode(requests.first.body), {
        'email': 'person@example.com',
        'password': '  keep password spaces  ',
      });
      expect(
        requests.first.headers['content-type'],
        contains('application/json'),
      );
      expect(requests.first.headers.containsKey('authorization'), isFalse);
      expect(requests.last.headers['authorization'], 'Bearer private-token');
      for (final request in requests) {
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
      }
      expect(session.state, SessionState.signedIn);
      expect(session.user!.displayName, 'Verified by me');
    },
  );

  test(
    'signup sends the versioned register route then verifies identity',
    () async {
      setupClient(success);
      addTearDown(session.dispose);
      await session.signUp(
        ' Local User ',
        ' person@example.com ',
        ' exact password ',
      );
      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/v1/auth/register',
        'GET /api/v1/me',
      ]);
      expect(jsonDecode(requests.first.body), {
        'displayName': 'Local User',
        'email': 'person@example.com',
        'password': ' exact password ',
      });
      expect(requests.first.headers.containsKey('authorization'), isFalse);
      expect(requests.last.headers['authorization'], 'Bearer private-token');
      expect(session.state, SessionState.signedIn);
      expect(session.user!.displayName, 'Verified by me');
    },
  );

  test(
    'duplicate signup shows a safe actionable error without loading me',
    () async {
      setupClient((_) async => http.Response('private server details', 409));
      addTearDown(session.dispose);
      await session.signUp('Local User', 'person@example.com', 'secret');
      expect(requests, hasLength(1));
      expect(session.state, SessionState.signedOut);
      expect(session.user, isNull);
      expect(session.message, 'Email is already registered. Please sign in.');
    },
  );

  test('empty credentials never send a request', () async {
    setupClient(success);
    addTearDown(session.dispose);
    await session.login(' ', '');
    expect(requests, isEmpty);
    expect(session.message, 'Enter your email and password.');
  });

  for (final entry in {
    401: 'Email or password is incorrect.',
    429: 'Too many sign-in attempts. Please wait and try again.',
    400: 'Please check your email and password and try again.',
    500: 'The sign-in service is unavailable. Please try again.',
    302: 'The sign-in service is unavailable. Please try again.',
  }.entries) {
    test('sanitized login failure ${entry.key}', () async {
      setupClient(
        (_) async =>
            http.Response('private-token password server trace', entry.key),
      );
      addTearDown(session.dispose);
      await session.login('person@example.com', 'secret');
      expect(session.state, SessionState.signedOut);
      expect(session.user, isNull);
      expect(session.message, entry.value);
      expect(requests, hasLength(1));
    });
  }

  test('network errors never leak diagnostics', () async {
    setupClient(
      (_) async =>
          throw http.ClientException('private-token password host internals'),
    );
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    expect(
      session.message,
      'Unable to reach the sign-in service. Please try again.',
    );
    expect(session.state, SessionState.signedOut);
  });

  for (final body in [
    '<html>private-token</html>',
    'null',
    '[]',
    '{}',
    jsonEncode({
      'accessToken': '',
      'expiresAt': '2026-10-03T12:30:00Z',
      'user': user,
    }),
    jsonEncode({
      'accessToken': 'token\r\ninjection',
      'expiresAt': '2026-10-03T12:30:00Z',
      'user': user,
    }),
    jsonEncode({
      'accessToken': 'token',
      'expiresAt': '2026-10-03T12:30:00',
      'user': user,
    }),
    jsonEncode({'accessToken': 'token', 'expiresAt': 'invalid', 'user': user}),
    jsonEncode({
      'accessToken': 'token',
      'expiresAt': '2026-10-03T12:30:00Z',
      'user': {'id': 1},
    }),
  ]) {
    test(
      'invalid login response is sanitized (${body.length} chars)',
      () async {
        setupClient((_) async => http.Response(body, 200));
        addTearDown(session.dispose);
        await session.login('person@example.com', 'secret');
        expect(session.state, SessionState.signedOut);
        expect(session.message, AuthTransport.invalidResponse);
        await session.logout();
        expect(requests, hasLength(1));
      },
    );
  }

  for (final response in [
    http.Response('{}', 200),
    http.Response(jsonEncode({...user, 'id': 'different'}), 200),
    http.Response('private-token', 401),
  ]) {
    test(
      'me must succeed and identify the same account (${response.statusCode}/${response.body.length})',
      () async {
        setupClient(
          (request) async =>
              request.url.path.endsWith('/login') ? loginResponse() : response,
        );
        addTearDown(session.dispose);
        await session.login('person@example.com', 'secret');
        expect(session.state, SessionState.signedOut);
        expect(session.user, isNull);
        expect(
          session.message,
          response.statusCode == 401
              ? AuthTransport.expired
              : AuthTransport.invalidResponse,
        );
        await session.logout();
        expect(
          requests,
          hasLength(2),
          reason: 'failed me must clear the token',
        );
      },
    );
  }

  test(
    'logout sends bearer, clears identity immediately and never reuses token',
    () async {
      final revoke = Completer<http.Response>();
      setupClient(
        (request) => request.url.path.endsWith('/logout')
            ? revoke.future
            : success(request),
      );
      addTearDown(session.dispose);
      await session.login('person@example.com', 'secret');
      final logout = session.logout();
      expect(session.state, SessionState.signedOut);
      expect(session.user, isNull);
      revoke.complete(http.Response('', 204));
      await logout;
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, '/api/v1/auth/logout');
      expect(requests.last.headers['authorization'], 'Bearer private-token');
      expect(requests.last.body, isEmpty);
      await session.logout();
      expect(requests, hasLength(3));
      await session.login('person@example.com', 'secret');
      expect(requests[3].headers.containsKey('authorization'), isFalse);
    },
  );

  for (final status in [401, 500]) {
    test(
      'failed remote logout $status still clears local session and warns',
      () async {
        setupClient(
          (request) => request.url.path.endsWith('/logout')
              ? Future.value(http.Response('secret detail', status))
              : success(request),
        );
        addTearDown(session.dispose);
        await session.login('person@example.com', 'secret');
        await session.logout();
        expect(session.user, isNull);
        expect(session.message, SessionController.revocationWarning);
        await session.logout();
        expect(requests, hasLength(3));
      },
    );
  }

  test('network logout failure warns without restoring credentials', () async {
    setupClient(
      (request) => request.url.path.endsWith('/logout')
          ? Future.error(http.ClientException('secret'))
          : success(request),
    );
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    await session.logout();
    expect(session.message, SessionController.revocationWarning);
    expect(session.state, SessionState.signedOut);
  });

  test('absolute expiry timer clears identity and token without refresh', () {
    fakeAsync((async) {
      setupClient(success);
      session.login('person@example.com', 'secret');
      async.flushMicrotasks();
      expect(session.state, SessionState.signedIn);
      now = start.add(const Duration(minutes: 30));
      async.elapse(const Duration(minutes: 30));
      expect(session.state, SessionState.signedOut);
      expect(session.user, isNull);
      expect(session.message, AuthTransport.expired);
      session.logout();
      async.flushMicrotasks();
      expect(requests, hasLength(2));
      session.dispose();
    });
  });

  test(
    'resume check enforces expiry without waiting for suspended timer',
    () async {
      setupClient(success);
      addTearDown(session.dispose);
      await session.login('person@example.com', 'secret');
      now = start.add(const Duration(hours: 1));
      session.checkExpiry();
      expect(session.state, SessionState.signedOut);
      expect(session.message, AuthTransport.expired);
    },
  );

  test('already expired login rejected before me', () async {
    setupClient((_) async => loginResponse(expiry: start));
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    expect(session.message, AuthTransport.expired);
    expect(requests, hasLength(1));
  });

  test('expiry reached while loading me cannot sign in', () async {
    setupClient((request) async {
      if (request.url.path.endsWith('/login')) return loginResponse();
      now = start.add(const Duration(minutes: 30));
      return http.Response(jsonEncode(user), 200);
    });
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    expect(session.message, AuthTransport.expired);
    expect(session.user, isNull);
  });

  test('late login after timeout never installs token', () {
    fakeAsync((async) {
      final pending = Completer<http.Response>();
      setupClient((_) => pending.future);
      session.login('person@example.com', 'secret');
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 15));
      expect(session.message, 'The request timed out. Please try again.');
      pending.complete(loginResponse());
      async.flushMicrotasks();
      expect(session.state, SessionState.signedOut);
      session.logout();
      async.flushMicrotasks();
      expect(requests, hasLength(1));
      session.dispose();
    });
  });

  test('duplicate submits ignored; logout invalidates pending login', () async {
    final pending = Completer<http.Response>();
    setupClient((_) => pending.future);
    addTearDown(session.dispose);
    final first = session.login('person@example.com', 'secret');
    await session.login('person@example.com', 'second');
    await session.logout();
    expect(session.message, SessionController.revocationWarning);
    pending.complete(loginResponse());
    await first;
    expect(session.state, SessionState.signedOut);
    expect(requests, hasLength(1));
  });

  test(
    'old login response cannot replace a newer successful session',
    () async {
      final old = Completer<http.Response>();
      var calls = 0;
      setupClient((request) {
        if (request.url.path.endsWith('/login') && calls++ == 0) {
          return old.future;
        }
        return success(request);
      });
      addTearDown(session.dispose);
      final first = session.login('person@example.com', 'first');
      // Let MockClient receive the first request before cancellation.
      await Future<void>.delayed(Duration.zero);
      await session.logout();
      await session.login('person@example.com', 'second');
      old.complete(loginResponse(token: 'old-token'));
      await first;
      expect(session.state, SessionState.signedIn);
      await session.logout();
      expect(requests.last.headers['authorization'], 'Bearer private-token');
    },
  );

  test('logout during me prevents late identity resurrection', () async {
    final me = Completer<http.Response>();
    final reachedMe = Completer<void>();
    setupClient((request) {
      if (request.url.path.endsWith('/me')) {
        reachedMe.complete();
        return me.future;
      }
      return success(request);
    });
    addTearDown(session.dispose);
    final login = session.login('person@example.com', 'secret');
    await reachedMe.future;
    await session.logout();
    me.complete(http.Response(jsonEncode(user), 200));
    await login;
    expect(session.state, SessionState.signedOut);
    expect(session.user, isNull);
    expect(requests.last.url.path, '/api/v1/auth/logout');
  });

  test('late old logout result does not erase a new session', () async {
    final oldLogout = Completer<http.Response>();
    setupClient(
      (request) => request.url.path.endsWith('/logout')
          ? oldLogout.future
          : success(request),
    );
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    final logout = session.logout();
    await session.login('person@example.com', 'new');
    oldLogout.complete(http.Response('', 500));
    await logout;
    expect(session.state, SessionState.signedIn);
    expect(session.message, isNull);
  });

  test('dispose during login does not notify or retain a session', () async {
    final pending = Completer<http.Response>();
    setupClient((_) => pending.future);
    var notifications = 0;
    session.addListener(() => notifications++);
    final login = session.login('person@example.com', 'secret');
    session.dispose();
    pending.complete(loginResponse());
    await login;
    expect(notifications, 1);
    expect(session.user, isNull);
    expect(session.state, SessionState.signedOut);
  });

  test('a fresh controller always starts signed out', () async {
    setupClient(success);
    await session.login('person@example.com', 'secret');
    session.dispose();
    setupClient(success);
    addTearDown(session.dispose);
    expect(session.state, SessionState.signedOut);
    expect(session.user, isNull);
  });

  test(
    'JSON identity is UTF-8 even when response headers omit charset',
    () async {
      const displayName = 'ሰላም · Zoë';
      setupClient((request) async {
        if (request.url.path.endsWith('/login')) return loginResponse();
        return http.Response.bytes(
          utf8.encode(jsonEncode({...user, 'displayName': displayName})),
          200,
        );
      });
      addTearDown(session.dispose);
      await session.login('person@example.com', 'secret');
      expect(session.user!.displayName, displayName);
    },
  );

  test('normalized invalid calendar dates are rejected', () async {
    setupClient(
      (_) async => http.Response(
        jsonEncode({
          'accessToken': 'token',
          'expiresAt': '2026-10-32T12:30:00Z',
          'user': user,
        }),
        200,
      ),
    );
    addTearDown(session.dispose);
    await session.login('person@example.com', 'secret');
    expect(session.message, AuthTransport.invalidResponse);
    expect(requests, hasLength(1));
  });

  test('server deadline cannot extend the session beyond 30 minutes', () {
    fakeAsync((async) {
      setupClient(
        (request) async => request.url.path.endsWith('/login')
            ? loginResponse(expiry: start.add(const Duration(hours: 2)))
            : http.Response(jsonEncode(user), 200),
      );
      session.login('person@example.com', 'secret');
      async.flushMicrotasks();
      expect(session.state, SessionState.signedIn);
      // Even a wall clock moving backwards must not prolong the elapsed timer.
      now = start.subtract(const Duration(hours: 1));
      async.elapse(const Duration(minutes: 30));
      expect(session.state, SessionState.signedOut);
      expect(session.message, AuthTransport.expired);
      session.dispose();
    });
  });

  test('logout timeout preserves local signout and warns', () {
    fakeAsync((async) {
      final pending = Completer<http.Response>();
      setupClient(
        (request) => request.url.path.endsWith('/logout')
            ? pending.future
            : success(request),
      );
      session.login('person@example.com', 'secret');
      async.flushMicrotasks();
      session.logout();
      expect(session.user, isNull);
      async.elapse(const Duration(seconds: 15));
      expect(session.message, SessionController.revocationWarning);
      pending.complete(http.Response('', 204));
      async.flushMicrotasks();
      expect(session.message, SessionController.revocationWarning);
      session.dispose();
    });
  });
}
