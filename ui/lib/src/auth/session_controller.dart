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

  SessionState get state => _state;
  AccountUser? get user => _user;
  String? get message => _message;
  bool get isSigningIn => _state == SessionState.signingIn;

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
