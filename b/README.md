# BahirLedger backend

Java 21 / Spring Boot modular-monolith foundation. Flutter remains in the sibling ui directory.

## Current backend scope

- `GET /api/v1/health` returns `{"status":"UP"}` (process liveness only).
- All other HTTP requests are denied. No password login, generated development account, SSO, database, membership API or business endpoints exist yet.
- Internal `AccessPolicy` tests organization/project grants and configurable self-approval; it is NOT exposed as an API and does not implement role delegation, workflow validation or durable policy storage.
- [OpenAPI contract](src/main/resources/contracts/openapi.yaml) is committed, not served publicly.

## Build and run

Select a JDK 21 installation using `JAVA_HOME` (the system's shell default may be Java 17). Use the checked-in Maven wrapper; global Maven is unnecessary.

- Verify: `./mvnw verify` (Windows: `mvnw.cmd verify`).
- Run locally: `./mvnw spring-boot:run` (default port 8080).
- Alternatively run the packaged executable JAR after verification.
- VS Code tasks provide **Backend: verify** and **Backend: run**. Set the Java 21 environment before launching VS Code/tasks.
- Debug using a Java-enabled IDE's application launch with `BahirLedgerBackendApplication`; no remote debug listener is exposed by default.

Wrapper/build dependencies are downloaded on the first build. No credentials or running PostgreSQL instance are required for this increment. Do not disable security to experiment with future endpoints.

## Direction and next gates

PostgreSQL, REST/OpenAPI, explicit synchronization, OIDC federation (proposed MVP interoperability), S3-compatible evidence storage, and Python AI/derived analytics are architectural directions, not currently running infrastructure. Java retains all authoritative business transactions and access enforcement. Python owns AI-provider integration and derived processing when the first AI feature is implemented; OpenAI and concrete Python framework/broker choices are not selected. Provider selection, SSO onboarding/recovery, versioned policy administration and durable tenant isolation require subsequent reviewed increments.

Shared version-controlled specifications: [architecture](../architecture.md), [API design](../api-design.md), [AI/data ownership](../ai-analytics.md), [auth/access](../auth-access.md), [decisions](../decisions.md), and [product vision](../product-vision.md). The parent [README](../README.md) is the application entry point. Only the root `docs/` directory contains local-only development plans and progress. Do not place tokens, SSO secrets, or production data in this repository.