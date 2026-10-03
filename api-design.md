# API design and protocol decisions

Updated: 2026-10-03. The [backend OpenAPI contract](b/src/main/resources/contracts/openapi.yaml) defines the current public surface. The managed-auth section below describes implemented operations; other resource/sync/evidence examples are future designs and need contract review before implementation.

## Implemented managed account authentication

| Operation | Contract |
| --- | --- |
| `GET /api/v1/health` | Public liveness: `200 {status:"UP"}`; not database/tenant readiness |
| `POST /api/v1/auth/login` | JSON `{email,password}` → `200 {accessToken,expiresAt,user:{id,email,displayName}}` |
| `GET /api/v1/me` | Bearer authentication → `200 {id,email,displayName}`; no membership or grants |
| `POST /api/v1/auth/logout` | Bearer authentication → `204`; revokes that session |

Java directly verifies BCrypt passwords (cost 12). The opaque token contains 32 random bytes encoded as base64url, not a JWT; `expiresAt` is absolute UTC, 30 minutes after issuance. Backend memory retains SHA-256 token digests with account ID/expiry and rechecks active accounts in JDBC. No refresh, sliding expiry, authentication server, OIDC or cookies/HTTP sessions. Backend restart invalidates sessions, not durable accounts.

Flutter keeps the token only in memory, sends it only as `Authorization: Bearer …`, and completes sign-in only after `/me` confirms the same account ID. Web Fetch uses `credentials: omit`, `cache: no-store` and rejects redirects; native also rejects redirects. Logout clears local state before attempting remote revocation; failures warn that the remote session may survive until expiry. Reload/restart signs out locally, not necessarily remotely. Requests time out after 15 seconds without automatic retry/refresh.

Login validation returns `400`; wrong email/password or inactive account returns the same generic `401` credentials error; bounded per-process throttling/concurrency/session capacity returns `429`. Authentication failures, forbidden operations, database failures and unexpected controller failures have sanitized `{code,message}` responses (`401`, `403`, `503`, `500` respectively). Auth/identity responses, including errors, use `Cache-Control: no-store`. See [backend details](b/README.md) for body/credential bounds and limits.

Only these exact methods/routes and allowed preflights are enabled. CORS permits one configured exact loopback HTTP(S) origin with port, never wildcard/credentialed access; the local default is `http://localhost:8765`, otherwise cross-origin access defaults off. CSRF exemptions apply only to POST login/logout, not arbitrary writes. Non-loopback browser deployment needs a reviewed CORS policy; the current configuration is not production web certification.

Current account provisioning is opt-in and local-profile-only; **no signup, email-verification, invitation, organization/member, password-recovery or business endpoints exist**. Managed signup with verified email is planned as the default; optional SSO is separate future work and cannot email-auto-link identities. Account authentication never implies tenant access. See [auth/access](auth-access.md).

## Protocol selection

| Interface | Choice and purpose |
| --- | --- |
| Flutter to Java | Versioned REST over HTTPS with JSON; OpenAPI is the checked-in contract |
| Offline synchronization | Explicit REST push/pull protocol, not generic CRUD replay |
| Evidence transfer | Authorized short-lived object-storage upload/download URLs; metadata and finalize operations through Java |
| Java to Python background work | Durable, versioned job/result messages; no mandatory HTTP server for a worker |
| Interactive Python AI, if needed | Internal authenticated HTTP API (FastAPI is a candidate), described by OpenAPI; Java remains the user-facing access boundary |
| Foreground notifications | Optional future SSE for one-way updates; notifications trigger authorized refresh, not durable synchronization |
| Background mobile notifications | Platform push services; no assumption of a permanently connected socket |
| WebSockets | Deferred until continuous bidirectional communication is required |
| GraphQL | Deferred; current needs do not justify an additional query/authorization/sync surface |
| gRPC | Deferred; consider only for demonstrated internal-service needs |

OpenAPI client generation can provide typed Dart clients, but generated types do not replace server validation. Do not introduce an API gateway in another language without a concrete need.

## Resource queries and explicit commands

Use resource queries for authorized project/member/budget views. Model significant business transitions as explicit commands instead of accepting unrestricted state changes. Illustrative operations: `POST /api/v1/projects`, `GET /api/v1/projects/{projectId}`, and project-specific `submit`, `approve`, or `request-amendment` commands. Their permitted workflow is organization/project policy, not a universal management methodology.

A command may carry an `Idempotency-Key`, an `expectedVersion`, and a reason/evidence reference as required by the applicable policy. Java checks identity, membership, tenant/project ownership, permissions, workflow and concurrency before committing the mutation and audit event together.

Scope deduplication to the caller/tenant and operation semantics; reject reuse of a key with a different payload. Define retry behavior, retention and response replay explicitly. Recheck access before returning any retained response. Client retries must not double-charge, double-approve or duplicate events.

Define consistent validation/error shapes, pagination, version compatibility and date/money representation in each contract. Use explicit currency and reviewed decimal representation; do not silently transport money through imprecise binary floating-point arithmetic. A proposed endpoint is not implemented until its contract, authorization and tests agree.

## Offline push/pull

Illustrative routes: `POST /api/v1/sync/push` and `GET /api/v1/sync/pull?cursor=<opaque-cursor>`.

- Stable entity IDs and client-generated operation IDs; durable deduplication under retries.
- Expected entity versions and explicit conflict outcomes; never silent last-write-wins for approvals, payments or financial corrections.
- Per-operation accepted/rejected/conflict results; specify partial-batch semantics and transaction boundaries.
- Server-issued scoped cursors, pagination, deletion markers and a resynchronization path for expired cursors.
- No cursor may reveal another tenant's/project's data. Permission changes must invalidate or constrain downloads and explain pending-work outcomes.
- Server ordering must not depend on a device's clock. Account for late commits and concurrent changes in the cursor design so records cannot be skipped.
- Revalidate current authorization, policy and request version on receipt. An offline decision is a proposal until accepted; show local/pending/accepted/needs-attention states distinctly.

See [offline access and unresolved defaults](auth-access.md#offline-access-proposals-not-accepted-defaults). A realtime notification stream is not a replacement for this durable recovery protocol.

## Evidence APIs

Java authorizes object operations and issues narrowly scoped short-lived URLs. Keep buckets private; object keys are identifiers, not permissions. Finalize uploads only after validating ownership, expected metadata, size/type and integrity requirements. Plan malware/content handling, expiry, interrupted uploads and abandoned-object cleanup before release. Python receives access only to objects required by an authorized analysis job.

## Trust boundaries

Service authentication is required for Java/Python integration; a tenant ID in a payload alone grants nothing. Provider API keys stay server-side. Tenant scope, purpose and permitted data accompany a job and are verified at retrieval and result acceptance. See [ai-analytics.md](ai-analytics.md) for result ownership and failure handling.