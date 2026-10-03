package com.bahirledger.backend.access;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import static com.bahirledger.backend.access.AccessPolicy.*;
import static org.assertj.core.api.Assertions.*;

class AccessPolicyTest {
    private final UUID org = UUID.randomUUID();
    private final UUID project = UUID.randomUUID();
    private final UUID account = UUID.randomUUID();
    private final ProjectScope target = new ProjectScope(org, project);

    private Member member(Grant... grants) { return new Member(account, org, true, Set.of(grants)); }
    private Grant scoped(Capability capability) { return new Grant(org, project, capability); }
    private ApprovalPolicy policy(boolean self) { return new ApprovalPolicy(new ApprovalRule(self), false, null); }

    @Test
    void defaultDenyAndInactiveMembership() {
        assertThat(authorize(member(), target, Capability.PROJECT_VIEW)).isEqualTo(Decision.MISSING_CAPABILITY);
        assertThat(authorize(new Member(account, org, false, Set.of(scoped(Capability.PROJECT_VIEW))),
                target, Capability.PROJECT_VIEW)).isEqualTo(Decision.INACTIVE_MEMBER);
    }

    @Test
    void projectGrantDoesNotLeakToOtherProjectsOrCapabilities() {
        var member = member(scoped(Capability.PROJECT_VIEW));
        assertThat(authorize(member, target, Capability.PROJECT_VIEW)).isEqualTo(Decision.ALLOWED);
        assertThat(authorize(member, new ProjectScope(org, UUID.randomUUID()), Capability.PROJECT_VIEW))
                .isEqualTo(Decision.MISSING_CAPABILITY);
        assertThat(authorize(member, target, Capability.PROJECT_APPROVE)).isEqualTo(Decision.MISSING_CAPABILITY);
    }

    @Test
    void explicitOrganizationGrantCoversProjectsButNotAnotherTenant() {
        var member = member(new Grant(org, null, Capability.PROJECT_APPROVE));
        assertThat(authorize(member, target, Capability.PROJECT_APPROVE)).isEqualTo(Decision.ALLOWED);
        assertThat(authorize(member, new ProjectScope(org, UUID.randomUUID()), Capability.PROJECT_APPROVE))
                .isEqualTo(Decision.ALLOWED);
        assertThat(authorize(member, new ProjectScope(UUID.randomUUID(), project), Capability.PROJECT_APPROVE))
                .isEqualTo(Decision.WRONG_ORGANIZATION);
    }

    @Test
        void foreignOrganizationGrantCannotAuthorizeCurrentTenant() {
        assertThat(authorize(member(new Grant(UUID.randomUUID(), project, Capability.PROJECT_VIEW)),
                target, Capability.PROJECT_VIEW)).isEqualTo(Decision.MISSING_CAPABILITY);
    }

    @Test
    void policyAdministrationDoesNotImplyApproval() {
        assertThat(approve(member(scoped(Capability.POLICY_MANAGE)), target, Capability.PROJECT_APPROVE,
                account, policy(true))).isEqualTo(Decision.MISSING_CAPABILITY);
    }

    @Test
    void selfApprovalIsConfigurableRatherThanUniversal() {
        var approver = member(scoped(Capability.PROJECT_APPROVE));
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account, policy(true)))
                .isEqualTo(Decision.ALLOWED);
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account, policy(false)))
                .isEqualTo(Decision.SELF_APPROVAL_DENIED);
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, UUID.randomUUID(), policy(false)))
                .isEqualTo(Decision.ALLOWED);
    }

    @Test
    void projectOverrideCannotBypassMandatoryOrganizationRule() {
        var approver = member(scoped(Capability.PROJECT_APPROVE));
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account,
                new ApprovalPolicy(new ApprovalRule(false), false, new ApprovalRule(true))))
                .isEqualTo(Decision.SELF_APPROVAL_DENIED);
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account,
                new ApprovalPolicy(new ApprovalRule(false), true, new ApprovalRule(true))))
                .isEqualTo(Decision.ALLOWED);
    }

    @Test
    void absentProjectRuleInheritsAndAbsentOrganizationRuleDenies() {
        var approver = member(scoped(Capability.PROJECT_APPROVE));
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account,
                new ApprovalPolicy(new ApprovalRule(false), true, null))).isEqualTo(Decision.SELF_APPROVAL_DENIED);
        assertThat(approve(approver, target, Capability.PROJECT_APPROVE, account,
                new ApprovalPolicy(null, true, new ApprovalRule(true)))).isEqualTo(Decision.MISSING_APPROVAL_RULE);
    }

    @Test
    void financeAndProjectApprovalsHaveIndependentRulesAndGrants() {
        var both = member(scoped(Capability.PROJECT_APPROVE), scoped(Capability.FINANCE_APPROVE));
        assertThat(approve(both, target, Capability.PROJECT_APPROVE, account, policy(true))).isEqualTo(Decision.ALLOWED);
        assertThat(approve(both, target, Capability.FINANCE_APPROVE, account, policy(false)))
                .isEqualTo(Decision.SELF_APPROVAL_DENIED);
        assertThat(approve(member(scoped(Capability.PROJECT_APPROVE)), target, Capability.FINANCE_APPROVE,
                account, policy(true))).isEqualTo(Decision.MISSING_CAPABILITY);
    }

    @Test
    void grantsAreCopiedAndInvalidInputsCannotAuthorize() {
        var grants = new HashSet<Grant>();
        var member = new Member(account, org, true, grants);
        grants.add(scoped(Capability.PROJECT_APPROVE));
        assertThat(member.grants()).isEmpty();
        assertThatThrownBy(() -> member.grants().add(scoped(Capability.PROJECT_APPROVE)))
                .isInstanceOf(UnsupportedOperationException.class);
        assertThatThrownBy(() -> approve(member, target, Capability.PROJECT_VIEW, account, policy(true)))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new ProjectScope(null, project)).isInstanceOf(NullPointerException.class);
    }
}