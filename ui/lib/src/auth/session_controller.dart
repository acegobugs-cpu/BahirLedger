import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_transport.dart';

enum SessionState { signedOut, signingIn, signedIn }

/// App-scoped session, deliberately not restored after a restart or web reload.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthTransport transport,
    DateTime Function()? clock,
  }) : _transport = transport,
       _clock = clock ?? DateTime.now;

  final AuthTransport _transport;
  final DateTime Function() _clock;
  SessionState _state = SessionState.signedOut;
  AccountUser? _user;
  DateTime? _expiresAt;
  String? _message;
  Timer? _expiryTimer;
  bool _disposed = false;
  int _operation = 0;
  bool _verificationBusy = false;
  DateTime? _resendAfter;

  SessionState get state => _state;
  AccountUser? get user => _user;
  String? get message => _message;
  bool get isSigningIn => _state == SessionState.signingIn;
  bool get verificationBusy => _verificationBusy;
  int get resendCooldownSeconds {
    final remaining = _resendAfter?.difference(_clock()).inMilliseconds ?? 0;
    return remaining <= 0 ? 0 : (remaining / 1000).ceil();
  }

  static const revocationWarning =
      'Signed out on this device. Remote revocation was not confirmed; the server session may remain valid until it expires.';

  bool _current(int operation) => !_disposed && operation == _operation;

  Future<void> signUp(String userName, String email, String password) async {
    if (_disposed || _state != SessionState.signedOut) return;
    if (userName.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      _message = 'Enter your user name, email, and password.';
      notifyListeners();
      return;
    }
    final operation = ++_operation;
    _message = null;
    _state = SessionState.signingIn;
    notifyListeners();
    if (!_current(operation)) return;
    try {
      final account = await _transport.signUp(userName, email, password);
      if (!_current(operation)) return;
      _user = account.user;
      _expiresAt = account.expiresAt;
      _state = SessionState.signedIn;
      checkExpiry();
      if (_state == SessionState.signedIn) {
        _expiryTimer = Timer(_expiresAt!.difference(_clock()), _expire);
      }
    } on AuthFailure catch (failure) {
      if (!_current(operation)) return;
      _clearLocal();
      _message = failure.message;
    } catch (_) {
      if (!_current(operation)) return;
      _transport.clearSession();
      _clearLocal();
      _message = 'Unable to sign up. Please try again.';
    }
    if (_current(operation)) notifyListeners();
  }

  Future<void> login(String email, String password) async {
    if (_disposed || _state != SessionState.signedOut) return;
    if (email.trim().isEmpty || password.isEmpty) {
      _message = 'Enter your email and password.';
      notifyListeners();
      return;
    }
    final operation = ++_operation;
    _message = null;
    _state = SessionState.signingIn;
    notifyListeners();
    if (!_current(operation)) return;
    try {
      final account = await _transport.login(email, password);
      if (!_current(operation)) return;
      _user = account.user;
      _expiresAt = account.expiresAt;
      _state = SessionState.signedIn;
      checkExpiry();
      if (_state == SessionState.signedIn) {
        // Elapsed-time expiry still signs out if the wall clock moves backwards.
        _expiryTimer = Timer(_expiresAt!.difference(_clock()), _expire);
      }
    } on AuthFailure catch (failure) {
      if (!_current(operation)) return;
      _clearLocal();
      _message = failure.message;
    } catch (_) {
      if (!_current(operation)) return;
      _transport.clearSession();
      _clearLocal();
      _message = 'Unable to sign in. Please try again.';
    }
    if (_current(operation)) notifyListeners();
  }

  Future<void> confirmEmail(String token) => _verify(
    () async {
      final user = await _transport.confirmEmail(token);
      return user;
    },
    success:
        'Email verified. No organization or project access has been granted.',
  );

  Future<void> refreshUser() => _verify(_transport.refreshUser);

  Future<void> resendVerification() async {
    if (resendCooldownSeconds > 0) return;
    await _verify(
      () async {
        await _transport.resendVerification();
        return null;
      },
      resend: true,
      success:
          'Verification request accepted. Check your email. Delivery is not guaranteed; already verified accounts receive no new mail.',
    );
  }

  // Serialize account operations. Logout/expiry/disposal invalidate their epoch;
  // neither a late success nor a late failure may affect a newer session.
  Future<void> _verify(
    Future<AccountUser?> Function() request, {
    bool resend = false,
    String? success,
  }) async {
    checkExpiry();
    if (_disposed || _state != SessionState.signedIn || _verificationBusy) {
      return;
    }
    final operation = ++_operation;
    _verificationBusy = true;
    _message = null;
    notifyListeners();
    if (!_current(operation)) return;
    try {
      final user = await request();
      if (!_current(operation)) return;
      checkExpiry();
      if (!_current(operation)) return;
      if (user != null) _user = user;
      if (resend) _resendAfter = _clock().add(const Duration(seconds: 60));
      _message =
          success ??
          (_user!.emailVerified
              ? 'Email verification is confirmed.'
              : 'Your email is not yet verified. Paste a token or request a new email.');
    } on AuthFailure catch (failure) {
      if (!_current(operation)) return;
      checkExpiry();
      if (!_current(operation)) return;
      if (failure.endsSession) {
        _transport.clearSession();
        _clearLocal();
      } else if (failure.cooldown) {
        _resendAfter = _clock().add(const Duration(seconds: 60));
      }
      _message = failure.message;
    } catch (_) {
      if (!_current(operation)) return;
      _message =
          'The verification service is unavailable. Please try again later.';
    } finally {
      if (_current(operation)) {
        _verificationBusy = false;
        notifyListeners();
      }
    }
  }

  /// Called on resume too: backgrounded browser/native timers can be suspended.
  void checkExpiry() {
    if (_disposed || _expiresAt == null) return;
    if (!_clock().isBefore(_expiresAt!)) {
      _expire();
    }
  }

  void _expire() {
    if (_disposed || _expiresAt == null) return;
    _operation++;
    _transport.clearSession();
    _clearLocal();
    _message = AuthTransport.expired;
    notifyListeners();
  }

  Future<void> logout() async {
    if (_disposed) return;
    final operation = ++_operation;
    final revocation = _transport.logout();
    _clearLocal();
    _message = 'Signed out on this device. Confirming remote revocation…';
    notifyListeners();
    final confirmed = await revocation;
    if (!_current(operation)) return;
    _message = confirmed ? 'You have signed out.' : revocationWarning;
    notifyListeners();
  }

  void _clearLocal() {
    _verificationBusy = false;
    _resendAfter = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiresAt = null;
    _user = null;
    _state = SessionState.signedOut;
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _clearLocal();
    _transport.dispose();
    super.dispose();
  }
}
