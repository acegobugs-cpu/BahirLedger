package com.bahirledger.backend.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.stereotype.Component;

@Component
public class SessionStore {
    public static final Duration LIFETIME = Duration.ofMinutes(30);
    private static final int MAX_SESSIONS = 10_000;
    private final Map<String, Session> sessions = new HashMap<>();
    private final SecureRandom random = new SecureRandom();
    private final Clock clock;

    public SessionStore(Clock clock) { this.clock = clock; }

    public synchronized IssuedSession issue(UUID userId) {
        purgeExpired();
        if (sessions.size() >= MAX_SESSIONS) throw ApiException.throttled();
        byte[] bytes = new byte[32];
        String token;
        String digest;
        do {
            random.nextBytes(bytes);
            token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
            digest = digest(token);
        } while (sessions.containsKey(digest));
        Instant expiresAt = clock.instant().plus(LIFETIME);
        sessions.put(digest, new Session(userId, expiresAt));
        return new IssuedSession(token, expiresAt);
    }

    public synchronized Optional<UUID> findUser(String digest) {
        purgeExpired();
        return Optional.ofNullable(sessions.get(digest)).map(Session::userId);
    }

    public synchronized void revoke(String digest) { sessions.remove(digest); }

    private void purgeExpired() {
        Instant now = clock.instant();
        sessions.values().removeIf(session -> !now.isBefore(session.expiresAt()));
    }

    public static String digest(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 unavailable");
        }
    }

    private record Session(UUID userId, Instant expiresAt) {}

    /** Only transient response data contains the raw token; never stored or logged. */
    public record IssuedSession(String accessToken, Instant expiresAt) {
        @Override public String toString() { return "IssuedSession[REDACTED]"; }
    }
}