import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'onboarding.dart';
import 'platform_client.dart';

class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.emailVerified,
  });

  factory AccountUser.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    if (value['emailVerified'] is! bool) throw const FormatException();
    return AccountUser(
      id: _text(value['id']),
      email: _text(value['email']),
      displayName: _text(value['displayName']),
      emailVerified: value['emailVerified'] as bool,
    );
  }

  final String id;
  final String email;
  final String displayName;
  final bool emailVerified;
}

String _text(Object? value) {
  if (value is! String || value.trim().isEmpty) throw const FormatException();
  return value;
}

class AuthFailure implements Exception {
  const AuthFailure(
    this.message, {
    this.endsSession = false,
    this.cooldown = false,
  });
  final String message;
  final bool endsSession;
  final bool cooldown;

  @override
  String toString() => message;
}

class AuthenticatedAccount {
  const AuthenticatedAccount(this.user, this.expiresAt);
  final AccountUser user;
  final DateTime expiresAt;
}

/// Sole owner of the bearer token; nothing persists it or exposes it to widgets.
/// Owns its client, including when a client is injected by tests.
class AuthTransport {
  AuthTransport({
    required ApiConfig config,
    http.Client? client,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 15),
  }) : _config = config,
       _client = client ?? createAuthClient(),
       _clock = clock ?? DateTime.now;

  final ApiConfig _config;
  final http.Client _client;
  final DateTime Function() _clock;
  final Duration timeout;
  final _pending = <Completer<void>>{};
  String? _token;
  String? _accountId;
  bool _emailVerified = false;
  int _generation = 0;
  bool _disposed = false;

  static const invalidResponse =
      'The sign-in service returned an invalid response. Please try again.';
  static const expired = 'Your session expired. Please sign in again.';
  static const invalidVerification =
      'This verification token is invalid, expired, already used, or belongs to another account. Check the account email or request a new token.';
  static const signupMailUnavailable =
      'Verification mail is unavailable. Your account may already exist. Please sign in and resend verification instead of repeatedly signing up.';

  Future<http.Response> _request(
    String method,
    String path, {
    String? token,
    Map<String, String>? body,
  }) async {
    if (_disposed) throw const AuthFailure('Session closed.');
    final abort = Completer<void>();
    _pending.add(abort);
    final request = http.AbortableRequest(
      method,
      _config.endpoint("/api/v1$path"),
      abortTrigger: abort.future,
    )..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const AuthFailure('The request timed out. Please try again.');
    } catch (_) {
      throw const AuthFailure(
        'Unable to reach the sign-in service. Please try again.',
      );
    } finally {
      // Also abort a timed-out request rather than letting it keep running.
      if (!abort.isCompleted) abort.complete();
      _pending.remove(abort);
    }
  }

  void _checkCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw const AuthFailure('Sign-in canceled.');
    }
  }

  void _expectSuccess(http.Response response, {bool login = false}) {
    if (response.statusCode == 200) return;
    throw AuthFailure(switch (response.statusCode) {
      401 => login ? 'Email or password is incorrect.' : expired,
      409 => 'Email is already registered. Please sign in.',
      429 => 'Too many sign-in attempts. Please wait and try again.',
      400 => 'Please check your email and password and try again.',
      _ => 'The sign-in service is unavailable. Please try again.',
    });
  }

  Future<AuthenticatedAccount> signUp(
    String userName,
    String email,
    String password,
  ) async {
    clearSession();
    final generation = _generation;
    final started = _clock().toUtc();
    try {
      final response = await _request(
        'POST',
        '/auth/register',
        body: {
          'displayName': userName.trim(),
          'email': email.trim(),
          'password': password,
        },
      );
      _checkCurrent(generation);
      if (response.statusCode == 503) {
        throw const AuthFailure(signupMailUnavailable);
      }
      _expectSuccess(response);
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      final token = _text(json['accessToken']);
      if (!RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(token)) {
        throw const FormatException();
      }
      final expiryText = _text(json['expiresAt']);
      if (!RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|\+00:00)$',
      ).hasMatch(expiryText)) {
        throw const FormatException();
      }
      var expiresAt = DateTime.parse(expiryText).toUtc();
      if (expiresAt.toIso8601String().substring(0, 19) !=
          expiryText.substring(0, 19)) {
        throw const FormatException();
      }
      final maximum = started.add(const Duration(minutes: 30));
      if (expiresAt.isAfter(maximum)) expiresAt = maximum;
      final signUpUser = AccountUser.fromJson(json['user']);
      if (!expiresAt.isAfter(_clock())) throw const AuthFailure(expired);
      _token = token;
      final me = await _request('GET', '/me', token: _token);
      _checkCurrent(generation);
      _expectSuccess(me);
      final user = AccountUser.fromJson(jsonDecode(utf8.decode(me.bodyBytes)));
      if (user.id != signUpUser.id) throw const FormatException();
      if (!expiresAt.isAfter(_clock())) throw const AuthFailure(expired);
      _accountId = user.id;
      _emailVerified = user.emailVerified;
      return AuthenticatedAccount(user, expiresAt);
    } on AuthFailure {
      if (generation == _generation) clearSession();
      rethrow;
    } catch (_) {
      if (generation == _generation) clearSession();
      throw const AuthFailure(invalidResponse);
    }
  }

  Future<AuthenticatedAccount> login(String email, String password) async {
    clearSession();
    final generation = _generation;
    final started = _clock().toUtc();
    try {
      final response = await _request(
        'POST',
        '/auth/login',
        body: {'email': email.trim(), 'password': password},
      );
      _checkCurrent(generation);
      _expectSuccess(response, login: true);
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      final token = _text(json['accessToken']);
      if (!RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(token)) {
        throw const FormatException();
      }
      final expiryText = _text(json['expiresAt']);
      if (!RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|\+00:00)$',
      ).hasMatch(expiryText)) {
        throw const FormatException();
      }
      var expiresAt = DateTime.parse(expiryText).toUtc();
      // DateTime.parse normalizes invalid days/months instead of rejecting them.
      if (expiresAt.toIso8601String().substring(0, 19) !=
          expiryText.substring(0, 19)) {
        throw const FormatException();
      }
      // Absolute deadline only: activity never extends the 30-minute session.
      final maximum = started.add(const Duration(minutes: 30));
      if (expiresAt.isAfter(maximum)) expiresAt = maximum;
      final loginUser = AccountUser.fromJson(json['user']);
      if (!expiresAt.isAfter(_clock())) throw const AuthFailure(expired);
      _token = token;
      final me = await _request('GET', '/me', token: _token);
      _checkCurrent(generation);
      _expectSuccess(me);
      final user = AccountUser.fromJson(jsonDecode(utf8.decode(me.bodyBytes)));
      if (user.id != loginUser.id) throw const FormatException();
      if (!expiresAt.isAfter(_clock())) throw const AuthFailure(expired);
      _accountId = user.id;
      _emailVerified = user.emailVerified;
      return AuthenticatedAccount(user, expiresAt);
    } on AuthFailure {
      if (generation == _generation) clearSession();
      rethrow;
    } catch (_) {
      if (generation == _generation) clearSession();
      throw const AuthFailure(invalidResponse);
    }
  }

  void _expectVerification(http.Response response, int expected) {
    if (response.statusCode == expected) return;
    if (response.statusCode == 401) {
      clearSession();
      throw const AuthFailure(expired, endsSession: true);
    }
    throw AuthFailure(switch (response.statusCode) {
      400 => invalidVerification,
      429 => 'Too many verification attempts. Please wait before trying again.',
      503 =>
        'Verification mail or service is unavailable. Please try again later.',
      _ => 'The verification service is unavailable. Please try again later.',
    }, cooldown: response.statusCode == 429);
  }

  Future<http.Response> _accountRequest(
    String method,
    String path, {
    Map<String, String>? body,
    int expected = 200,
  }) async {
    final generation = _generation;
    if (_token == null || _accountId == null) {
      throw const AuthFailure(expired, endsSession: true);
    }
    final response = await _request(method, path, token: _token, body: body);
    _checkCurrent(generation);
    _expectVerification(response, expected);
    return response;
  }

  AccountUser _readCurrentUser(
    http.Response response, {
    bool confirmed = false,
  }) {
    try {
      final user = AccountUser.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
      if (user.id != _accountId || (confirmed && !user.emailVerified)) {
        throw const FormatException();
      }
      _emailVerified = user.emailVerified;
      return user;
    } catch (_) {
      clearSession();
      throw const AuthFailure(invalidResponse, endsSession: true);
    }
  }

  Future<AccountUser> _loadUser(
    String method,
    String path, {
    Map<String, String>? body,
    bool confirmed = false,
  }) async {
    final generation = _generation;
    final response = await _accountRequest(method, path, body: body);
    _checkCurrent(generation);
    return _readCurrentUser(response, confirmed: confirmed);
  }

  Future<AccountUser> refreshUser() => _loadUser('GET', '/me');

  Future<AccountUser> confirmEmail(String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const AuthFailure(invalidVerification);
    }
    return _loadUser(
      'POST',
      '/auth/email-verification/confirm',
      body: {'token': token},
      confirmed: true,
    );
  }

  Future<void> resendVerification() async {
    await _accountRequest(
      'POST',
      '/auth/email-verification/resend',
      expected: 204,
    );
  }

  static const onboardingUnavailable =
      'Organization status could not be confirmed. Refresh status before trying again; the previous action may have completed.';
  static const invitationUnavailable =
      'This invitation is unavailable. Check the signed-in email and ask the owner for a new code. It may be expired, used, or revoked.';

  // Uses the same cookie-free request helper and credential generation as auth.
  // Check the generation before status handling AND before parsing any data.
  Future<T> _organizationRequest<T>(
    String method,
    String path,
    T Function(Object?) parse, {
    Map<String, String>? body,
    int expected = 200,
  }) async {
    final generation = _generation;
    if (_disposed || _token == null || _accountId == null) {
      throw const AuthFailure(expired, endsSession: true);
    }
    if (!_emailVerified) {
      throw const AuthFailure(
        'Verify your email before organization onboarding.',
      );
    }
    final response = await _request(method, path, token: _token, body: body);
    _checkCurrent(generation);
    if (response.statusCode == 401) {
      clearSession();
      throw const AuthFailure(expired, endsSession: true);
    }
    if (response.statusCode != expected) {
      throw AuthFailure(switch (response.statusCode) {
        400 =>
          path.startsWith('/onboarding/invitations/')
              ? invitationUnavailable
              : 'The organization request was invalid. Check the name or recipient email, then refresh status.',
        403 =>
          'Organization access was denied. Refresh status or check email verification; no organization access is confirmed.',
        404 => 'The invitation was not found. Refresh status.',
        409 =>
          'Organization or invitation status changed. Refresh status; membership may already exist or the setup or invitation may be unavailable.',
        429 =>
          'Too many organization requests. Please wait, then refresh status.',
        _ => onboardingUnavailable,
      });
    }
    try {
      _checkCurrent(generation);
      final result = parse(
        expected == 204 ? null : jsonDecode(utf8.decode(response.bodyBytes)),
      );
      _checkCurrent(generation);
      return result;
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(onboardingUnavailable);
    }
  }

  Future<OnboardingContext> loadOnboarding() =>
      _organizationRequest('GET', '/onboarding', OnboardingContext.fromJson);

  Future<OnboardingContext> saveBootstrap(String name) {
    final trimmed = name.trim();
    try {
      onboardingText(trimmed);
    } catch (_) {
      throw const AuthFailure(
        'Enter an organization name of 1–120 characters.',
      );
    }
    return _organizationRequest(
      'POST',
      '/onboarding/bootstrap',
      OnboardingContext.fromJson,
      body: {'name': trimmed},
    );
  }

  Future<OnboardingContext> activateBootstrap(String id) {
    onboardingId(id);
    return _organizationRequest(
      'POST',
      '/onboarding/bootstrap/activate',
      OnboardingContext.fromJson,
      body: {'bootstrapId': id},
    );
  }

  Future<void> cancelBootstrap(String id) {
    onboardingId(id);
    return _organizationRequest(
      'POST',
      '/onboarding/bootstrap/cancel',
      (_) {},
      body: {'bootstrapId': id},
      expected: 204,
    );
  }

  Future<List<OrganizationInvitation>> loadInvitations() =>
      _organizationRequest(
        'GET',
        '/organization/invitations',
        OrganizationInvitation.listFromJson,
      );

  Future<IssuedInvitation> createInvitation(String email) {
    final normalized = email.trim().toLowerCase();
    try {
      invitationEmail(normalized);
    } catch (_) {
      throw const AuthFailure(
        'Enter a valid invitation email (maximum 254 characters).',
      );
    }
    return _organizationRequest(
      'POST',
      '/organization/invitations',
      IssuedInvitation.fromJson,
      body: {'email': normalized},
      expected: 201,
    );
  }

  Future<void> revokeInvitation(String id) {
    onboardingId(id);
    return _organizationRequest(
      'POST',
      '/organization/invitations/$id/revoke',
      (_) {},
      expected: 204,
    );
  }

  Future<InvitationPreview> previewInvitation(String token) {
    if (!validInvitationCode(token)) {
      throw const AuthFailure(invitationUnavailable);
    }
    return _organizationRequest(
      'POST',
      '/onboarding/invitations/preview',
      InvitationPreview.fromJson,
      body: {'token': token},
    );
  }

  Future<OnboardingContext> acceptInvitation(String token) {
    if (!validInvitationCode(token)) {
      throw const AuthFailure(invitationUnavailable);
    }
    return _organizationRequest(
      'POST',
      '/onboarding/invitations/accept',
      OnboardingContext.fromJson,
      body: {'token': token},
    );
  }

  /// Clear local credentials before attempting remote revocation.
  /// A login in flight may create a server session whose token is never received.
  Future<bool> logout() async {
    final token = _token;
    final hadPending = _pending.isNotEmpty;
    clearSession();
    if (token == null) return !hadPending;
    try {
      final response = await _request('POST', '/auth/logout', token: token);
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// Cancel account-page work without ending or extending the bearer session.
  void cancelAccountRequests() {
    _generation++;
    for (final abort in _pending) {
      if (!abort.isCompleted) abort.complete();
    }
    _pending.clear();
  }

  void clearSession() {
    cancelAccountRequests();
    _token = null;
    _accountId = null;
    _emailVerified = false;
  }

  void dispose() {
    _disposed = true;
    clearSession();
    _client.close();
  }
}
