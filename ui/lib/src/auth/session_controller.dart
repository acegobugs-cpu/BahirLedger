import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_transport.dart';
import 'onboarding.dart';

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
  OnboardingContext? _onboarding;
  List<OrganizationInvitation> _invitations = const [];
  bool _onboardingBusy = false;
  String? _onboardingMessage;
  String? _shareCode;
  String? _acceptCode;
  InvitationPreview? _preview;
  DateTime? _codeExpiry;
  Timer? _codeTimer;
  int _privateRevision = 0;

  OnboardingContext? get onboarding => _onboarding;
  List<OrganizationInvitation> get invitations => _invitations;
  bool get onboardingBusy => _onboardingBusy;
  bool get accountBusy => _verificationBusy || _onboardingBusy;
  String? get onboardingMessage => _onboardingMessage;
  String? get shareCode => _shareCode;
  InvitationPreview? get invitationPreview => _preview;
  int get privateRevision => _privateRevision;
  bool get isOrganizationOwner =>
      _onboarding?.membership?.role == OrganizationRole.owner;

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
    if (_disposed || _state != SessionState.signedIn || accountBusy) {
      return;
    }
    final operation = ++_operation;
    _clearOnboarding();
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

  void _clearCodes() {
    _privateRevision++;
    _shareCode = null;
    _acceptCode = null;
    _preview = null;
    _codeExpiry = null;
    _codeTimer?.cancel();
    _codeTimer = null;
  }

  void _clearOnboarding() {
    _clearCodes();
    _onboarding = null;
    _invitations = const [];
    _onboardingMessage = null;
  }

  void dismissInvitation() {
    if (_disposed) return;
    // Dismissal must invalidate a pending response as well as visible codes.
    if (_onboardingBusy) {
      _operation++;
      _transport.cancelAccountRequests();
      _onboardingBusy = false;
      _clearOnboarding();
    } else {
      _clearCodes();
    }
    notifyListeners();
  }

  /// Called when leaving the account surface, without notifying during disposal.
  void leaveOnboarding() {
    if (_disposed) return;
    if (_onboardingBusy) {
      _operation++;
      _transport.cancelAccountRequests();
      _onboardingBusy = false;
      _clearOnboarding();
    } else {
      _clearCodes();
    }
  }

  void _expireCodesAt(DateTime expiry) {
    _codeExpiry = expiry;
    _codeTimer = Timer(expiry.difference(_clock()), () {
      if (_disposed) return;
      _clearCodes();
      notifyListeners();
    });
  }

  bool _onboardingCurrent(int operation) {
    if (!_current(operation)) return false;
    checkExpiry();
    return _current(operation);
  }

  // One epoch and one serialization gate for BOTH verification and onboarding.
  // Every awaited result is checked before publishing or issuing follow-up calls.
  Future<void> _organization(
    Future<void> Function(int operation) action,
  ) async {
    checkExpiry();
    if (_disposed ||
        _state != SessionState.signedIn ||
        _user?.emailVerified != true ||
        accountBusy) {
      return;
    }
    final operation = ++_operation;
    _clearCodes();
    _onboardingMessage = null;
    _onboardingBusy = true;
    notifyListeners();
    if (!_onboardingCurrent(operation)) return;
    try {
      await action(operation);
      if (!_onboardingCurrent(operation)) return;
    } on AuthFailure catch (failure) {
      if (!_onboardingCurrent(operation)) return;
      _clearOnboarding();
      if (failure.endsSession) {
        _transport.clearSession();
        _clearLocal();
        _message = failure.message;
      } else {
        _onboardingMessage = failure.message;
      }
    } catch (_) {
      if (!_onboardingCurrent(operation)) return;
      _clearOnboarding();
      _onboardingMessage = AuthTransport.onboardingUnavailable;
    } finally {
      if (_current(operation)) {
        _onboardingBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _publishContext(OnboardingContext value, int operation) async {
    if (!_onboardingCurrent(operation)) return;
    // No owner UI is published until its list request is also confirmed.
    var invitations = const <OrganizationInvitation>[];
    if (value.membership?.role == OrganizationRole.owner) {
      invitations = await _transport.loadInvitations();
      if (!_onboardingCurrent(operation)) return;
    }
    _onboarding = value;
    _invitations = invitations;
  }

  Future<void> refreshOnboarding() => _organization((operation) async {
    _onboarding = null;
    _invitations = const [];
    final value = await _transport.loadOnboarding();
    if (!_onboardingCurrent(operation)) return;
    await _publishContext(value, operation);
  });

  Future<void> saveOrganization(String name) {
    if (_onboarding == null || _onboarding!.membership != null) {
      return Future.value();
    }
    return _organization((operation) async {
      final value = await _transport.saveBootstrap(name);
      if (!_onboardingCurrent(operation)) return;
      await _publishContext(value, operation);
    });
  }

  Future<void> activateOrganization() {
    final setup = _onboarding?.bootstrap;
    if (setup == null) return Future.value();
    return _organization((operation) async {
      final value = await _transport.activateBootstrap(setup.id);
      if (!_onboardingCurrent(operation)) return;
      await _publishContext(value, operation);
    });
  }

  Future<void> cancelOrganization() {
    final setup = _onboarding?.bootstrap;
    if (setup == null) return Future.value();
    return _organization((operation) async {
      await _transport.cancelBootstrap(setup.id);
      if (!_onboardingCurrent(operation)) return;
      final value = await _transport.loadOnboarding();
      if (!_onboardingCurrent(operation)) return;
      await _publishContext(value, operation);
    });
  }

  Future<void> invite(String email) {
    if (!isOrganizationOwner) return Future.value();
    return _organization((operation) async {
      final issued = await _transport.createInvitation(email);
      if (!_onboardingCurrent(operation)) return;
      if (!issued.invitation.expiresAt.isAfter(_clock()) ||
          issued.invitation.email != email.trim().toLowerCase()) {
        throw const AuthFailure(AuthTransport.onboardingUnavailable);
      }
      // Keep the new code private until refreshed context confirms ownership.
      final value = await _transport.loadOnboarding();
      if (!_onboardingCurrent(operation)) return;
      final organizationId = _onboarding?.membership?.organizationId;
      await _publishContext(value, operation);
      if (!_onboardingCurrent(operation)) return;
      if (!isOrganizationOwner ||
          value.membership?.organizationId != organizationId ||
          !issued.invitation.expiresAt.isAfter(_clock()) ||
          !_invitations.any(
            (item) =>
                item.id == issued.invitation.id &&
                item.email == issued.invitation.email &&
                item.status == InvitationStatus.pending &&
                item.expiresAt.isAfter(_clock()),
          )) {
        throw const AuthFailure(AuthTransport.onboardingUnavailable);
      }
      _shareCode = issued.code;
      _expireCodesAt(issued.invitation.expiresAt);
    });
  }

  Future<void> revokeInvitation(String id) {
    if (!isOrganizationOwner ||
        !_invitations.any(
          (item) => item.id == id && item.status == InvitationStatus.pending,
        )) {
      return Future.value();
    }
    return _organization((operation) async {
      await _transport.revokeInvitation(id);
      if (!_onboardingCurrent(operation)) return;
      final value = await _transport.loadOnboarding();
      if (!_onboardingCurrent(operation)) return;
      await _publishContext(value, operation);
    });
  }

  Future<void> previewInvitation(String code) {
    if (_onboarding == null || _onboarding!.membership != null) {
      return Future.value();
    }
    return _organization((operation) async {
      final preview = await _transport.previewInvitation(code);
      if (!_onboardingCurrent(operation)) return;
      if (!preview.expiresAt.isAfter(_clock())) {
        throw const AuthFailure(AuthTransport.invitationUnavailable);
      }
      _preview = preview;
      _acceptCode = code;
      _expireCodesAt(preview.expiresAt);
    });
  }

  Future<void> acceptInvitation() {
    checkExpiry();
    final code = _acceptCode;
    if (code == null || _preview == null || _onboarding?.membership != null) {
      return Future.value();
    }
    return _organization((operation) async {
      final value = await _transport.acceptInvitation(code);
      if (!_onboardingCurrent(operation)) return;
      await _publishContext(value, operation);
    });
  }

  /// Called on resume too: backgrounded browser/native timers can be suspended.
  void checkExpiry() {
    if (!_disposed && _codeExpiry != null && !_clock().isBefore(_codeExpiry!)) {
      _clearCodes();
      notifyListeners();
    }
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
    _clearOnboarding();
    _onboardingBusy = false;
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
