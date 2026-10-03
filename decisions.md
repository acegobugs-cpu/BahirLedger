# Decisions and gates

Updated: 2026-10-03. Keep unresolved policy explicit. Implementing a proposed default does not make it an approved product decision. This is the shared decision register; execution steps and results belong to local development records.

## Confirmed inputs

- Flutter app under `ui/`, Java backend under `b/`; architecture, access, product and API/AI specifications at the repository root are version-control eligible. Only development notes, context, plans and history remain in root `docs/`, Git-ignored.
- Work in small testable, reviewable increments. Architecture approval does not certify implemented security or authorize all features at once.
- Approved [architecture](architecture.md): Java Spring Boot/PostgreSQL modular monolith, REST/JSON + OpenAPI, explicit push/pull sync, S3-compatible evidence; BahirLedger-managed identity by default and optional organization SSO. OIDC is proposed for future SSO interoperability, not the current sign-in protocol.
- Approved [AI ownership](ai-analytics.md): Python handles AI-provider integration, processing and derived analytics; Java retains business authority and authoritative data. Python cannot independently mutate approvals, project states, permissions or financial records. Deploy with the first concrete AI feature; core Java workflows must remain available without it. OpenAI, specific SDKs/models, FastAPI and a broker are not selected dependencies.
- [API decisions](api-design.md): REST/JSON + OpenAPI for clients, explicit REST synchronization and authorized object transfers; versioned durable jobs/results for Python. Optional internal HTTP for interactive AI and optional SSE later. GraphQL, gRPC and WebSockets deferred until a demonstrated requirement; mobile background alerts use platform push rather than permanent sockets.
- Self-service org creation; org is an independent workspace/tenant, not a legal entity. One org per application account, invite-only membership, personal devices only. Managed registration with verified email is the planned default; organization bootstrap does not require an organization IdP. Registration and membership are not implemented.
- Structured org/project policy configures self-approval, role/approval delegation by authorized admins, and org-wide versus selected-project authority. Optional role templates, no fixed methodology. Org-delegated overrides are bounded by mandatory rules.
- Restricted managed bootstrap: verify account/email and satisfy controlled organization activation before tenant access; atomically enforce one org/account. Invites bind recipient/org, expire and are one-use; verified email alone is not membership. Optional SSO enrollment will require provider-control verification/test sign-in, trusted registries and issuer+subject binding. Linking requires verified control of both identities, never matching-email auto-linking. External-browser auth code + PKCE/no client secret applies to future SSO only.
- Chosen first slice: direct Java email/password sign-in, BCrypt cost 12, opaque 30-minute bearer tokens held only in Flutter memory, backend in-memory SHA-256 digest sessions and JDBC/Flyway accounts. No auth server, OIDC, cookie authentication or refresh tokens. The explicit local profile provisions development accounts only and uses H2 files outside the repository; PostgreSQL is the deployment target but live PostgreSQL is untested. The authenticated landing has identity only, not membership; no production-ready claim.
- [Legacy decisions](ui/docs/dec/decisions.md) about required review and reasons are historical prototype rules, not universal policy. Preserve regression behavior until a reviewed configurable replacement.
- [Offline recommendations](auth-access.md) (seven days, five minutes, 30-day exceptions, online-by-default approvals) remain unaccepted proposals. Revocation reaches disconnected devices later; pending work retained encrypted; no authoritative offline approvals.

## Superseded identity decision — 2026-10-03

The earlier mandatory organization SSO, no-local-password-service and provider-required bootstrap direction is **superseded**, not an additional active rule. The accepted replacement is managed identity by default with optional organization SSO. Provider-control/test-sign-in gates remain relevant when enabling SSO, not prerequisites for managed signup or organization creation. This changes identity onboarding only: invitation-only membership, one org/account, personal devices and configurable authorization remain unchanged.

## Open decision categories

| Gate | Decision needed | Safe planning boundary |
| --- | --- | --- |
| Managed identity/tenancy | Verified-email registration, invitation recipient binding, atomic org/bootstrap membership, password recovery/change, MFA, abuse/audit controls and session hardening? | Local development provisioning is not production registration; no email-as-membership or tenant access during pending bootstrap. |
| Optional SSO | Provider/protocol interoperability (OIDC proposed), provider-control proof/registry administration, linking, migration/recovery and org authentication policy? | No arbitrary issuer, matching-email auto-link or unreviewed recovery bypass. Not a gate on managed signup. |
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