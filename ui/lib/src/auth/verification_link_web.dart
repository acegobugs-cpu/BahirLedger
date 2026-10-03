import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'verification_link_source.dart';

VerificationLinkSource createVerificationLinkSource() => _WebSource();

class _WebSource implements VerificationLinkSource {
  JSFunction? _listener;

  @override
  Uri get trustedOrigin => Uri.parse(web.window.location.origin);
  @override
  String get currentUrl => web.window.location.href;

  @override
  void scrub() {
    // Replace, never push: Back must not restore the secret-bearing entry.
    // Drop history.state as well; do not copy a framework route containing it.
    web.window.history.replaceState(null, '', '/#/');
  }

  @override
  void listen(void Function() onChange) {
    _listener = ((web.Event _) => onChange()).toJS;
    web.window.addEventListener('hashchange', _listener);
    web.window.addEventListener('popstate', _listener);
  }

  @override
  void dispose() {
    web.window.removeEventListener('hashchange', _listener);
    web.window.removeEventListener('popstate', _listener);
    _listener = null;
  }
}
