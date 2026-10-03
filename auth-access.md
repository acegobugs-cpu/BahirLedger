# Authentication, tenancy and configurable access

Updated: 2026-10-03. Confirmed product constraints and security boundaries, with implemented account-only signup/sign-in and email verification identified separately below. See [decisions](decisions.md), [architecture](architecture.md) and [current backend scope](b/README.md). Development steps and verification history are kept in local-only records.

## Confirmed account and organization model

- Self-service organization creation is an accepted product direction, not yet implemented. An organization is an independent workspace/tenant, not a legal entity.
- One organization per application account; joining an existing organization is invite-only. An existing membership cannot silently move to or join another tenant. Organization creation must enforce the same single-membership invariant atomically.
- **BahirLedger-managed identity is the default; organization SSO is optional.** Account-only signup and email verification are implemented; organization bootstrap and invitations are not. Organization creation does not require an organization IdP. This supersedes the earlier mandatory-SSO/no-local-auth decision; see [decision history](decisions.md#superseded-identity-decision--2026-10-03).
- Personal devices only in the initial scope; shared-device and managed-fleet workflows are not assumed.
- Managed accounts have a stable application UUID. Future external identity is the validated **issuer + subject** pair. Linking must verify control of both identities; email changes, matching email or domain ownership do not confer membership or automatically link accounts. Provider migration/account recovery needs an explicit reviewed process.

## Implemented account-only signup, sign-in and verification

- Java directly authenticates email/password against JDBC accounts with BCrypt cost 12. Flyway manages account migrations. There is no separate authentication server, OIDC flow, cookie authentication, HTTP session or refresh token.
- Public registration creates a durable account, sends verification and issues an account-only session after delivery acceptance. Duplicate signup sends no mail. Delivery failure can leave a pending account without a session; sign in and resend after cooldown. Explicit `local` provisioning remains create-only and requires all three development environment variables; no default application credentials or startup password resets. Local H2 files live outside the checkout; PostgreSQL is the deployment target but live PostgreSQL remains untested.
- Login returns an opaque bearer token and absolute 30-minute expiry. Flutter stores the raw token only in memory; backend memory holds only SHA-256 digests plus account/expiry. Backend restart invalidates sessions but retains durable accounts. `/me` does not renew expiry and returns identity only, **not organization/project membership or grants**.
- Required boolean `emailVerified` defaults false for new, migrated and locally provisioned accounts. Login does not send mail and allows only account/verification operations while pending. Confirmation requires a current same-active-account bearer plus a single-use 30-minute token; only its SHA-256 digest is persisted. Account-row locking serializes confirmation/resend. Resend rotates tokens with a durable 60-second cooldown, including failed delivery; separate bounded per-process rate limits also apply. Verification never renews sessions or grants tenant authority; future tenant APIs must check verified email **and** membership.
- Flutter confirms `/me` after signup/login and gates unverified accounts on confirmation/resend/status/sign-out; verified accounts see identity only. Verification operations are serialized and stale responses cannot revive cleared sessions. Timer/resume expiry and reload/restart sign-out remain enforced. Web omits cookies, rejects redirects and disables caching; native also rejects redirects. Logout clears locally first and warns if remote revocation is unconfirmed. Aborted login, failed identity lookup or app closure may leave a server session until expiry.
- Fragment verification links are held only in memory and scrubbed from the current browser URL/history entry before UI handling; same-account sign-in and explicit confirmation are required. Native supports manual token paste or configured trusted full-link paste, not OS universal/app links. Never log/persist tokens; scrubbing cannot erase browser/provider records created before app startup.
- Real SMTP is configurable but delivery defaults disabled (`503`, not fake success). A private external file outbox is allowed only with the exclusively local profile and does not deliver to an inbox. Adapter acceptance does not guarantee inbox delivery; synchronous delivery has no durable worker/automatic retry or atomic database/mail commit. See [delivery setup and reliability limits](b/README.md#verification-delivery-setup).
- The separate local project demo grants no membership/permissions. Input limits, generic errors, bounded in-process throttling, no-store responses and fail-closed routing are implemented; they do not make this production-ready. See [API contract summary](api-design.md#implemented-managed-account-authentication), [backend setup/security limits](b/README.md) and [client behavior](ui/README.md).

**Not implemented:** invitations, organization bootstrap/membership, password recovery/change, MFA, optional SSO/linking, durable distributed sessions/revocation/throttle maps, tenant/business APIs, full audit/abuse monitoring or offline security. The persistent resend cooldown alone does not provide distributed abuse protection.

## Bootstrap and invitation boundary

The following tenant onboarding remains planned; implemented account creation/email verification supplies only its identity prerequisite, not bootstrap authority:

1. Create/verify a BahirLedger-managed account through a reviewed verified-email registration flow. Possessing an email address or completing login alone grants no tenant access.
2. Organization creation enters a **restricted pending bootstrap session**. It can configure the proposed workspace but cannot read or mutate tenant domain data or exercise active owner authority. No organization IdP is required.
3. Validate the verified account, controlled bootstrap conditions and single-organization invariant; design failed/abandoned-bootstrap recovery and abuse protections before release.
4. Atomically activate the organization and initial owner membership. Never grant tenant access merely because registration or bootstrap started. Initial owner administration does not automatically grant financial/project approval permission.

Invitations must bind to the intended organization and intended recipient identity through a verified redemption flow; include expiry, one-use consumption and revocation. The exact pre-sign-in recipient binding mechanism is still to be designed. Token possession or a matching email alone must not bypass identity verification. Check existing account membership and consume invitation/create membership in one transaction; reject replay, wrong recipient, expiry and cross-org membership races without partial membership.

## Optional organization SSO — future

Select/configure a provider through a trusted registry; validate issuer, discovery/JWKS endpoints, redirects and token parameters against reviewed configuration, never arbitrary user-supplied issuer URLs. Verify provider control and successful test sign-in before enabling the binding. Provider-specific control proof, failed enrollment, migration/recovery and whether/how an organization may enforce SSO require review; these are not gates on managed signup.

OIDC is the proposed initial SSO protocol; no provider or universal SAML interoperability is selected. Future Flutter SSO would use external-browser OAuth authorization code **with PKCE**, validated redirect URI and state/nonce, and **no client secret**. Validate signature, issuer, audience and lifetime against trusted configuration. Linking needs explicit authenticated verification of both managed and external identities, not matching-email auto-linking. Review storage/refresh/logout behavior for that future flow separately from current bearer sessions. SSO authenticates identity, not application membership or project permissions.

## Policy, roles and delegation

The product must not impose a project-management ideology. Self-approval can be permitted or prohibited by explicit policy. Org-wide authority versus authority over selected projects is configurable. Authorized administrators can delegate role assignment and approval authority within explicit scope; role templates are optional presets, not a fixed hierarchy or a universal set of roles. RACI responsibility is not itself a security grant.

Policies are structured and scoped to organization/project. Organization policies define defaults, mandatory rules and which settings may be overridden by delegated project authorities. A project override applies **only when explicitly delegated** and cannot weaken mandatory rules or broaden the delegator's authority. Missing authorization denies; an approval request without an applicable approval rule denies. A self-approval setting does not independently grant approval permission.

Required evaluator decision boundary:

- Match the request organization, project ownership and grant organization; reject missing/cross-org permission.
- Distinguish org-wide grants from selected-project grants; project grants do not spill into other projects or organization administration.
- For approvals, require an applicable rule and apply configurable self-approval.
- Ignore/reject a project override as defined by the tested contract unless the organization explicitly delegates that setting; retain mandatory restrictions.
- Return a deterministic decision. A standalone internal evaluator does not by itself implement authenticated identities, durable roles, policy administration or complete application security.

Policy administration needs versioning, effective-policy preview/explanations, bounded delegation and audit. **Detailed precedence** for multiple grants/denies, competing delegations and policy versions remains open; do not invent a universal allow-wins/deny-wins hierarchy. Recovery, last-owner protection, owner transfer and emergency access remain gates; neither managed credentials nor optional SSO may bypass membership or effective authorization.

Legacy UI review-before-preparation and rejection/amendment reasons are prototype behavior, **not universal domain rules**. Keep existing prototype regression behavior until a reviewed configurable workflow replaces it; do not encode those examples as mandatory server policy. See the [historical decisions](ui/docs/dec/decisions.md).

## Offline access: proposals, not accepted defaults

| Recommendation | Decision status |
| --- | --- |
| Seven-day offline data-access lease | Provisional; not explicitly accepted |
| Five-minute local inactivity lock | Provisional; not explicitly accepted |
| Exceptions up to 30 days | Provisional; not explicitly accepted; authority and safeguards unresolved |
| Approvals online by default | Proposed default, not accepted universal policy |
| Permit offline proposed approval commands where configured | Proposed/configurable, never authoritative offline approval |

Revocation cannot reach a disconnected device until it reconnects; expiry/local locking can bound exposure but cannot promise instant remote revocation. Retain pending work **encrypted** for controlled reconciliation rather than silently discarding it on expiry/revocation. Retention does not grant permission to read or submit it. Reconnect must revalidate membership, scope and current policy before acceptance; denied/conflicting work needs an explicit recovery UX. No authoritative offline approvals. Device-clock manipulation, lease renewal, key lifecycle, secure storage, revoked-user recovery and retention/deletion rules require explicit design and tests.

## Open decisions before broader implementation

- Remaining full interactive browser/manual verification, SMTP/inbox, PostgreSQL and native validation and production mail reliability; live HTTP/file-delivery and browser-link/CORS checks passed (see [validation limits](b/README.md#verification-validation--2026-10-03)). Exact invitation recipient binding, durable tenancy/atomic bootstrap, password lifecycle/MFA, session hardening and abuse/audit controls remain open.
- Optional SSO provider; OIDC claims/discovery/logout/refresh interoperability; whether non-OIDC federation is deferred or brokered.
- Provider-control proof, trusted-provider registration, explicit identity linking, account/provider migration and bootstrap abandonment/recovery.
- Delegated-policy precedence, mandatory-rule representation, recovery and last-owner protection.
- Accepted offline defaults/exceptions and encrypted pending-work recovery.

Optional-provider selection does not block managed signup or durable-tenancy work. These outstanding capabilities prevent any claim of complete production authentication, tenant isolation or offline security; implemented account-only signup/verification does not satisfy them.

## Planned user-facing access journeys

- **Create organization:** start managed registration and verify email; pending setup shows verification or abandoned-setup recovery without tenant-data access and without requiring an IdP. Activation establishes the first owner's scoped administrative authority, not automatic financial/project approval authority. Optional SSO enrollment is a separate reviewed journey.
- **Accept invitation:** show intended organization/access, verify the intended managed identity (or explicitly linked optional SSO identity) and accept. Explain wrong identity, revoked/expired/already-used invitation, suspended organization and existing-other-organization membership without leaking unrelated tenant data.
- **Return/sign in:** use managed sign-in by default or configured optional SSO, then resolve membership/permissions before opening accessible projects. Distinguish expired session, missing membership, suspension and provider outage; do not lose saved drafts on reauthentication. Today only identity landing and separate demo exist, not this tenant journey.
- **My Access:** show organization/project roles, available capabilities, inherited policy and grant source. Org membership alone does not imply every-project visibility. Roles are named permission bundles; administrators preview gained/lost access before saving versioned changes.
- **Configure policies:** organization administrators set defaults, mandatory restrictions and delegable project overrides. Project administrators can edit only delegated settings. Membership administration does not silently grant approval-delegation power; no self-escalation beyond authorized scope.
- **Review requests:** submitters see pending decisions and reasons/history. An approver sees only eligible work; assignment routes work but never grants approval permission. Check effective rules, amount limits where configured, current request version and authority when accepting the decision. Explain lost access or changed requests.
- **Work offline:** distinguish saved locally, waiting to sync, accepted by server and needs attention. Recommended seven-day lease and five-minute local lock are separate; biometric/device-credential unlock does not renew online authorization. Sensitive financial/personal data is not downloaded by default; proposed longer field exceptions require explicit scope and authority.
- **Sign out/lose access:** warn about unsynchronized work; offer sync first, cancel sign-out, or explicit discard confirmation according to policy. Suspend server access on revocation; refresh membership and manage local caches when the device reconnects. Preserve audit attribution after membership removal. Prevent unsafe last-owner removal and provide reviewed lost-device/account/SSO-recovery paths, not authorization bypasses. This future encrypted-work flow is separate from current memory-only token clearing.

An organization is a group workspace, not necessarily a registered business: an NGO, company, government office, cooperative or community association can manage several projects. One organization per application account means no tenant switcher in the initial scope; whether one person may maintain separate accounts in different organizations remains to be settled. Managed onboarding avoids requiring small groups to operate an IdP; optional SSO does not change the tenant model.

Organization-specific self-approval, permission administration and all-project versus selected-project authority remain configurable choices. Offline timings, online-by-default approvals and up-to-30-day exceptions remain recommendations, not accepted hardcoded policy. Permission/security administration is online-only in the proposed design; optional offline decision capture never implies final approval.
