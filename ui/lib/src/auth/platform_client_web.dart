import 'dart:async';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createAuthClient() => CookieFreeBrowserClient();

/// BrowserClient defaults to same-origin cookies, not credentials: omit.
/// Keep the package:http interface, but omit cookies even for same-origin APIs.
class CookieFreeBrowserClient extends http.BaseClient {
  final _active = <web.AbortController>{};
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed.');
    final abort = web.AbortController();
    _active.add(abort);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(abortTrigger.then((_) => abort.abort()));
    }
    try {
      final body = await request.finalize().toBytes();
      final response = await web.window
          .fetch(
            request.url.toString().toJS,
            web.RequestInit(
              method: request.method,
              headers: request.headers.jsify()! as web.HeadersInit,
              body: body.isEmpty ? null : body.toJS,
              credentials: 'omit',
              redirect: 'error',
              cache: 'no-store',
              signal: abort.signal,
            ),
          )
          .toDart;
      final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
      return http.StreamedResponse(
        Stream.value(bytes),
        response.status,
        request: request,
      );
    } catch (_) {
      // Never propagate browser diagnostics that might include request details.
      throw http.ClientException('Request failed.');
    } finally {
      _active.remove(abort);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _active) {
      abort.abort();
    }
    _active.clear();
    super.close();
  }
}
