import 'package:http/http.dart' as http;

// The native HTTP client does not maintain a cookie jar.
http.Client createAuthClient() => http.Client();
