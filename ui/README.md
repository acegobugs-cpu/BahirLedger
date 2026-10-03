# BahirLedger Flutter client

Flutter project/accountability prototype: project list/create/edit/detail, review history and preparation editors. Current state is in memory, with known cross-route data-loss gaps. Production authentication, durable offline storage, backend integration and synchronization are not implemented in the verified UI baseline.

## Development setup and checks

The recorded development toolchain is Flutter 3.41.9 / Dart 3.11.5; see [pubspec.yaml](pubspec.yaml) and [tests](test/widget_test.dart). Install dependencies with `flutter pub get`, discover targets with `flutter devices`, and launch with `flutter run -d <device-id>`. Previous test results and pending human smoke checks are kept in local development records rather than presented as newly verified results here.

Run UI checks from this directory: `flutter analyze --no-pub` and `flutter test`; use targeted tests for the changed slice. Generated platform folders are not release-support certification.

## Backend and access direction

The [backend build definition](../b/pom.xml) establishes Java 21 / Spring Boot; approved direction is PostgreSQL modular monolith, REST/JSON/OpenAPI, explicit push/pull sync, S3-compatible evidence and Python-owned AI processing/derived analytics. Java owns business authority; AI remains planned, with no provider selected. See the [root overview](../README.md) for current scope, [architecture](../architecture.md), [API design](../api-design.md), and [AI ownership](../ai-analytics.md). The current backend is a scaffold/health/fail-closed/internal-policy foundation, not full authentication.

An org is an independent workspace/tenant, not a legal entity. One org per application account, invite-only membership, self-service org creation with restricted bootstrap, mandatory org SSO and personal devices only. Provider is not selected; OIDC proposed. Flutter sign-in will use external-browser auth code + PKCE, no app secret. Pending bootstrap cannot access tenant data before provider-control verification and successful test sign-in.

Authority is configurable by org/project, including self-approval, scoped grants and delegated role/approval administration bounded by mandatory rules. Role templates are optional. [Old review decisions](docs/dec/decisions.md) and [workflow sketches](docs/workflow/1_projectWorkFlow.md) are historical prototype examples, not universal policy.

Offline timings and online-by-default approvals remain proposals. No authoritative offline approvals or instant disconnected revocation; pending work must be retained encrypted for later reconciliation. The current prototype does not implement those protections.

Shared decisions and specifications are version-controlled at the root: [decisions](../decisions.md) and [auth/access](../auth-access.md). Local implementation context, review records and development plans belong only under the repository-root ignored `docs/` directory, not this source tree. Historical UI screen numbers are examples, not current development roadmap numbers; numbering history is preserved in local plans.
