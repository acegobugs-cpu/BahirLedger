package com.bahirledger.backend.auth;

import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import com.bahirledger.backend.AuthTestConfiguration;
import com.bahirledger.backend.MailCaptureTestConfiguration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.*;

@SpringBootTest
@Import({AuthTestConfiguration.class, MailCaptureTestConfiguration.class})
class EmailVerificationStateTest {
    @Autowired AccountStore accounts;
    @Autowired EmailVerificationService verification;
    @Autowired JdbcTemplate jdbc;
    @Autowired PlatformTransactionManager transactions;
    @Autowired AuthTestConfiguration.MutableClock clock;
    @Autowired MailCaptureTestConfiguration.CapturingMailSender mail;
    private UserView user;

    @BeforeEach
    void reset() {
        clock.advance(Duration.between(clock.instant(), clock.instant()
            .truncatedTo(java.time.temporal.ChronoUnit.SECONDS).plusSeconds(31 * 60)));
        jdbc.update("DELETE FROM accounts");
        mail.reset();
        user = accounts.create("state@example.test", "State", "synthetic-hash");
    }

    @Test
    void onlyDigestIsPersistedAndConsumptionUpdatesAccountAtomically() {
        verification.resend(user.id());
        String token = mail.deliveries.getFirst().token();
        var row = jdbc.queryForMap("SELECT * FROM email_verifications WHERE account_id = ?", user.id());
        assertThat(row.get("TOKEN_DIGEST")).isEqualTo(SessionStore.digest(token));
        assertThat(row.toString()).doesNotContain(token);
        assertThat(jdbc.queryForList("SELECT * FROM accounts").toString()).doesNotContain(token);
        var other = accounts.create("other@example.test", "Other", "synthetic-hash");
        invalid(() -> verification.confirm(other.id(), token));
        assertThat(verification.confirm(user.id(), token).emailVerified()).isTrue();
        assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isTrue();
        assertThat(jdbc.queryForMap("SELECT * FROM email_verifications").get("TOKEN_DIGEST")).isNull();
        invalid(() -> verification.confirm(user.id(), token));
        verification.resend(user.id());
        assertThat(mail.deliveries).hasSize(1);
    }

    @Test
    void expiryIsExclusiveAtExactlyThirtyMinutes() {
        verification.resend(user.id());
        String token = mail.deliveries.getFirst().token();
        clock.advance(Duration.ofMinutes(30));
        invalid(() -> verification.confirm(user.id(), token));
        assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isFalse();
        verification.resend(user.id());
        clock.advance(Duration.ofMinutes(30).minusNanos(1));
        assertThat(verification.confirm(user.id(), mail.deliveries.getLast().token()).emailVerified()).isTrue();
    }

    @Test
    void resendRotatesAndPersistentCooldownSurvivesNewServiceInstance() {
        verification.resend(user.id());
        String old = mail.deliveries.getFirst().token();
        var restarted = new EmailVerificationService(jdbc, clock, mail, transactions);
        assertThatThrownBy(() -> restarted.resend(user.id())).isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(429));
        clock.advance(Duration.ofMinutes(1));
        restarted.resend(user.id());
        String current = mail.deliveries.getLast().token();
        assertThat(current).isNotEqualTo(old);
        invalid(() -> verification.confirm(user.id(), old));
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM email_verifications", Integer.class)).isEqualTo(1);
        assertThat(verification.confirm(user.id(), current).emailVerified()).isTrue();
    }

    @Test
    void failedDeliveryInvalidatesPreviousTokenAndPersistsCooldownWithoutVerification() {
        verification.resend(user.id());
        String old = mail.deliveries.getFirst().token();
        clock.advance(Duration.ofMinutes(1));
        mail.fail = true;
        assertThatThrownBy(() -> verification.resend(user.id())).isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(503));
        invalid(() -> verification.confirm(user.id(), old));
        assertThat(jdbc.queryForMap("SELECT * FROM email_verifications").get("TOKEN_DIGEST")).isNull();
        assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isFalse();
        assertThatThrownBy(() -> new EmailVerificationService(jdbc, clock, mail, transactions).resend(user.id()))
                .isInstanceOf(ApiException.class).satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(429));
    }

    @Test
    void failedAccountUpdateRollsBackTokenConsumption() {
        verification.resend(user.id());
        String token = mail.deliveries.getFirst().token();
        jdbc.execute("ALTER TABLE accounts ADD CONSTRAINT test_block_verification CHECK (email_verified = FALSE)");
        try {
            assertThatThrownBy(() -> verification.confirm(user.id(), token)).isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(jdbc.queryForObject("SELECT token_digest FROM email_verifications WHERE account_id = ?", String.class, user.id()))
                    .isEqualTo(SessionStore.digest(token));
            assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isFalse();
        } finally {
            jdbc.execute("ALTER TABLE accounts DROP CONSTRAINT test_block_verification");
        }
        assertThat(verification.confirm(user.id(), token).emailVerified()).isTrue();
    }

    @Test
    void nanosecondClockDoesNotRoundPersistentCooldownUpward() {
        clock.advance(Duration.ofNanos(999));
        verification.resend(user.id());
        clock.advance(Duration.ofMinutes(1));
        assertThatCode(() -> verification.resend(user.id())).doesNotThrowAnyException();
        assertThat(mail.deliveries).hasSize(2);
    }

    @Test
    void deliveryWorkIsBoundedWithoutQueuingExcessRequests() throws Exception {
        var entered = new CountDownLatch(4);
        var release = new CountDownLatch(1);
        mail.beforeSend = () -> { entered.countDown(); await(release); };
        try (var executor = Executors.newFixedThreadPool(4)) {
            var pending = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 4; i++) {
                var account = accounts.create("bounded" + i + "@example.test", "Bounded", "synthetic-hash");
                pending.add(executor.submit(() -> verification.resend(account.id())));
            }
            try {
                await(entered);
                assertThat(resendStatus(verification)).isEqualTo(429);
            } finally {
                release.countDown();
            }
            for (var future : pending) future.get(10, TimeUnit.SECONDS);
        } finally {
            release.countDown();
        }
        assertThat(mail.deliveries).hasSize(4);
    }

    @Test
    void concurrentConfirmationsHaveExactlyOneWinner() throws Exception {
        verification.resend(user.id());
        String token = mail.deliveries.getFirst().token();
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> { await(start); return confirmationStatus(token); });
            var second = executor.submit(() -> { await(start); return confirmationStatus(token); });
            start.countDown();
            assertThat(List.of(first.get(10, TimeUnit.SECONDS), second.get(10, TimeUnit.SECONDS)))
                    .containsExactlyInAnyOrder(200, 400);
        }
        assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isTrue();
    }

    @Test
    void concurrentResendsDeliverOnlyOnceAcrossServiceInstances() throws Exception {
        var secondService = new EmailVerificationService(jdbc, clock, mail, transactions);
        var start = new CountDownLatch(1);
        try (var executor = Executors.newFixedThreadPool(2)) {
            var first = executor.submit(() -> { await(start); return resendStatus(verification); });
            var second = executor.submit(() -> { await(start); return resendStatus(secondService); });
            start.countDown();
            assertThat(List.of(first.get(10, TimeUnit.SECONDS), second.get(10, TimeUnit.SECONDS)))
                    .containsExactlyInAnyOrder(204, 429);
        }
        assertThat(mail.deliveries).hasSize(1);
    }

    @Test
    void resendHoldingLockMakesOldTokenConfirmationWaitThenFail() throws Exception {
        verification.resend(user.id());
        String old = mail.deliveries.getFirst().token();
        clock.advance(Duration.ofMinutes(1));
        var sending = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        mail.beforeSend = () -> { sending.countDown(); await(release); };
        try (var executor = Executors.newFixedThreadPool(2)) {
            var resend = executor.submit(() -> resendStatus(verification));
            await(sending);
            var started = new CountDownLatch(1);
            var confirm = executor.submit(() -> { started.countDown(); return confirmationStatus(old); });
            try {
                await(started);
                assertThatThrownBy(() -> confirm.get(100, TimeUnit.MILLISECONDS))
                    .isInstanceOf(java.util.concurrent.TimeoutException.class);
            } finally {
                release.countDown();
            }
            assertThat(resend.get(10, TimeUnit.SECONDS)).isEqualTo(204);
            assertThat(confirm.get(10, TimeUnit.SECONDS)).isEqualTo(400);
        } finally {
            release.countDown();
        }
        assertThat(verification.confirm(user.id(), mail.deliveries.getLast().token()).emailVerified()).isTrue();
    }

    @Test
    void deactivatedAccountCannotSendOrConfirmEvenDirectly() {
        verification.resend(user.id());
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", user.id());
        assertThatThrownBy(() -> verification.confirm(user.id(), mail.deliveries.getFirst().token()))
                .isInstanceOf(ApiException.class).satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(401));
        assertThat(resendStatus(verification)).isEqualTo(401);
        assertThat(mail.deliveries).hasSize(1);
    }

    @Test
    void throttlesBoundGlobalAndAccountStateAndReclaimWindows() {
        var throttle = new VerificationThrottle(clock);
        for (int i = 0; i < 100; i++) throttle.checkSource(true, "source-" + i);
        assertThatThrownBy(() -> throttle.checkSource(true, "overflow")).isInstanceOf(ApiException.class);
        for (int i = 0; i < 30; i++) throttle.checkSource(false, "source-" + i);
        assertThatThrownBy(() -> throttle.checkSource(false, "overflow")).isInstanceOf(ApiException.class);
        clock.advance(Duration.ofMinutes(5));
        for (int i = 0; i < 10_000; i++) throttle.checkAccount(true, java.util.UUID.randomUUID());
        assertThatThrownBy(() -> throttle.checkAccount(false, user.id())).isInstanceOf(ApiException.class);
        Map<?, ?> state = (Map<?, ?>) ReflectionTestUtils.getField(throttle, "buckets");
        assertThat(state).hasSize(10_000);
        clock.advance(Duration.ofMinutes(5));
        throttle.checkAccount(false, user.id());
        assertThat(state).hasSize(1);
        assertThat(state.toString()).doesNotContain(user.id().toString());
    }

    private int confirmationStatus(String token) {
        try { verification.confirm(user.id(), token); return 200; }
        catch (ApiException error) { return error.status(); }
    }

    private int resendStatus(EmailVerificationService service) {
        try { service.resend(user.id()); return 204; }
        catch (ApiException error) { return error.status(); }
    }

    private static void invalid(Runnable action) {
        assertThatThrownBy(action::run).isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).code()).isEqualTo("invalid_verification_token"));
    }

    private static void await(CountDownLatch latch) {
        try { assertThat(latch.await(10, TimeUnit.SECONDS)).isTrue(); }
        catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new AssertionError(interrupted); }
    }
}