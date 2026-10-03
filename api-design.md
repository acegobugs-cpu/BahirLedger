# API design and protocol decisions

Updated: 2026-10-03. Approved direction, not implemented endpoint inventory. The [backend OpenAPI contract](b/src/main/resources/contracts/openapi.yaml) defines the current public surface; examples below are future designs and need contract review before implementation.

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