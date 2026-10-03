# Historical prototype decisions — Project Review

**Superseded as universal domain policy (2026-10-02).** Retained to explain the existing UI, not to prescribe every organization's workflow. See [current product direction](../../../README.md) and [client scope](../../README.md). Local development plans belong only in the root ignored documentation directory.

## Legacy behavior represented by the prototype

- Review is required before preparation.
- Rejection requires a reason.
- An amendment request requires a reason.

These are historical examples, not mandatory domain rules. Preserve existing regression behavior until a reviewed configurable implementation replaces it; do not copy the hardcoded rules into universal backend authorization.

## Current policy direction

Organizations are independent workspaces/tenants, not legal entities. Structured org/project policies configure workflows, self-approval, org-wide versus selected-project authority, and role/approval delegation by authorized administrators. Role templates are optional, not a fixed hierarchy. Project overrides require organization delegation and remain bounded by mandatory rules; self-approval settings never grant permission by themselves.

Who may review and whether the creator may approve are determined by explicit effective policy, not a universal yes/no answer. Detailed delegated precedence, recovery/last-owner protection and workflow settings remain to be specified and tested. The former foundation-only/pending status is historical: the UI now integrates managed account sign-in, but not tenant membership or server-authorized project workflows. Managed signup is planned and organization SSO is optional future work; see [current auth/access](../../../auth-access.md). These prototype review decisions do not establish production authorization.