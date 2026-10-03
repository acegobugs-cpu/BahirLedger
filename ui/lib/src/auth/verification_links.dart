import 'package:flutter/foundation.dart';

import 'verification_link_platform.dart';
import 'verification_link_source.dart';

/// Only a raw token or the exact trusted verification route is accepted.
/// This is a local parser: it never follows a URL or performs a network lookup.
String? parseVerificationToken(
  String input, {
  Uri? trustedOrigin,
  bool allowRoute = false,
}) {
  final text = input.trim();
  final pattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  if (pattern.hasMatch(text)) return text;
  try {
    var uri = Uri.parse(text);
    if (uri.hasScheme || uri.hasAuthority) {
      if (trustedOrigin == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.origin != trustedOrigin.origin ||
          uri.userInfo.isNotEmpty) {
        return null;
      }
      if (uri.hasFragment) {
        if (uri.path != '/' || uri.hasQuery) return null;
        uri = Uri.parse(uri.fragment);
      }
    } else if (!allowRoute || !text.startsWith('/')) {
      return null;
    }
    if (uri.path != '/verify-email' || uri.hasFragment) return null;
    final query = uri.queryParametersAll;
    if (query.length != 1 || query['token']?.length != 1) return null;
    final token = query['token']!.single;
    return pattern.hasMatch(token) ? token : null;
  } catch (_) {
    return null;
  }
}

/// App-owned, ephemeral pending input across sign-in/sign-up routes.
class VerificationLinks extends ChangeNotifier {
  VerificationLinks({VerificationLinkSource? source})
    : _source = source ?? createVerificationLinkSource() {
    _captureLocation(notify: false);
    _source.listen(_captureLocation);
  }

  final VerificationLinkSource _source;
  String? _pending;
  String? _message;
  bool _disposed = false;
  int revision = 0;

  Uri? get trustedOrigin => _source.trustedOrigin;
  bool get hasPending => _pending != null;
  String? get message => _message;
  static const invalidLink =
      'The verification link is missing a valid token. Paste the token from your email or request a new email after signing in.';

  void _captureLocation({bool notify = true}) {
    if (_disposed) return;
    final url = _source.currentUrl;
    if (url == null) return;
    captureRoute(url, notify: notify);
  }

  /// Called before Flutter can put an incoming secret into route settings.
  bool captureRoute(String route, {bool notify = true}) {
    if (_disposed) return false;
    // Ordinary app routes contain neither input nor queries. Scrub any other
    // incoming URL, even a malformed one, without reflecting it into messages.
    final uri = Uri.tryParse(route);
    final fragment = uri?.fragment ?? '';
    final candidate =
        route.contains('verify-email') ||
        (uri?.hasQuery ?? false) ||
        fragment.contains('?');
    if (!candidate) return false;
    // Scrub synchronously before parsing, notifying widgets, or navigation.
    _source.scrub();
    revision++;
    _pending = parseVerificationToken(
      route,
      trustedOrigin: trustedOrigin,
      allowRoute: true,
    );
    _message = _pending == null
        ? invalidLink
        : 'Verification link ready. Sign in to the matching account, then explicitly confirm your email.';
    if (notify) notifyListeners();
    return true;
  }

  String? takePending() {
    final token = _pending;
    _pending = null;
    _message = null;
    return token;
  }

  void clear() {
    if (_disposed) return;
    _pending = null;
    _message = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = null;
    _message = null;
    _source.dispose();
    super.dispose();
  }
}
