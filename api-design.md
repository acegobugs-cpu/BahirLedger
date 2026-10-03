# API design and protocol decisions

Updated: 2026-10-03. The [backend OpenAPI contract](b/src/main/resources/contracts/openapi.yaml) defines the current public surface (0.4.0). The managed-auth and durable-onboarding sections below describe implemented operations; other resource/sync/evidence examples are future designs and need contract review before implementation.

## Implemented managed account authentication

| Operation | Contract |
| --- | --- |
| `GET /api/v1/health` | Public liveness: `200 {status:"UP"}`; not database/tenant readiness |
| `POST /api/v1/auth/register` | JSON `{email,displayName,password}` → `200 {accessToken,expiresAt,user:{id,email,displayName,emailVerified:false}}` after delivery acceptance; `409` duplicate, `503` delivery/database failure |
| `POST /api/v1/auth/login` | JSON `{email,password}` → `200 {accessToken,expiresAt,user:{id,email,displayName,emailVerified}}`; unverified accounts may sign in |
| `GET /api/v1/me` | Bearer authentication → `200 {id,email,displayName,emailVerified}`; no membership or grants |
| `POST /api/v1/auth/email-verification/confirm` | Same-account bearer and JSON `{token}` → `200 {id,email,displayName,emailVerified:true}`; `400` invalid/expired/replayed/rotated/wrong-account token |
| `POST /api/v1/auth/email-verification/resend` | Bearer, no body → `204` delivery accepted or already verified without mail; `429` cooldown/throttle, `503` delivery/database failure |
| `POST /api/v1/auth/logout` | Bearer authentication → `204`; revokes that session |

Java directly verifies BCrypt passwords (cost 12). The opaque token contains 32 random bytes encoded as base64url, not a JWT; `expiresAt` is absolute UTC, 30 minutes after issuance. Backend memory retains SHA-256 token digests with account ID/expiry and rechecks active accounts in JDBC. No refresh, sliding expiry, authentication server, OIDC or cookies/HTTP sessions. Backend restart invalidates sessions, not durable accounts.

`emailVerified` is a required boolean; new, migrated and locally provisioned accounts default to false, never implicitly verified. Pending sessions permit account/verification operations only. Flutter completes signup/sign-in after `/me` confirms the same account ID and uses its status to gate the verification/account page. Missing/malformed booleans fail closed; verification does not renew the bearer or grant tenant access.

Flutter keeps the bearer only in memory, sends it only as `Authorization: Bearer …`. Web Fetch uses `credentials: omit`, `cache: no-store` and rejects redirects; native also rejects redirects. Logout clears local state before attempting remote revocation; failures warn that the remote session may survive until expiry. Reload/restart signs out locally, not necessarily remotely. Requests time out after 15 seconds without automatic retry/token refresh.

Verification tokens are 32 random bytes encoded as exactly 43 base64url characters, persisted only as SHA-256 digests, single-use and strictly expire at 30 minutes. Confirmation requires the same active account's bearer and atomically consumes the digest/sets the flag under an account-row lock. Resend rotates the token with a durable 60-second cooldown, including delivery failures; failure clears the new token without restoring the old one. Separate five-minute budgets are confirm 10/account, 20/direct source, 100/global; resend 3/unverified account, 10/direct source, 30/global. These bounded rate maps are per-process, unlike the persisted cooldown; verified resend no-ops still count toward source budgets. Signup uses shared login/registration limits.

The private configuration template selects Gmail SMTP/587 with STARTTLS; disabled mode remains the unconfigured adapter fallback, and an explicitly local-only private file outbox is optional. Registration `200`/resend `204` means adapter acceptance, not inbox delivery; no durable worker, automatic retry or atomic SMTP/database transaction exists. Registration `503` can leave a pending account but allocates no session before accepted delivery; recover through login/resend, not repeated signup. Duplicate registration sends no mail; login sends no mail. See [direct-property delivery configuration](b/README.md#verification-delivery-setup).

Mail uses configured frontend origin plus `/#/verify-email?token=TOKEN`, never request-derived headers or an API token-query URL. Flutter captures the fragment ephemerally, replaces the current URL/history entry before parsing/navigation, and requires explicit confirmation after matching-account login. Native supports manual token/full trusted-link paste (full links require `FRONTEND_ORIGIN`), not OS universal/app-link registration. Scrubbing cannot remove pre-startup browser/provider records; never log or persist these tokens.

Login validation returns `400`; wrong email/password or inactive account returns the same generic `401` credentials error; bounded per-process throttling/concurrency/session capacity returns `429`. Authentication failures, forbidden operations, database failures and unexpected controller failures have sanitized `{code,message}` responses (`401`, `403`, `503`, `500` respectively). Auth/identity responses, including errors, use `Cache-Control: no-store`. See [backend details](b/README.md) for body/credential bounds and limits.

Only the exact auth and onboarding methods/routes documented here and allowed preflights are enabled. CORS permits one configured exact loopback HTTP(S) origin with port, never wildcard/credentialed access; the local default is `http://localhost:8765`, otherwise cross-origin access defaults off. CSRF exemptions apply only to the exact implemented auth and onboarding POST operations, not arbitrary writes or route subtrees. The verification frontend-link origin is separate configuration and does not expand CORS. Non-loopback browser deployment needs a reviewed CORS policy; the current configuration is not production web certification.

Account-only signup and verification are implemented alongside opt-in local provisioning and the separate onboarding surface below. **No password-recovery, MFA, SSO, general member administration, policy or project/financial endpoints exist**; the `/auth/signup` alias is also denied. Future business endpoints must require verified email, active membership and effective authorization. Optional SSO cannot email-auto-link identities. See [auth/access](auth-access.md).

## Implemented durable onboarding — 2026-10-03

All operations require an **active verified account bearer**; the existing bearer/deadline and `/me`/auth payloads are unchanged. `Context` below is `{membership,bootstrap}`, both keys always present and nullable. Membership is `{organizationId,organizationName,role}` (`OWNER` or `MEMBER`); pending bootstrap is `{id,name,expiresAt}`. Membership implies a null bootstrap, never project/policy/financial grants.

| Operation | Input → success |
| --- | --- |
| `GET /api/v1/onboarding` | `200 Context`; resume durable setup or read active membership |
| `POST /api/v1/onboarding/bootstrap` | `{name}` → `200 Context`; stripped nonblank single-line name, max 120 characters; backend rejects embedded ASCII controls |
| `POST /api/v1/onboarding/bootstrap/activate` | `{bootstrapId}` → `200 Context`; atomic organization + `OWNER` + audits |
| `POST /api/v1/onboarding/bootstrap/cancel` | `{bootstrapId}` → `204` |
| `GET /api/v1/organization/invitations` | `200 {invitations:[{id,email,status,expiresAt}]}`; owner-only latest 100 |
| `POST /api/v1/organization/invitations` | `{email}` → `201 {invitation:{id,email,status,expiresAt},token}`; owner-only, normalized email max 254, no role choice |
| `POST /api/v1/organization/invitations/{id}/revoke` | Empty body → `204`; owner-only, canonical UUID-shaped path |
| `POST /api/v1/onboarding/invitations/preview` | `{token}` → `200 {organizationName,expiresAt}`; no writes, reservation or grants |
| `POST /api/v1/onboarding/invitations/accept` | `{token}` → `200 Context`; atomic `MEMBER` + consumption + pending cancellation + audits |

Pending bootstrap is account-scoped restricted state, not a separate bearer grant: fixed **24-hour** expiry; editing retains ID/deadline; no organization exists before activation. Cancel/expiry permits a new ID/lifetime. Expired setup is hidden lazily. Successful activation ID retries return current active membership even after the old pending deadline; stale/cancelled/expired unactivated IDs fail. One org/account includes suspended/revoked membership, preventing silent switching. Durable active account/membership/organization checks and account → organization → invitation locks precede authority-dependent changes; audit failure rolls back every mutation.

Invitations are **owner-shared codes, no invitation email or URL**: 32 random bytes / 43 base64url characters, SHA-256-digest-only storage, one-time raw return, strict **seven-day** expiry. Exact normalized verified recipient email **and** secret are required. `PENDING`, `ACCEPTED`, `REVOKED`, projected `EXPIRED` statuses are returned without tokens/digests in lists. Invalid/expired/revoked/replayed/wrong-recipient/inactive-target codes share `400 invalid_invitation`; malformed/missing JSON, unsupported media type and oversized bodies use `400 invalid_request`. Preview reserves nothing. Acceptance replay fails; recover lost success through GET. Issue retry creates another invite and consumes budget; lost raw codes cannot be recovered. Already-revoked revoke is `204`; accepted revoke is `409 invitation_unavailable`; unknown/cross-org revoke is the same `404 invitation_not_found`.

Bearer failure is `401`; unverified access is `403 email_verification_required`; inactive org/membership is `403 organization_unavailable`; non-owner admin is forbidden. Existing membership is `409 membership_exists`; unavailable bootstrap is `409 bootstrap_unavailable`. Tenant budget/capacity failures use **`429 rate_limited`**, not auth's unchanged `too_many_requests`. Error bodies remain generic `{code,message}`; sensitive successes/errors are `Cache-Control: no-store`.

Mutation/preview JSON bodies are limited to **4096 bytes**, including chunked requests. Exact POST-only CSRF exemptions/CORS entries include the UUID-shaped revoke route, never a subtree. Shared fixed five-minute tenant budgets: **20/account, 80/direct source, 200/global, 10,000 keys maximum** per process; forwarded headers ignored, no distributed throttle or `Retry-After` guarantee. Durable caps: **100 nonexpired open/org**, **10 issued/owner per rolling 24 hours**, unaffected by revocation; lists return latest **100**, creation then UUID descending. `OWNER` invitation administration and `MEMBER` membership are slice decisions, not universal role policy. No destructive member/owner admin, custom policy or business API is added.

Parent final full-JDK-21 Maven `test`: **137 passed, zero failures/errors/skips**, after the backend name-validation fix above. Independently, the same **15 `OnboardingStateTest` tests passed on disposable real PostgreSQL 16**, with isolated per-test schemas covering clean V1–V3 migration, concurrency, audit rollback, expiry and digest/recipient binding. H2 additive upgrade/reopen also passed. HTTP/security/contract coverage is from the regular H2 suite, **not PostgreSQL-backed HTTP tests**. See [test-only opt-in and evidence limits](b/README.md#onboarding-validation--2026-10-03).

**326 Flutter tests, clean analyzer and release web build** remain implementation-agent results, not parent reruns. This docs-only pass reran no runtime checks. The disposable PostgreSQL instance is stopped; user database/private configuration/services were untouched. No PostgreSQL existing-database upgrade, PostgreSQL-backed browser/SMTP validation or server restart is claimed. The shared browser tab is the stale old implementation, not new live UI evidence. Live browser onboarding, full interactive verification, SMTP/inbox, native-device and production gates remain open.

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
