import 'package:http/http.dart' as http;

import 'platform_client_native.dart'
    if (dart.library.js_interop) 'platform_client_web.dart'
    as platform;

http.Client createAuthClient() => platform.createAuthClient();
