package com.bahirledger.backend.access;

import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Small, side-effect-free policy primitive; not an authentication or role-administration service.
 * Callers must eventually load all inputs from trusted, tenant-scoped server state, never request claims.
 */
public final class AccessPolicy {
    private AccessPolicy() {}

    public enum Capability { PROJECT_VIEW, PROJECT_APPROVE, FINANCE_APPROVE, POLICY_MANAGE }

    /** Null projectId explicitly means all projects in this organization. */
    public record Grant(UUID organizationId, UUID projectId, Capability capability) {
        public Grant {
            Objects.requireNonNull(organizationId);
            Objects.requireNonNull(capability);
        }
    }

    public record Member(UUID accountId, UUID organizationId, boolean active, Set<Grant> grants) {
        public Member {
            Objects.requireNonNull(accountId);
            Objects.requireNonNull(organizationId);
            grants = Set.copyOf(grants);
        }
    }

    public record ProjectScope(UUID organizationId, UUID projectId) {
        public ProjectScope {
            Objects.requireNonNull(organizationId);
            Objects.requireNonNull(projectId);
        }
    }

    public record ApprovalRule(boolean allowSelfApproval) {}

    /** These rules are for one requested approval capability, not a universal workflow. */
    public record ApprovalPolicy(ApprovalRule organizationRule, boolean projectOverrideAllowed,
                                 ApprovalRule projectRule) {}

    public enum Decision {
        ALLOWED, INACTIVE_MEMBER, WRONG_ORGANIZATION, MISSING_CAPABILITY,
        MISSING_APPROVAL_RULE, SELF_APPROVAL_DENIED
    }

    public static Decision authorize(Member member, ProjectScope target, Capability capability) {
        Objects.requireNonNull(member);
        Objects.requireNonNull(target);
        Objects.requireNonNull(capability);
        if (!member.active()) return Decision.INACTIVE_MEMBER;
        if (!member.organizationId().equals(target.organizationId())) return Decision.WRONG_ORGANIZATION;
        boolean granted = member.grants().stream().anyMatch(grant ->
                grant.organizationId().equals(target.organizationId())
                && grant.capability() == capability
                && (grant.projectId() == null || grant.projectId().equals(target.projectId())));
        return granted ? Decision.ALLOWED : Decision.MISSING_CAPABILITY;
    }

    public static Decision approve(Member member, ProjectScope target, Capability capability,
                                   UUID submittedBy, ApprovalPolicy policy) {
        Objects.requireNonNull(submittedBy);
        Objects.requireNonNull(policy);
        if (capability != Capability.PROJECT_APPROVE && capability != Capability.FINANCE_APPROVE) {
            throw new IllegalArgumentException("An approval capability is required");
        }
        Decision access = authorize(member, target, capability);
        if (access != Decision.ALLOWED) return access;
        ApprovalRule rule = policy.organizationRule();
        if (rule == null) return Decision.MISSING_APPROVAL_RULE;
        if (policy.projectOverrideAllowed() && policy.projectRule() != null) rule = policy.projectRule();
        if (!rule.allowSelfApproval() && member.accountId().equals(submittedBy)) {
            return Decision.SELF_APPROVAL_DENIED;
        }
        return Decision.ALLOWED;
    }
}