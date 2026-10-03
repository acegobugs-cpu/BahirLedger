package com.bahirledger.backend.auth;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.UUID;
import java.util.concurrent.Semaphore;

import com.bahirledger.backend.auth.mail.VerificationMailSender;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class EmailVerificationService {
    public static final Duration LIFETIME = Duration.ofMinutes(30);
    public static final Duration COOLDOWN = Duration.ofMinutes(1);
    private final JdbcTemplate jdbc;
    private final Clock clock;
    private final VerificationMailSender mail;
    private final TransactionTemplate transaction;
    private final SecureRandom random = new SecureRandom();
    private final Semaphore deliveryWork = new Semaphore(4);

    public EmailVerificationService(JdbcTemplate jdbc, Clock clock, VerificationMailSender mail,
            PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.mail = mail;
        this.transaction = new TransactionTemplate(transactions);
        this.transaction.setTimeout(30);
    }

    public void resend(UUID accountId) {
        if (!deliveryWork.tryAcquire()) throw ApiException.throttled();
        try {
            boolean accepted = Boolean.TRUE.equals(transaction.execute(status -> {
                UserView user = lockAccount(accountId);
                if (user.emailVerified()) return true;
                // PostgreSQL/H2 timestamps have microsecond precision. Avoid database rounding
                // nanosecond clocks upward and making the exact persisted cooldown boundary drift.
                var now = clock.instant().truncatedTo(ChronoUnit.MICROS);
                var nextSend = jdbc.query("SELECT next_send_at FROM email_verifications WHERE account_id = ?",
                        (rs, row) -> rs.getObject(1, OffsetDateTime.class).toInstant(), accountId);
                if (!nextSend.isEmpty() && now.isBefore(nextSend.getFirst())) throw ApiException.throttled();

                byte[] bytes = new byte[32];
                random.nextBytes(bytes);
                String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
                jdbc.update("DELETE FROM email_verifications WHERE account_id = ?", accountId);
                jdbc.update("INSERT INTO email_verifications (account_id, token_digest, expires_at, next_send_at) VALUES (?, ?, ?, ?)",
                        accountId, SessionStore.digest(token), now.plus(LIFETIME).atOffset(ZoneOffset.UTC),
                        now.plus(COOLDOWN).atOffset(ZoneOffset.UTC));
                try {
                    // Synchronous delivery under the account lock serializes resend vs confirmation.
                    mail.send(user.email(), token);
                    return true;
                } catch (RuntimeException unavailable) {
                    // Commit rotation and cooldown even on delivery failure; never log mail exceptions.
                    clearToken(accountId);
                    return false;
                }
            }));
            if (!accepted) throw ApiException.unavailable();
        } finally {
            deliveryWork.release();
        }
    }

    public UserView confirm(UUID accountId, String token) {
        if (token == null || !token.matches("[A-Za-z0-9_-]{43}")) throw ApiException.invalidVerificationToken();
        return transaction.execute(status -> {
            UserView user = lockAccount(accountId);
            var expiries = jdbc.query("SELECT expires_at FROM email_verifications WHERE account_id = ? AND token_digest = ?",
                    (rs, row) -> rs.getObject(1, OffsetDateTime.class).toInstant(), accountId, SessionStore.digest(token));
            if (user.emailVerified() || expiries.isEmpty() || !clock.instant().isBefore(expiries.getFirst())) {
                throw ApiException.invalidVerificationToken();
            }
            clearToken(accountId);
            jdbc.update("UPDATE accounts SET email_verified = TRUE WHERE id = ?", accountId);
            return new UserView(user.id(), user.email(), user.displayName(), true);
        });
    }

    private UserView lockAccount(UUID accountId) {
        return jdbc.query("SELECT id, email, display_name, email_verified FROM accounts WHERE id = ? AND active = TRUE FOR UPDATE",
                (rs, row) -> new UserView(rs.getObject("id", UUID.class), rs.getString("email"),
                        rs.getString("display_name"), rs.getBoolean("email_verified")), accountId)
                .stream().findFirst().orElseThrow(ApiException::unauthorized);
    }

    private void clearToken(UUID accountId) {
        jdbc.update("UPDATE email_verifications SET token_digest = NULL, expires_at = NULL WHERE account_id = ?", accountId);
    }
}