# BahirLedger

A Flutter application and Java backend for project management and accountability: projects, approvals, funds, evidence, and attributable history. Organizations configure their own project policies within tenant-isolation and security boundaries.

## Current application

- **Managed signup/sign-in and email verification:** Flutter integrates Java's account-only registration, login, identity, verification and logout endpoints. Unverified accounts see a verification gate; verified accounts see identity only, not organization membership or an authorized project workspace. Bearer tokens remain in client memory only and expire after at most 30 minutes.
- **Separate local demo:** project list, create/edit forms, review screens, preparation checklist, and funding/budget/RACI/milestone/procurement editors remain sample-data prototypes. Some changes do not survive navigation or restart; exploring the demo grants no tenant access.
- **Backend:** BCrypt password hashes, JDBC account storage with Flyway migrations, opaque bearer sessions held as digests in backend memory, fail-closed HTTP security, an internal policy evaluator and a static OpenAPI contract. The explicit local profile uses file-backed H2 outside the repository. PostgreSQL is the deployment target, not a live-tested deployment.
- **Verification boundary:** New, migrated and locally provisioned accounts default to `emailVerified=false`. Login permits account/verification operations only; verification never grants tenant access. Single-use 30-minute verification tokens are persisted as SHA-256 digests; resend rotates them with a durable 60-second cooldown and rate limits. Confirmation requires a current bearer for the same account.
- **Accepted direction, still planned:** Controlled organization bootstrap, invitations, tenant membership, password recovery/change, MFA, optional organization SSO, full policy administration, offline synchronization, private evidence and Python AI/analytics remain future work. This is not production-ready authentication or financial software.

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

Choose **Explore demo (local sample data)** to explore without a backend or account. For managed signup/sign-in, complete the [backend private-properties setup](b/README.md#private-properties-workflow), run the backend separately and register through the UI; legacy provisioning is not needed. Set `API_BASE_URL` to the API origin; its default is `http://localhost:8080`. HTTP is allowed only for exact loopback hosts in debug builds; profile/release requires HTTPS. For web development use a fixed frontend port matching both backend origins (template: `http://localhost:8765`). See [ui/README.md](ui/README.md) for platform and transport limits.

Web verification links use a frontend fragment, held only in memory and scrubbed from the current URL/history entry before UI handling; confirmation is explicit after same-account sign-in. Native supports manual token paste, or full-link paste with configured `FRONTEND_ORIGIN`, not OS universal/app links. Scrubbing cannot erase records created before app startup.

### Backend

Use a **full JDK 21**; a Java runtime alone is insufficient. From the backend directory run `./mvnw verify` (Windows: `mvnw.cmd verify`). Dedicated test-only configuration keeps tests independent of private database/SMTP values.

All backend runtime settings belong in private, ignored/untracked [b/src/main/resources/application.properties](b/src/main/resources/application.properties). **Preserve an existing file and its database values.** Only if it is absent, copy [b/src/main/resources/application.properties.example](b/src/main/resources/application.properties.example) beside it using the editor, then fill private values. The template has blank database/SMTP credentials, Gmail port 587 with STARTTLS, both origins at `http://localhost:8765`, and explicit loopback HTTP permission. The existing private sender is filled; enter the remaining Google app password in `bahirledger.mail.smtp.password` **in the editor, never in chat**.

After credentials are filled and the configured PostgreSQL service is available, normal `./mvnw spring-boot:run` works without a launcher or environment setup. The existing local environment file is untouched and not loaded; canonical `bahirledger.database.*` properties are read directly. No automatic restart is performed. The optional `local` profile explicitly selects external file-backed H2 instead of PostgreSQL and inherits private CORS/mail settings; it is not needed for Gmail or UI registration. Accounts survive restart; bearer sessions do not.

`GET /api/v1/health` returns `{"status":"UP"}` for liveness, not tenant or deployment readiness. Only health/register/login and authenticated identity/verification/logout operations, plus permitted preflights, are enabled; everything else is denied.

The template selects **SMTP**; disabled mode remains a fallback that returns `503` for registration/pending resend, not simulated success. The exclusively `local` profile can optionally use a private file outbox, which does not send to an inbox. Adapter/relay acceptance is **not guaranteed inbox delivery**; there is no durable mail worker or automatic retry. Signup failure can leave a pending account without a session: sign in, then resend after cooldown. See [delivery setup and limits](b/README.md#verification-delivery-setup).

See [b/README.md](b/README.md) for configuration and debugging, and [the API contract](b/src/main/resources/contracts/openapi.yaml) for implemented operations.

## Checks

- From the Flutter directory: `flutter test` and `flutter analyze --no-pub`.
- From the backend directory: `./mvnw verify` (full JDK 21 required).
- For whitespace: `git diff --check` from the repository root.

Do not commit credentials, identity-provider secrets, signing keys, or production data. No model-provider API key belongs in Flutter.

Ignoring/untracking private configuration does **not** erase previous commits: rotate any real credentials previously committed. Maven build output and packaged JARs include private resource configuration; **do not publish artifacts containing secrets**. See [backend secret hygiene](b/README.md#private-properties-workflow).

## Documentation

| Document | Category |
| --- | --- |
| [product-vision.md](product-vision.md) | Product goals, domain examples, scope, principles, and engineering challenges |
| [architecture.md](architecture.md) | System structure, ownership, storage, and integration boundaries |
| [api-design.md](api-design.md) | REST/OpenAPI, synchronization, files, realtime, and deferred protocols |
| [auth-access.md](auth-access.md) | Managed identity, optional SSO, invitations, configurable permissions, and offline access |
| [ai-analytics.md](ai-analytics.md) | Python AI processing, Java authority, job contracts, and data safety |
| [decisions.md](decisions.md) | Accepted decisions, rationale, and unresolved choices |

Root technical/product documents are intended for version control. The root `docs/` directory is reserved for **local, Git-ignored development plans, context, progress, and review history**; it is not required by a fresh clone. No commit is created automatically.
