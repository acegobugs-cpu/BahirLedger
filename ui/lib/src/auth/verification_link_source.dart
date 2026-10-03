/// Small platform seam: URL values must never be logged or persisted by callers.
abstract class VerificationLinkSource {
  Uri? get trustedOrigin;
  String? get currentUrl;
  void scrub();
  void listen(void Function() onChange);
  void dispose();
}
