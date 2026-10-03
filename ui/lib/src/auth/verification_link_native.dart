import 'api_config.dart';
import 'verification_link_source.dart';

VerificationLinkSource createVerificationLinkSource() => _NativeSource();

class _NativeSource implements VerificationLinkSource {
  @override
  Uri? get trustedOrigin {
    const value = String.fromEnvironment('FRONTEND_ORIGIN');
    if (value.isEmpty) return null;
    try {
      return ApiConfig(value).origin;
    } on FormatException {
      return null;
    }
  }

  @override
  String? get currentUrl => null;
  @override
  void scrub() {}
  @override
  void listen(void Function() onChange) {}
  @override
  void dispose() {}
}
