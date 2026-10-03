# AI processing and analytical data ownership

Updated: 2026-10-03. Agreed direction: **Java owns business authority; Python owns AI processing and derived analytics.** Implement the Python component with the first concrete AI feature, not as a dependency of the initial backend. No AI provider, SDK, model or worker is implemented/selected by this document. OpenAI is a candidate, not a committed vendor.

## Responsibilities

| Java / Spring Boot | Python AI / analytics |
| --- | --- |
| Identity/membership and authorization enforcement | OpenAI or other model-provider integration |
| Projects, approvals and configurable business policy | Document/receipt extraction and classification |
| Budgets, expenses and financial invariants | Embeddings, authorized retrieval and AI orchestration |
| Authoritative PostgreSQL transactions | Derived features, analytical datasets and statistical analysis |
| Attributable audit records and sync acceptance | Anomaly findings, summaries and recommendations |
| Validating/recording accepted analysis results | Model/prompt/pipeline versions and processing metadata |

Java can call AI APIs through an official provider SDK, Spring AI or HTTP. Python is not required by OpenAI. The chosen division keeps ML/data-science libraries and experimentation outside the transactional core. Do not add a second Java AI orchestration stack without a reviewed need; verify framework/SDK compatibility before selecting dependencies.

## Data ownership

Authoritative project states, permissions, financial records and evidence metadata remain owned by Java modules. Python may own extracted text, embeddings, vector indexes, features and model outputs. An extracted amount is a suggestion, not an approved expense; a model's proposed tool action is untrusted intent, not permission.

Use controlled APIs, narrowly scoped read models or approved data exports, not unrestricted business-table access. Separate schemas and credentials in one PostgreSQL installation can be sufficient initially; physical database separation is not mandatory. Define read models, deletion/retention propagation, stale-index handling and version association before populating analytical storage.

Organization/project isolation applies to jobs, data retrieval, document access, conversation history, caches, vector searches, outputs and logs. Access to a derived embedding or summary must not outlive access to its source without a separately approved retention/access policy.

## Example: evidence analysis

1. A user uploads evidence through Java's authorized API and controlled object-storage flow.
2. Java commits metadata and an analysis job/outbox entry transactionally.
3. Durable delivery makes the job available to Python; credentials and data scope are least-privilege.
4. Python reads only approved source/context versions, extracts or analyzes, and produces a structured result.
5. The result includes source references, pipeline/model version, relevant uncertainty/limitations, timestamps and operation identity.
6. Java authenticates the service, validates the result schema and job/tenant/source association, and records an advisory result idempotently.
7. A user reviews it. Any resulting change uses the normal current authorization, concurrency checks and business workflow.

Do not hold a database transaction open while calling a model provider. Recheck permissions for displaying results and executing user actions, and define how revoked/cancelled jobs are discarded or quarantined.

## Delivery and failure handling

- Start with one Python background worker; use a PostgreSQL-backed durable job mechanism if sufficient. Kafka/RabbitMQ are deferred, not prerequisites.
- Version job/result schemas. Include job ID, tenant/project scope, operation type, source/version references, schema version, correlation ID and pipeline version where applicable. Do not put secrets or unrestricted source data in queue metadata.
- Define acknowledgement/lease semantics, bounded retries/backoff, deadlines, cancellation, poison-job handling and dead-letter/manual review. Delivery can repeat; deduplicate by job/result identity and never repeat business effects.
- Represent queued/running/succeeded/failed/cancelled states honestly. Surface retryable errors without exposing sensitive provider details.
- An internal FastAPI service is an option for future interactive/streaming AI, not mandatory infrastructure for a background worker. Java remains the user-facing authorization boundary.
- Java continues core work during Python/provider outages. Existing accepted business transactions are not undone because subsequent analysis failed.
- Contract tests must cover incompatible schemas, duplicate results, stale source versions, cross-tenant jobs, revocation, worker crashes and provider timeouts. Evaluate analysis quality against reviewed examples separately from API correctness.

## Privacy, security and human review

Provider credentials stay in backend secret management, never Flutter. Define organization-approved data egress, provider retention/training terms, residency, redaction, budgets, rate limits and logging before sending documents externally. An external provider's default settings are not a privacy policy.

Treat retrieved documents and model output as untrusted: document instructions must not change authorization or grant access to tools. Scope retrieval before model invocation; validate every tool request independently. Keep source citations/provenance and uncertainty with findings. AI assists human investigation; it must not accuse people, replace auditors, or become the final authority over approvals, payments or disciplinary decisions.

The [product vision](product-vision.md#integrity-engine) preserves the intended integrity-engine examples. See [architecture.md](architecture.md) and [api-design.md](api-design.md) for integration choices.