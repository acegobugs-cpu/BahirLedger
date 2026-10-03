# Decisions and gates

Updated: 2026-10-03. Keep unresolved policy explicit. Implementing a proposed default does not make it an approved product decision. This is the shared decision register; execution steps and results belong to local development records.

## Confirmed inputs

- Flutter app under `ui/`, Java backend under `b/`; architecture, access, product and API/AI specifications at the repository root are version-control eligible. Only development notes, context, plans and history remain in root `docs/`, Git-ignored.
- Work in small testable, reviewable increments. Architecture approval does not certify implemented security or authorize all features at once.
- Approved [architecture](architecture.md): Java Spring Boot/PostgreSQL modular monolith, REST/JSON + OpenAPI, explicit push/pull sync, S3-compatible evidence; established identity provider, not yet selected. OIDC interoperability is proposed for MVP.
- Approved [AI ownership](ai-analytics.md): Python handles AI-provider integration, processing and derived analytics; Java retains business authority and authoritative data. Python cannot independently mutate approvals, project states, permissions or financial records. Deploy with the first concrete AI feature; core Java workflows must remain available without it. OpenAI, specific SDKs/models, FastAPI and a broker are not selected dependencies.
- [API decisions](api-design.md): REST/JSON + OpenAPI for clients, explicit REST synchronization and authorized object transfers; versioned durable jobs/results for Python. Optional internal HTTP for interactive AI and optional SSE later. GraphQL, gRPC and WebSockets deferred until a demonstrated requirement; mobile background alerts use platform push rather than permanent sockets.
- Self-service org creation; org is an independent workspace/tenant, not a legal entity. One org per application account, invite-only membership, mandatory org SSO from outset, personal devices only.
- Structured org/project policy configures self-approval, role/approval delegation by authorized admins, and org-wide versus selected-project authority. Optional role templates, no fixed methodology. Org-delegated overrides are bounded by mandatory rules.
- Restricted SSO bootstrap: verify provider control and test sign-in before activation/tenant data. Stable issuer+subject identity; email/domain does not confer membership. Invites bind recipient/org, expire and are one-use; trusted provider registries, not arbitrary issuer URLs. Flutter external-browser auth code + PKCE, no app secret.
- [Legacy decisions](ui/docs/dec/decisions.md) about required review and reasons are historical prototype rules, not universal policy. Preserve regression behavior until a reviewed configurable replacement.
- [Offline recommendations](auth-access.md) (seven days, five minutes, 30-day exceptions, online-by-default approvals) remain unaccepted proposals. Revocation reaches disconnected devices later; pending work retained encrypted; no authoritative offline approvals.

## Open decision categories

| Gate | Decision needed | Safe planning boundary |
| --- | --- | --- |
| Identity | Concrete provider/protocol interoperability (MVP OIDC proposed), provider-control proof/registry administration, invitation binding, migration/recovery? | No custom password fallback, arbitrary issuer, email-as-membership or tenant access during pending bootstrap. |
| Policy | Detailed delegated precedence, conflicting grants, mandatory-rule representation, recovery and last-owner/transfer protection? | An internal evaluator is not role administration or policy storage. No undelegated override or privilege escalation. |
| Device access | Token/key storage, accepted offline lease/lock/exception defaults, proposed approval commands and revoked-user pending-work recovery? | Personal devices; no instant disconnected revocation or authoritative offline approval; encrypted retention is not access permission. |
| Workflow | Configured submit/review scope, self-approval setting, editing after submission, explicit under-review action, rejection recovery, resubmission after amendment? | Configurable org/project rules; legacy review/reason requirements are not universal. Label demo actors as prototype behavior, not security. |
| Finance | Currency/precision, zero-cost items, funding committed vs received, project cap/target, shortage warning vs activation blocker? | Do not infer received cash from funding entries or spent money from estimates. Explicitly map divergent categories. |
| Readiness | Are Team/Documents required by the effective policy? What records prove completion? Optional procurement? What constitutes funding/budget readiness? | No hardcoded completion flags or universal methodology. Missing configured required feature blocks activation until implemented in a separate tested slice. |
| Client storage | First supported runtime(s), local storage package, encryption, schema/versioning, migrations, demo seeding, backup/error recovery? | PostgreSQL is approved for the server; choose client storage after target validation and coordinate with synchronization. Do not assume mobile-only SQLite works on Linux/web. |
| Future: lifecycle | Completion request/final review states, evidence checks, closing/reopening and historical edits? | Do not implement one-click completion from enum availability alone. |
| AI/data | First feature, provider/model/SDK, allowed data egress/retention/residency, quality evaluation, job protocol and service credentials? | Provider unselected; derived data is not business authority. Require tenant isolation, idempotency, bounded retries, privacy controls and outage tolerance. |

## Implementation guidance (not implementation claims)

- One injected project repository/store, stable IDs, typed models/results, immutable updates; keep widgets thin and existing UI working.
- Small framework-native state mechanism is sufficient initially; no state-library migration without a concrete need.
- Durable project mutation plus event append should be atomic. An append-only local API is not a tamper-proof ledger.
- Separate demo fixtures from real persisted records; initialize sample data only explicitly.
- Keep backend/auth, sync, cryptography and finance-ledger changes separate from local state repairs. Do not confuse approved architecture with completed security. Deployment starts small; neither a dedicated broker, full event sourcing, nor multiple Java business services is required.