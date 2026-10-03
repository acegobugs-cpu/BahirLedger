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

Choose **Explore demo (local sample data)** to explore without a backend or account. For managed signup/sign-in, run the backend separately; configure verification delivery or optionally provision a local development account as described in [b/README.md](b/README.md). Provisioning does not verify email. Set `API_BASE_URL` to the API origin; its default is `http://localhost:8080`. HTTP is allowed only for exact loopback hosts in debug builds; profile/release requires HTTPS. For web development use a fixed frontend port matching the backend's exact CORS origin (local default `http://localhost:8765`). See [ui/README.md](ui/README.md) for platform and transport limits.

Web verification links use a frontend fragment, held only in memory and scrubbed from the current URL/history entry before UI handling; confirmation is explicit after same-account sign-in. Native supports manual token paste, or full-link paste with configured `FRONTEND_ORIGIN`, not OS universal/app links. Scrubbing cannot erase records created before app startup.

### Backend

Install a **full JDK 21** and select it with `JAVA_HOME`; a Java runtime alone is insufficient. From the repository root, use `cd b`, then `./mvnw verify`. On Windows use `mvnw.cmd`. Tests supply their own database; application startup requires explicit database/profile configuration.

For local development only, enable `SPRING_PROFILES_ACTIVE=local` when running `./mvnw spring-boot:run`. Account creation is opt-in via all three variables `BAHIRLEDGER_DEV_EMAIL`, `BAHIRLEDGER_DEV_PASSWORD` and `BAHIRLEDGER_DEV_NAME`; there are no default application credentials. Follow the secure provisioning instructions in [b/README.md](b/README.md), not shell-history password literals. Existing accounts are never overwritten. H2 account data defaults to the user's external local-data directory and survives backend restart; sessions do not.

Without the local profile, PostgreSQL URL, username and password configuration are required; review/externalize machine-local settings and use deployment secrets. `GET /api/v1/health` returns `{"status":"UP"}` for liveness, not tenant or deployment readiness. Only health/register/login and authenticated identity/verification/logout operations, plus permitted preflights, are enabled; everything else is denied.

Verification delivery defaults to **disabled**: registration and pending-account resend return `503`, not simulated success. Configure `BAHIRLEDGER_MAIL_MODE=smtp` and the frontend origin/SMTP settings for real mail, or explicitly choose the private external file outbox under the exclusively `local` profile. The outbox does not send to an inbox. Adapter/relay acceptance is **not guaranteed inbox delivery**; there is no durable mail worker or automatic retry. Signup failure can leave a pending account without a session: sign in, then resend after cooldown. See [delivery setup and limits](b/README.md#verification-delivery-setup).

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
| [auth-access.md](auth-access.md) | Managed identity, optional SSO, invitations, configurable permissions, and offline access |
| [ai-analytics.md](ai-analytics.md) | Python AI processing, Java authority, job contracts, and data safety |
| [decisions.md](decisions.md) | Accepted decisions, rationale, and unresolved choices |

Root technical/product documents are intended for version control. The root `docs/` directory is reserved for **local, Git-ignored development plans, context, progress, and review history**; it is not required by a fresh clone. No commit is created automatically.
