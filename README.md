# BahirLedger

A Flutter application and Java backend for project management and accountability: projects, approvals, funds, evidence, and attributable history. Organizations configure their own project policies within tenant-isolation and security boundaries.

## Current application

- **Flutter prototype:** project list, create/edit forms, review screens, preparation checklist, and funding/budget/RACI/milestone/procurement editors. Data is currently page-local and in memory; some changes do not survive navigation or restart.
- **Java backend foundation:** a public liveness endpoint, fail-closed HTTP security, an internal organization/project policy evaluator, and a static OpenAPI contract. It is not yet connected to Flutter.
- **Planned, not operational:** PostgreSQL persistence, organization SSO and membership, full policy administration, offline synchronization, private evidence storage, and Python AI/analytics processing. This is not production-ready authentication or financial software.

## Repository

| Location | Purpose |
| --- | --- |
| [ui/README.md](ui/README.md) | Flutter client and platform scaffolds |
| [b/README.md](b/README.md) | Java/Spring Boot backend, build and run details |
| Root Markdown documents below | Shared, version-controlled product and technical documentation |

## Getting started

### Flutter client

Install Flutter with Dart compatible with `^3.11.5` and the build prerequisites for your chosen target. The development baseline used Flutter 3.41.9 / Dart 3.11.5; see [ui/pubspec.yaml](ui/pubspec.yaml).

From the repository root, use `cd ui`, then `flutter pub get` and `flutter run -d <device-id>`. Discover available targets with `flutter devices`. Platform scaffolding does not mean every release target is certified.

The client currently uses local sample data; a running backend or SSO account is not required to explore the prototype.

### Backend

Install a **full JDK 21** and select it with `JAVA_HOME`; a Java runtime alone is insufficient. From the repository root, use `cd b`, then `./mvnw verify` and `./mvnw spring-boot:run`. On Windows use `mvnw.cmd`.

Default local endpoint: `http://localhost:8080/api/v1/health`, returning `{"status":"UP"}`. This indicates process liveness, not database or SSO readiness. Other requests are denied in the foundation. First build downloads Maven/dependencies; no database or credentials are required yet.

See [b/README.md](b/README.md) for configuration and debugging, and [the API contract](b/src/main/resources/contracts/openapi.yaml) for implemented operations.

## Checks

- From the Flutter directory: `flutter test` and `flutter analyze --no-pub`.
- From the backend directory: `./mvnw verify` (full JDK 21 required).
- For whitespace: `git diff --check` from the repository root.

Do not commit credentials, identity-provider secrets, signing keys, or production data. No model-provider API key belongs in Flutter.

## Documentation

| Document | Category |
| --- | --- |
| [product-vision.md](product-vision.md) | Product goals, domain examples, scope, principles, and engineering challenges |
| [architecture.md](architecture.md) | System structure, ownership, storage, and integration boundaries |
| [api-design.md](api-design.md) | REST/OpenAPI, synchronization, files, realtime, and deferred protocols |
| [auth-access.md](auth-access.md) | Organizations, SSO, invitations, configurable permissions, and offline access |
| [ai-analytics.md](ai-analytics.md) | Python AI processing, Java authority, job contracts, and data safety |
| [decisions.md](decisions.md) | Accepted decisions, rationale, and unresolved choices |

Root technical/product documents are intended for version control. The root `docs/` directory is reserved for **local, Git-ignored development plans, context, progress, and review history**; it is not required by a fresh clone. No commit is created automatically.