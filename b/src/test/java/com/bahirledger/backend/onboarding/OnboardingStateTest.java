package com.bahirledger.backend.onboarding;

import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import com.bahirledger.backend.AuthTestConfiguration.MutableClock;
import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.ApiException;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.UserView;
import org.flywaydb.core.Flyway;
import org.h2.jdbcx.JdbcDataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.support.JdbcTransactionManager;
import static org.assertj.core.api.Assertions.*;

class OnboardingStateTest {
    JdbcTemplate jdbc;
    MutableClock clock;
    JdbcTransactionManager transactions;
    AccountStore accounts;
    OnboardingService service;
    UserView owner;
    UserView recipient;
    JdbcTemplate postgresAdmin;
    String postgresSchema;

    @BeforeEach void setup() {
        javax.sql.DataSource source;
        String postgresUrl = System.getProperty("bahirledger.test.postgres.url");
        if (postgresUrl != null) {
            // Explicit disposable test database only; never load private runtime properties.
            if (!postgresUrl.matches("jdbc:postgresql://127\\.0\\.0\\.1:[0-9]+/bahirledger_onboarding_test")) {
                throw new IllegalArgumentException("Use an isolated loopback bahirledger_onboarding_test database");
            }
            var admin = new DriverManagerDataSource(postgresUrl, "onboarding_test", "");
            postgresAdmin = new JdbcTemplate(admin);
            postgresSchema = "onboarding_" + UUID.randomUUID().toString().replace("-", "");
            postgresAdmin.execute("CREATE SCHEMA " + postgresSchema);
            source = new DriverManagerDataSource(postgresUrl + "?currentSchema=" + postgresSchema, "onboarding_test", "");
        } else {
            var h2 = new JdbcDataSource();
            h2.setURL("jdbc:h2:mem:" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1");
            h2.setUser("sa");
            source = h2;
        }
        Flyway.configure().dataSource(source).load().migrate();
        jdbc = new JdbcTemplate(source);
        transactions = new JdbcTransactionManager(source);
        clock = new MutableClock();
        accounts = new AccountStore(jdbc);
        service = new OnboardingService(jdbc, clock, transactions);
        owner = verified("owner@example.test");
        recipient = verified("recipient@example.test");
    }

    @org.junit.jupiter.api.AfterEach void removeDisposableSchema() {
        if (postgresAdmin != null && postgresSchema != null) {
            postgresAdmin.execute("DROP SCHEMA " + postgresSchema + " CASCADE");
        }
    }
    UserView verified(String email) {
        var user = accounts.create(email, "Synthetic fixture", "synthetic-hash");
        jdbc.update("UPDATE accounts SET email_verified = TRUE WHERE id = ?", user.id());
        return accounts.findActiveUser(user.id()).orElseThrow();
    }
    OnboardingService.Context activate(UserView user) {
        return service.activate(user.id(), service.bootstrap(user.id(), "Organization").bootstrap().id());
    }
    int count(String table) { return jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class); }
    void code(Runnable work, String code) {
        assertThatThrownBy(work::run).isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).code()).isEqualTo(code));
    }

    @Test void pendingIsDurableBoundedAndGrantsNothingUntilAtomicActivation() {
        var setup = service.bootstrap(owner.id(), "  First  ").bootstrap();
        assertThat(setup.name()).isEqualTo("First");
        assertThat(setup.expiresAt()).isEqualTo(clock.instant().plus(Duration.ofHours(24)));
        assertThat(count("organizations")).isZero();
        assertThat(count("organization_memberships")).isZero();
        code(() -> service.invitations(owner.id()), "forbidden");
        code(() -> service.issue(owner.id(), recipient.email()), "forbidden");
        clock.advance(Duration.ofHours(2));
        service = new OnboardingService(jdbc, clock, transactions);
        assertThat(service.context(owner.id()).bootstrap()).isEqualTo(setup);
        var edited = service.bootstrap(owner.id(), "Edited").bootstrap();
        assertThat(edited.id()).isEqualTo(setup.id());
        assertThat(edited.expiresAt()).isEqualTo(setup.expiresAt());
        assertThat(count("organization_bootstraps")).isEqualTo(1);
        var result = service.activate(owner.id(), setup.id());
        assertThat(result.bootstrap()).isNull();
        assertThat(result.membership().role()).isEqualTo("OWNER");
        assertThat(result.membership().organizationName()).isEqualTo("Edited");
        assertThat(service.activate(owner.id(), setup.id())).isEqualTo(result);
        clock.advance(Duration.ofDays(2));
        assertThat(new OnboardingService(jdbc, clock, transactions).activate(owner.id(), setup.id())).isEqualTo(result);
        assertThat(count("organizations")).isEqualTo(1);
        assertThat(count("organization_memberships")).isEqualTo(1);
        code(() -> service.activate(owner.id(), UUID.randomUUID()), "bootstrap_unavailable");
        code(() -> service.bootstrap(owner.id(), "Another"), "membership_exists");
        assertThat(jdbc.queryForList("SELECT action FROM onboarding_audit", String.class))
                .containsExactly("BOOTSTRAP_STARTED", "BOOTSTRAP_UPDATED", "ORGANIZATION_ACTIVATED", "MEMBERSHIP_CREATED", "BOOTSTRAP_ACTIVATED");
    }

    @Test void cancelExpiryAndRestartNeverReviveStaleIdsOrExtendLifetime() {
        var first = service.bootstrap(owner.id(), "First").bootstrap();
        code(() -> service.cancel(owner.id(), UUID.randomUUID()), "bootstrap_unavailable");
        service.cancel(owner.id(), first.id());
        assertThat(service.context(owner.id()).bootstrap()).isNull();
        code(() -> service.cancel(owner.id(), first.id()), "bootstrap_unavailable");
        code(() -> service.activate(owner.id(), first.id()), "bootstrap_unavailable");
        var second = service.bootstrap(owner.id(), "Second").bootstrap();
        assertThat(second.id()).isNotEqualTo(first.id());
        clock.advance(Duration.ofHours(24).minusNanos(1));
        assertThat(service.context(owner.id()).bootstrap()).isNotNull();
        clock.advance(Duration.ofNanos(1));
        assertThat(service.context(owner.id()).bootstrap()).isNull();
        code(() -> service.activate(owner.id(), second.id()), "bootstrap_unavailable");
        code(() -> service.cancel(owner.id(), second.id()), "bootstrap_unavailable");
        var third = service.bootstrap(owner.id(), "Third").bootstrap();
        assertThat(third.id()).isNotEqualTo(second.id());
        assertThat(count("organization_bootstraps")).isEqualTo(1);
        assertThat(count("organizations")).isZero();
        assertThat(jdbc.queryForList("SELECT action FROM onboarding_audit", String.class)).contains("BOOTSTRAP_EXPIRED");
    }

    @Test void onlyDigestPersistsAndAcceptanceCancelsPendingWithoutProjectGrants() {
        var organization = activate(owner).membership();
        var pending = service.bootstrap(recipient.id(), "Unused").bootstrap();
        var issued = service.issue(owner.id(), "  RECIPIENT@EXAMPLE.TEST  ");
        assertThat(issued.token()).matches("[A-Za-z0-9_-]{43}");
        assertThat(issued.toString()).doesNotContain(issued.token());
        assertThat(new OnboardingController.TokenRequest(issued.token()).toString()).doesNotContain(issued.token());
        assertThat(jdbc.queryForObject("SELECT token_digest FROM organization_invitations", String.class)).isEqualTo(SessionStore.digest(issued.token()));
        for (String table : List.of("organization_invitations", "onboarding_audit", "organization_bootstraps", "organization_memberships", "organizations", "accounts")) {
            assertThat(jdbc.queryForList("SELECT * FROM " + table).toString()).doesNotContain(issued.token());
        }
        service = new OnboardingService(jdbc, clock, transactions);
        assertThat(service.preview(recipient.id(), issued.token()).organizationName()).isEqualTo(organization.organizationName());
        var accepted = service.accept(recipient.id(), issued.token());
        assertThat(accepted.bootstrap()).isNull();
        assertThat(accepted.membership().role()).isEqualTo("MEMBER");
        assertThat(accepted.membership().organizationId()).isEqualTo(organization.organizationId());
        assertThat(jdbc.queryForObject("SELECT status FROM organization_bootstraps WHERE account_id = ?", String.class, recipient.id())).isEqualTo("CANCELLED");
        code(() -> service.activate(recipient.id(), pending.id()), "bootstrap_unavailable");
        code(() -> service.accept(recipient.id(), issued.token()), "invalid_invitation");
        code(() -> service.preview(recipient.id(), issued.token()), "invalid_invitation");
        code(() -> service.invitations(recipient.id()), "forbidden");
        code(() -> service.issue(recipient.id(), owner.email()), "forbidden");
        code(() -> service.revoke(recipient.id(), issued.invitation().id()), "forbidden");
        code(() -> service.revoke(owner.id(), issued.invitation().id()), "invitation_unavailable");
        assertThat(service.invitations(owner.id()).invitations().getFirst().status()).isEqualTo("ACCEPTED");
    }

    @Test void wrongRecipientUnverifiedMissingRevokedExpiredAreNonDisclosing() {
        activate(owner);
        var issued = service.issue(owner.id(), recipient.email());
        code(() -> service.preview(owner.id(), issued.token()), "invalid_invitation");
        code(() -> service.accept(owner.id(), issued.token()), "invalid_invitation");
        for (String token : new String[] {null, "short", "A".repeat(43)}) {
            code(() -> service.preview(recipient.id(), token), "invalid_invitation");
            code(() -> service.accept(recipient.id(), token), "invalid_invitation");
        }
        jdbc.update("UPDATE accounts SET email_verified = FALSE WHERE id = ?", recipient.id());
        code(() -> service.accept(recipient.id(), issued.token()), "email_verification_required");
        code(() -> service.context(recipient.id()), "email_verification_required");
        jdbc.update("UPDATE accounts SET email_verified = TRUE WHERE id = ?", recipient.id());
        service.revoke(owner.id(), issued.invitation().id());
        service.revoke(owner.id(), issued.invitation().id());
        code(() -> service.accept(recipient.id(), issued.token()), "invalid_invitation");
        assertThat(service.invitations(owner.id()).invitations().getFirst().status()).isEqualTo("REVOKED");
        var expires = service.issue(owner.id(), recipient.email());
        clock.advance(Duration.ofDays(7).minusNanos(1));
        assertThat(service.preview(recipient.id(), expires.token())).isNotNull();
        clock.advance(Duration.ofNanos(1));
        code(() -> service.preview(recipient.id(), expires.token()), "invalid_invitation");
        code(() -> service.accept(recipient.id(), expires.token()), "invalid_invitation");
        assertThat(service.invitations(owner.id()).invitations()).anyMatch(i -> i.status().equals("EXPIRED"));
    }

    @Test void crossOrganizationOwnerAndSuspendedStatusesDeniedFreshly() {
        var organization = activate(owner).membership().organizationId();
        activate(recipient);
        var issued = service.issue(owner.id(), recipient.email());
        code(() -> service.revoke(recipient.id(), issued.invitation().id()), "invitation_not_found");
        code(() -> service.revoke(owner.id(), UUID.randomUUID()), "invitation_not_found");
        code(() -> service.accept(recipient.id(), issued.token()), "membership_exists");
        for (String status : List.of("SUSPENDED", "REVOKED")) {
            jdbc.update("UPDATE organization_memberships SET status = ? WHERE account_id = ?", status, owner.id());
            code(() -> service.context(owner.id()), "organization_unavailable");
            code(() -> service.issue(owner.id(), recipient.email()), "organization_unavailable");
            code(() -> service.revoke(owner.id(), issued.invitation().id()), "organization_unavailable");
            jdbc.update("UPDATE organization_memberships SET status = 'ACTIVE' WHERE account_id = ?", owner.id());
            jdbc.update("UPDATE organizations SET status = ? WHERE id = ?", status, organization);
            code(() -> service.invitations(owner.id()), "organization_unavailable");
            code(() -> service.accept(recipient.id(), issued.token()), "invalid_invitation");
            jdbc.update("UPDATE organizations SET status = 'ACTIVE' WHERE id = ?", organization);
        }
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", owner.id());
        code(() -> service.context(owner.id()), "unauthorized");
        code(() -> service.issue(owner.id(), recipient.email()), "unauthorized");
    }

    @Test void durableIssuanceBudgetAndListAreBoundedAndRevocationDoesNotResetBudget() {
        activate(owner);
        for (int i = 0; i < 10; i++) service.issue(owner.id(), recipient.email());
        service = new OnboardingService(jdbc, clock, transactions);
        code(() -> service.issue(owner.id(), recipient.email()), "rate_limited");
        for (var invitation : service.invitations(owner.id()).invitations()) service.revoke(owner.id(), invitation.id());
        code(() -> service.issue(owner.id(), recipient.email()), "rate_limited");
        clock.advance(Duration.ofHours(24));
        assertThat(service.issue(owner.id(), recipient.email())).isNotNull();
        // Simulate many owners sharing an org to exercise the organization-wide open budget.
        UUID organization = service.context(owner.id()).membership().organizationId();
        for (int i = 0; i < 100; i++) {
            UUID id = UUID.randomUUID();
            jdbc.update("INSERT INTO organization_invitations (id, organization_id, issued_by, email, token_digest, status, created_at, expires_at) VALUES (?, ?, ?, ?, ?, 'PENDING', ?, ?)",
                    id, organization, recipient.id(), recipient.email(), SessionStore.digest(id.toString()), clock.instant().atOffset(java.time.ZoneOffset.UTC), clock.instant().plus(Duration.ofDays(7)).atOffset(java.time.ZoneOffset.UTC));
        }
        assertThat(service.invitations(owner.id()).invitations()).hasSize(100);
        code(() -> service.issue(owner.id(), recipient.email()), "rate_limited");
    }

    @Test void auditFailureRollsBackEveryMutationIncludingActivationAndAcceptance() {
        var setup = service.bootstrap(owner.id(), "Original").bootstrap();
        rejectAudit(() -> service.activate(owner.id(), setup.id()));
        assertThat(count("organizations")).isZero();
        assertThat(count("organization_memberships")).isZero();
        assertThat(service.context(owner.id()).bootstrap()).isEqualTo(setup);
        rejectAudit(() -> service.bootstrap(owner.id(), "Changed"));
        rejectAudit(() -> service.cancel(owner.id(), setup.id()));
        assertThat(service.context(owner.id()).bootstrap()).isEqualTo(setup);
        service.activate(owner.id(), setup.id());
        rejectAudit(() -> service.issue(owner.id(), recipient.email()));
        assertThat(count("organization_invitations")).isZero();
        var issued = service.issue(owner.id(), recipient.email());
        var pending = service.bootstrap(recipient.id(), "Pending").bootstrap();
        rejectAudit(() -> service.revoke(owner.id(), issued.invitation().id()));
        rejectAudit(() -> service.accept(recipient.id(), issued.token()));
        assertThat(service.context(recipient.id()).bootstrap()).isEqualTo(pending);
        assertThat(service.invitations(owner.id()).invitations().getFirst().status()).isEqualTo("PENDING");
        assertThat(count("organization_memberships")).isEqualTo(1);
        assertThat(service.accept(recipient.id(), issued.token()).membership().role()).isEqualTo("MEMBER");
    }
    void rejectAudit(Runnable work) {
        // Existing rows satisfy the constraint; all new UUIDs violate it.
        jdbc.execute("ALTER TABLE onboarding_audit ADD CONSTRAINT test_audit_failure CHECK (occurred_at < TIMESTAMP WITH TIME ZONE '2026-10-03 00:00:01+00')");
        clock.advance(Duration.ofSeconds(2));
        try { assertThatThrownBy(work::run).isInstanceOf(org.springframework.dao.DataAccessException.class); }
        finally { jdbc.execute("ALTER TABLE onboarding_audit DROP CONSTRAINT test_audit_failure"); clock.advance(Duration.ofSeconds(-2)); }
    }

    @Test void concurrentActivationSameIdIsRetrySafeAndDatabaseRejectsSecondMembership() throws Exception {
        var id = service.bootstrap(owner.id(), "One").bootstrap().id();
        assertThat(race(() -> service.activate(owner.id(), id), () -> service.activate(owner.id(), id))).containsExactly(200, 200);
        assertThat(count("organizations")).isEqualTo(1);
        assertThat(count("organization_memberships")).isEqualTo(1);
        UUID org = service.context(owner.id()).membership().organizationId();
        assertThatThrownBy(() -> jdbc.update("INSERT INTO organization_memberships SELECT * FROM organization_memberships WHERE account_id = ?", owner.id()))
                .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
        assertThat(org).isNotNull();
    }

    @Test void lateAuditFailureRollsBackMembershipInvitationAndPendingCancellationTogether() {
        activate(owner);
        var setup = service.bootstrap(recipient.id(), "Retained");
        var issued = service.issue(owner.id(), recipient.email());
        int previousAuditCount = count("onboarding_audit");
        jdbc.execute("ALTER TABLE onboarding_audit ADD CONSTRAINT test_late_audit_failure CHECK (action <> 'INVITATION_ACCEPTED')");
        try {
            assertThatThrownBy(() -> service.accept(recipient.id(), issued.token())).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(service.context(recipient.id())).isEqualTo(setup);
            assertThat(count("organization_memberships")).isEqualTo(1);
            assertThat(count("onboarding_audit")).isEqualTo(previousAuditCount);
            assertThat(service.invitations(owner.id()).invitations().getFirst().status()).isEqualTo("PENDING");
        } finally { jdbc.execute("ALTER TABLE onboarding_audit DROP CONSTRAINT test_late_audit_failure"); }
        assertThat(service.accept(recipient.id(), issued.token()).membership().role()).isEqualTo("MEMBER");
    }

    @Test void lateActivationAuditFailureLeavesNoOrganizationOrMembership() {
        var setup = service.bootstrap(owner.id(), "Retained");
        jdbc.execute("ALTER TABLE onboarding_audit ADD CONSTRAINT test_late_activation_failure CHECK (action <> 'BOOTSTRAP_ACTIVATED')");
        try {
            assertThatThrownBy(() -> service.activate(owner.id(), setup.bootstrap().id())).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(service.context(owner.id())).isEqualTo(setup);
            assertThat(count("organizations")).isZero();
            assertThat(count("organization_memberships")).isZero();
            assertThat(count("onboarding_audit")).isEqualTo(1);
        } finally { jdbc.execute("ALTER TABLE onboarding_audit DROP CONSTRAINT test_late_activation_failure"); }
    }

    @Test void concurrentSetupSavesKeepSingleOriginalIdAndExpiry() throws Exception {
        assertThat(race(() -> service.bootstrap(owner.id(), "First"), () -> service.bootstrap(owner.id(), "Second"))).containsExactly(200, 200);
        assertThat(count("organization_bootstraps")).isEqualTo(1);
        assertThat(count("organizations")).isZero();
        var pending = service.context(owner.id()).bootstrap();
        assertThat(pending.expiresAt()).isEqualTo(clock.instant().plus(Duration.ofHours(24)));
        assertThat(jdbc.queryForList("SELECT subject_id FROM onboarding_audit", UUID.class)).containsOnly(pending.id());
    }

    @Test void activatedRetryAndMemberContextDenyRevokedStatusImmediately() {
        var setup = service.bootstrap(owner.id(), "Organization").bootstrap();
        service.activate(owner.id(), setup.id());
        var invitation = service.issue(owner.id(), recipient.email());
        service.accept(recipient.id(), invitation.token());
        for (String status : List.of("SUSPENDED", "REVOKED")) {
            jdbc.update("UPDATE organization_memberships SET status = ?", status);
            code(() -> service.context(recipient.id()), "organization_unavailable");
            code(() -> service.activate(owner.id(), setup.id()), "organization_unavailable");
            jdbc.update("UPDATE organization_memberships SET status = 'ACTIVE'");
            jdbc.update("UPDATE organizations SET status = ?", status);
            code(() -> service.context(recipient.id()), "organization_unavailable");
            code(() -> service.activate(owner.id(), setup.id()), "organization_unavailable");
            jdbc.update("UPDATE organizations SET status = 'ACTIVE'");
        }
    }

    @Test void concurrentAcceptHasOneWinnerAndActivationVersusAcceptCannotCreatePartialOrg() throws Exception {
        activate(owner);
        var issued = service.issue(owner.id(), recipient.email());
        assertThat(race(() -> service.accept(recipient.id(), issued.token()), () -> service.accept(recipient.id(), issued.token())))
                .containsExactlyInAnyOrder(200, 400);
        var other = verified("race@example.test");
        var invitation = service.issue(owner.id(), other.email());
        var setup = service.bootstrap(other.id(), "Racing").bootstrap();
        var results = race(() -> service.accept(other.id(), invitation.token()), () -> service.activate(other.id(), setup.id()));
        assertThat(results).containsExactlyInAnyOrder(200, 409);
        assertThat(count("organizations")).isEqualTo(service.context(other.id()).membership().role().equals("OWNER") ? 2 : 1);
        assertThat(count("organization_memberships")).isEqualTo(3);
    }

    @Test void concurrentBootstrapAndAcceptAndRevokeAreSerialized() throws Exception {
        activate(owner);
        var issued = service.issue(owner.id(), recipient.email());
        var results = race(() -> service.bootstrap(recipient.id(), "Racing"), () -> service.accept(recipient.id(), issued.token()));
        assertThat(results.get(1)).isEqualTo(200);
        assertThat(results.get(0)).isIn(200, 409);
        assertThat(service.context(recipient.id()).bootstrap()).isNull();
        assertThat(count("organizations")).isEqualTo(1);
        var other = verified("revoke@example.test");
        var invitation = service.issue(owner.id(), other.email());
        var revoked = race(() -> service.accept(other.id(), invitation.token()), () -> { service.revoke(owner.id(), invitation.invitation().id()); return null; });
        assertThat(revoked).isIn(List.of(200, 409), List.of(400, 200));
    }

    @Test void throttleBoundsAccountSourceGlobalAndReclaimsAtExactWindow() {
        var throttle = new TenantThrottle(clock);
        for (int i = 0; i < 20; i++) throttle.check(owner.id(), "source");
        code(() -> throttle.check(owner.id(), "other"), "rate_limited");
        clock.advance(Duration.ofMinutes(5));
        for (int i = 0; i < 80; i++) throttle.check(UUID.randomUUID(), "source");
        code(() -> throttle.check(UUID.randomUUID(), "source"), "rate_limited");
        clock.advance(Duration.ofMinutes(5));
        for (int i = 0; i < 200; i++) throttle.check(UUID.randomUUID(), "source" + i);
        code(() -> throttle.check(UUID.randomUUID(), "new"), "rate_limited");
        clock.advance(Duration.ofMinutes(5));
        assertThatCode(() -> throttle.check(owner.id(), "source")).doesNotThrowAnyException();
        var state = (java.util.Map<?, ?>) org.springframework.test.util.ReflectionTestUtils.getField(throttle, "buckets");
        assertThat(state).hasSize(3);
        assertThat(state.toString()).doesNotContain(owner.id().toString());
    }

    List<Integer> race(Supplier<?> first, Supplier<?> second) throws Exception {
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var a = executor.submit(() -> { assertThat(start.await(10, TimeUnit.SECONDS)).isTrue(); return status(first); });
            var b = executor.submit(() -> { assertThat(start.await(10, TimeUnit.SECONDS)).isTrue(); return status(second); });
            start.countDown();
            return List.of(a.get(10, TimeUnit.SECONDS), b.get(10, TimeUnit.SECONDS));
        }
    }
    int status(Supplier<?> work) { try { work.get(); return 200; } catch (ApiException error) { return error.status(); } }
}