# Approved architecture and implementation boundary

Updated: 2026-10-03. Approved direction, not a claim that all capabilities are implemented. See [README.md](README.md) and [b/README.md](b/README.md) for current source scope. Development plans and verification history remain local and separate.

## Shape and ownership

- **Flutter client** in `ui/`: presentation, local drafts/cache and eventual encrypted pending commands. Client checks improve UX, never replace server authorization.
- **Java Spring Boot modular monolith** in `b/`: REST/JSON, explicit application commands, server authorization and transactional domain changes. Keep module boundaries inside one deployable service; do not introduce microservices now.
- **PostgreSQL**: authoritative tenant-scoped records, policy versions, memberships and attributable history. Mutation, audit append and any future outbox record must share a transaction. Persistence and tenant isolation require a separately validated implementation.
- **OpenAPI**: versioned API contract committed with the backend; runtime endpoints must match it. The [current static contract](b/src/main/resources/contracts/openapi.yaml) is not a public documentation endpoint. See [API design](api-design.md) for protocol choices.
- **Explicit push/pull synchronization**: client submits idempotent proposed commands and pulls scoped changes using a version/cursor contract. Server revalidates current membership, permissions, policy and conflicts; local acceptance is not server acceptance. Full synchronization is planned, not present today.
- **S3-compatible evidence storage**: private objects plus tenant-scoped metadata and controlled upload/download authorization; no public bucket or object-key-as-permission design. Evidence integration remains future work.
- **Established identity provider**: mandatory organization SSO; vendor not selected. MVP interoperability is proposed OIDC, subject to provider/protocol validation. No custom password service. See [auth/access](auth-access.md).
- **Python AI and analytics component**: owns model-provider integrations, document processing, embeddings/retrieval and derived analytical data. Consumes explicitly scoped, authorized data/events and produces advisory findings. Java retains business authority; Python cannot independently write authoritative project/financial records. Deploy with the first concrete AI feature; not a prerequisite for the core backend. OpenAI is not selected. See [AI and analytics](ai-analytics.md).

An organization is an independent workspace/tenant, **not a legal entity**. Projects belong to exactly one tenant. Any later legal-entity modeling must be separate. Application accounts join one organization only, by invitation; self-service organization creation is a controlled bootstrap exception, not open membership enrollment. No cross-organization sharing or tenant switching is authorized by this model.

## Module seams (direction, not implemented modules)

Identity/membership, authorization/policy, projects/workflow, preparation/finance, audit, sync and evidence should expose narrow application interfaces. Tenant context comes from validated identity and membership, never an untrusted organization ID alone. Scope every query, command, event, cache and storage key to the tenant; validate project ownership before evaluating project grants. PostgreSQL transactions provide the authoritative commit boundary. Local durable storage is a separate client choice, gated on supported platforms, encryption and recovery requirements.

Use structured org/project policies rather than a fixed project-management methodology. Workflow examples, RACI labels and role templates are optional; mandatory security constraints cannot be overridden by organization or project configuration.

## Why this division

Java/Spring Boot supplies a mature strongly typed ecosystem for transactions, validation, authorization, testing and domain workflows. Java decimal arithmetic and PostgreSQL constraints support financial correctness, but neither replaces explicit invariants and concurrency tests. Kotlin is a viable ecosystem alternative, not an additional implementation language selected here; Go/TypeScript are not needed as extra gateways or services.

Python provides the ecosystem for AI-provider orchestration, data science, document extraction and specialized ML. Java can call model APIs directly; the division is an ownership choice, not a Java limitation. Keep the core as one deployable Java application; add one Python worker rather than decomposing all business modules into services.

## Data and deployment boundaries

- Java owns business records, authorization, financial invariants, audit and synchronization. Python owns derived data (extracted text, embeddings, features and advisory outputs) behind scoped interfaces.
- A shared PostgreSQL installation with separate schemas/credentials is a possible cost-conscious start; do not give Python unrestricted table access. Dedicated databases or tenant deployments may be required by future isolation needs.
- Use current-state tables plus attributable append-only events and a transactional outbox where needed. Full event sourcing is not required; an append-only application API is not tamper-proof storage.
- Start durable AI jobs with PostgreSQL-backed delivery if sufficient; brokers such as Kafka/RabbitMQ are deferred until justified. Define retries, deduplication and recovery before delivery.
- The Java core remains available if Python or the model provider is unavailable. AI failures must not roll back independent business transactions or bypass normal workflows.
- Keep a typed injected client store/repository, immutable updates and stable IDs; keep demo fixtures separate from durable records. Framework-native Flutter state is sufficient until a concrete need warrants a library.

See [API design](api-design.md), [AI processing](ai-analytics.md), [auth/access](auth-access.md), and [decisions](decisions.md). Runtime versions and commands belong to the component READMEs; step-by-step execution records do not belong in this architecture specification.