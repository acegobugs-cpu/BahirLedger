# Authentication, tenancy and configurable access

Updated: 2026-10-03. Confirmed product constraints and security boundaries; not an implementation claim. See [decisions](decisions.md), [architecture](architecture.md) and [current backend scope](b/README.md). Development steps and verification history are kept in local-only records.

## Confirmed account and organization model

- Self-service organization creation is supported. An organization is an independent workspace/tenant, not a legal entity.
- One organization per application account; joining an existing organization is invite-only. An existing membership cannot silently move to or join another tenant. Organization creation must enforce the same single-membership invariant atomically.
- Organization SSO is mandatory from the outset, including bootstrap. An established provider will be used; concrete provider is not chosen. OIDC is the proposed MVP protocol, not a promise of interoperability with every provider or SAML deployment.
- Personal devices only in the initial scope; shared-device and managed-fleet workflows are not assumed.
- Stable external identity is the validated **issuer + subject** pair. Email changes, email matching and domain ownership do not confer membership or automatically link accounts. Provider migration/account recovery needs an explicit reviewed process.

## Bootstrap and invitation boundary

1. Organization creation enters a **restricted pending bootstrap session**. It can configure the proposed organization/provider but cannot read or mutate tenant domain data or exercise active owner authority.
2. Select/configure a provider through a trusted registry. Validate issuer, discovery/JWKS endpoints, redirects and token parameters against reviewed configuration; do not accept arbitrary user-supplied issuer URLs or fetch arbitrary discovery endpoints.
3. Verify control of the intended provider configuration and perform a successful test sign-in using that configuration. Email/domain possession alone is not sufficient proof. The provider-specific control proof and failed/abandoned-bootstrap recovery must be designed before implementation.
4. Only then atomically activate the organization, initial owner membership and validated identity binding. Never grant tenant access merely because bootstrap or test login started.

Invitations must bind to the intended organization and intended recipient identity through a verified redemption flow; include expiry, one-use consumption and revocation. The exact pre-sign-in recipient binding mechanism is still to be designed. Token possession or a matching email alone must not bypass identity verification. Check existing account membership and consume invitation/create membership in one transaction; reject replay, wrong recipient, expiry and cross-org membership races without partial membership.

Flutter sign-in uses OAuth authorization code **with PKCE**, in the external system browser, with validated redirect URI and state/nonce. A native/public client carries **no app secret**. Validate token signature, issuer, audience and lifetime using the trusted provider configuration; do not accept an arbitrary token issuer as a new provider. Session/token storage and refresh/logout behavior must be threat-modeled for selected platforms. SSO authenticates identity, not application membership or project permissions.

## Policy, roles and delegation

The product must not impose a project-management ideology. Self-approval can be permitted or prohibited by explicit policy. Org-wide authority versus authority over selected projects is configurable. Authorized administrators can delegate role assignment and approval authority within explicit scope; role templates are optional presets, not a fixed hierarchy or a universal set of roles. RACI responsibility is not itself a security grant.

Policies are structured and scoped to organization/project. Organization policies define defaults, mandatory rules and which settings may be overridden by delegated project authorities. A project override applies **only when explicitly delegated** and cannot weaken mandatory rules or broaden the delegator's authority. Missing authorization denies; an approval request without an applicable approval rule denies. A self-approval setting does not independently grant approval permission.

Required evaluator decision boundary:

- Match the request organization, project ownership and grant organization; reject missing/cross-org permission.
- Distinguish org-wide grants from selected-project grants; project grants do not spill into other projects or organization administration.
- For approvals, require an applicable rule and apply configurable self-approval.
- Ignore/reject a project override as defined by the tested contract unless the organization explicitly delegates that setting; retain mandatory restrictions.
- Return a deterministic decision. A standalone internal evaluator does not by itself implement authenticated identities, durable roles, policy administration or complete application security.

Policy administration needs versioning, effective-policy preview/explanations, bounded delegation and audit. **Detailed precedence** for multiple grants/denies, competing delegations and policy versions remains open; do not invent a universal allow-wins/deny-wins hierarchy. Recovery, last-owner protection, owner transfer and emergency access remain gates, not a hidden password bypass to mandatory SSO.

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

- Concrete established provider; OIDC claims/discovery/logout/refresh interoperability; whether non-OIDC federation is deferred or brokered.
- Provider-control proof, trusted-provider registration and bootstrap abandonment/recovery.
- Exact invitation recipient binding and account/provider migration.
- Delegated-policy precedence, mandatory-rule representation, recovery and last-owner protection.
- Accepted offline defaults/exceptions and encrypted pending-work recovery.

These gates do not block a provider-independent scaffold/evaluator, but they block claiming complete authentication, tenant isolation or offline security.

## User-facing access journeys

- **Create organization:** anyone may start registration; pending setup shows verification progress, failed SSO test or abandoned-setup recovery without tenant-data access. Activation establishes the first owner's scoped administrative authority, not automatic financial/project approval authority.
- **Accept invitation:** show intended organization/access, authenticate through its SSO and explicitly accept. Explain wrong identity, revoked/expired/already-used invitation, suspended organization and existing-other-organization membership without leaking unrelated tenant data.
- **Return/sign in:** discover organization by saved context or code, use SSO/MFA, then open an accessible project list. Distinguish expired session, missing membership, suspension and provider outage; do not lose saved drafts on reauthentication.
- **My Access:** show organization/project roles, available capabilities, inherited policy and grant source. Org membership alone does not imply every-project visibility. Roles are named permission bundles; administrators preview gained/lost access before saving versioned changes.
- **Configure policies:** organization administrators set defaults, mandatory restrictions and delegable project overrides. Project administrators can edit only delegated settings. Membership administration does not silently grant approval-delegation power; no self-escalation beyond authorized scope.
- **Review requests:** submitters see pending decisions and reasons/history. An approver sees only eligible work; assignment routes work but never grants approval permission. Check effective rules, amount limits where configured, current request version and authority when accepting the decision. Explain lost access or changed requests.
- **Work offline:** distinguish saved locally, waiting to sync, accepted by server and needs attention. Recommended seven-day lease and five-minute local lock are separate; biometric/device-credential unlock does not renew online authorization. Sensitive financial/personal data is not downloaded by default; proposed longer field exceptions require explicit scope and authority.
- **Sign out/lose access:** warn about unsynchronized work; offer sync first, cancel sign-out, or explicit discard confirmation according to policy. Suspend server access on revocation; refresh membership and manage local caches when the device reconnects. Preserve audit attribution after membership removal. Prevent unsafe last-owner removal and provide reviewed lost-device/SSO-recovery paths, not password bypasses.

An organization is a group workspace, not necessarily a registered business: an NGO, company, government office, cooperative or community association can manage several projects. One organization per application account means no tenant switcher in the initial scope; whether one person may maintain separate accounts in different organizations remains to be settled. Mandatory SSO is a separate accepted constraint, not inherent in the organization concept; its onboarding cost for small groups must be considered.

Organization-specific self-approval, permission administration and all-project versus selected-project authority remain configurable choices. Offline timings, online-by-default approvals and up-to-30-day exceptions remain recommendations, not accepted hardcoded policy. Permission/security administration is online-only in the proposed design; optional offline decision capture never implies final approval.