import 'package:flutter/foundation.dart';

/// An origin, not an arbitrary endpoint. Never include credentials in this URL.
class ApiConfig {
  ApiConfig(String value, {bool allowDevelopmentHttp = kDebugMode}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        value != value.trim() ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.port < 1 ||
        uri.port > 65535 ||
        !RegExp(r'^[a-zA-Z0-9.\-:\[\]]+$').hasMatch(uri.host)) {
      throw const FormatException('API_BASE_URL must be a valid API origin.');
    }
    final loopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.scheme != 'https' &&
        !(allowDevelopmentHttp && loopback && uri.scheme == 'http')) {
      throw const FormatException(
        'API_BASE_URL requires HTTPS (debug loopback HTTP only).',
      );
    }
    origin = uri.replace(path: '');
  }

  factory ApiConfig.fromEnvironment() => ApiConfig(
    const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );

  late final Uri origin;

  Uri endpoint(String path) => origin.resolve(path);
}
