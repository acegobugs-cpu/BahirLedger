# BahirLedger Flutter client

Flutter client with managed email/password sign-in and a separate, explicitly labeled local project/accountability demo. The authenticated landing page shows account identity only: it does not treat demo projects as an authorized tenant workspace. Durable offline storage, tenant membership, project APIs and synchronization are not implemented.

## Managed sign-in setup

- Install dependencies with `flutter pub get`. Supply the API **origin** at build/run time using `--dart-define=API_BASE_URL=https://api.example.com` (no path, query, fragment or embedded credentials).
- The default is `http://localhost:8080` for local development. HTTP is permitted **only in debug builds**, and only for exact `localhost`, `127.0.0.1`, or `[::1]` loopback hosts. Profile/release builds require HTTPS, including for loopback. Invalid configuration shows a safe configuration screen instead of sending credentials. Do not use cleartext LAN or production origins.
- A backend with the managed-login contract must be running separately, and an account must already be provisioned. There is no registration, invitation, password-reset or organization-enrollment endpoint in this client. Provisioning/invitations are future work, not clickable placeholders.
- For web development, use a fixed Flutter web port and have the backend allow that exact frontend origin in CORS. Preflights must allow `Content-Type` and `Authorization` for the login, me and logout endpoints. Cookie credentials are not needed. An HTTPS page needs an HTTPS API to avoid mixed-content restrictions. CORS/network failures are intentionally shown as generic connectivity errors.
- Native Android internet permission and macOS outgoing-network entitlements are included. Android emulator `localhost` refers to the emulator, not the host: use development port forwarding or a trusted HTTPS endpoint rather than weakening the URL policy for `10.0.2.2`. Platform transport-security rules still apply; no broad Android cleartext or Apple ATS exception has been added. If debug loopback HTTP is blocked by the target platform, use trusted HTTPS (or a narrowly scoped, debug-only platform exception). Platform folders are not release certification.

## Session and HTTP contract

- `POST /api/v1/auth/login` sends JSON `{email,password}`; email is trimmed, password is not. A successful response must contain `accessToken`, an absolute UTC ISO `expiresAt`, and `user: {id,email,displayName}` with nonempty string fields.
- Sign-in completes only after `GET /api/v1/me` succeeds with `Authorization: Bearer …`. Its user object must have the same ID as the login response; the landing page displays the `/me` identity.
- `401` login errors use the generic “Email or password is incorrect.” message. `400`, `429`, other HTTP errors, malformed responses, network errors and timeouts have fixed safe messages; response bodies and transport exception details are never shown or logged. No automatic retry or refresh is performed.
- `POST /api/v1/auth/logout` uses the bearer token and expects `204`. Local identity and token are cleared **before** waiting for the server. Failures/timeouts warn that remote revocation was not confirmed. Each HTTP exchange has a 15-second timeout and redirects are rejected, including on native platforms.
- `SessionController` is a root-injected `ChangeNotifier`. `BahirLedgerApp` owns and disposes its session, including an injected session; callers should not share it with another root. `AuthTransport` similarly owns its injected HTTP client. Tests can inject `MockClient` and a matching clock into both session and transport. The `demoBuilder` is independently injectable.
- The token is private to `AuthTransport`, **in memory only on every platform**. There are no cookies, localStorage, sessionStorage, preferences, disk/keychain token storage or session restoration. The web adapter implements `package:http`'s client interface using Fetch with `credentials: omit` (the standard BrowserClient otherwise permits same-origin cookies), `cache: no-store`, and redirect rejection. Native uses `package:http` without a cookie jar.
- Expiry is absolute, at the server deadline and never later than 30 minutes from the login attempt. A timer and application-resume check clear local state; activity does not extend it. Restart/web reload signs out locally. Closing the app is **not** confirmed remote revocation; the server session can remain until expiry. Aborted/timed-out login or failed `/me` can likewise leave a server session until its deadline, even though no local authenticated state survives. Managed Dart strings cannot be securely zeroized, but the password controller is cleared immediately after a valid submit and again on disposal.
- “Explore demo (local sample data)” is the only normal application route into `Shell`/`ProjectsPage`. Its disclaimer remains visible on nested sample screens. Demo edits remain local prototype data and convey no membership, permissions or backend project access. Existing direct `Shell` tests remain supported.

## Frontend checks

Run `flutter test` for the full suite and `flutter analyze --no-pub` for static analysis. Auth tests cover request payloads/headers, login followed by `/me`, sanitized failures, invalid responses, token clearing, absolute expiry, disposal and request races; widget tests cover validation, loading, success/signout, remote-revocation warnings, responsive layouts and demo navigation. `flutter build web --no-pub --dart-define=API_BASE_URL=https://api.example.com` checks web compilation without starting an application/backend server. These are mocked tests, not a live backend or platform release smoke test.

## Development setup and checks

The recorded development toolchain is Flutter 3.41.9 / Dart 3.11.5; see [pubspec.yaml](pubspec.yaml) and [tests](test/widget_test.dart). Install dependencies with `flutter pub get`, discover targets with `flutter devices`, and launch with `flutter run -d <device-id>`. Previous test results and pending human smoke checks are kept in local development records rather than presented as newly verified results here.

Run UI checks from this directory: `flutter analyze --no-pub` and `flutter test`; use targeted tests for the changed slice. Generated platform folders are not release-support certification.

## Backend and access direction

The [backend build definition](../b/pom.xml) establishes Java 21 / Spring Boot; approved direction is PostgreSQL modular monolith, REST/JSON/OpenAPI, explicit push/pull sync, S3-compatible evidence and Python-owned AI processing/derived analytics. Java owns business authority; AI remains planned, with no provider selected. See the [root overview](../README.md) for current scope, [architecture](../architecture.md), [API design](../api-design.md), and [AI ownership](../ai-analytics.md). This frontend integrates only the managed account-authentication contract described above.

An org is an independent workspace/tenant, not a legal entity. The broader proposed org/SSO direction remains separate from the current local-account sign-in: invite-only membership, restricted org bootstrap, and external-browser OIDC/PKCE are not implemented here. No org/member endpoint is called or inferred from successful login, and no tenant authorization is claimed.

Authority is configurable by org/project, including self-approval, scoped grants and delegated role/approval administration bounded by mandatory rules. Role templates are optional. [Old review decisions](docs/dec/decisions.md) and [workflow sketches](docs/workflow/1_projectWorkFlow.md) are historical prototype examples, not universal policy.

Offline timings and online-by-default approvals remain proposals. No authoritative offline approvals or instant disconnected revocation; pending work must be retained encrypted for later reconciliation. The current prototype does not implement those protections.

Shared decisions and specifications are version-controlled at the root: [decisions](../decisions.md) and [auth/access](../auth-access.md). Local implementation context, review records and development plans belong only under the repository-root ignored `docs/` directory, not this source tree. Historical UI screen numbers are examples, not current development roadmap numbers; numbering history is preserved in local plans.
