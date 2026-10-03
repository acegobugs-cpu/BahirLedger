package com.bahirledger.backend.auth;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;

import org.springframework.stereotype.Component;

/** Fixed windows; counts successes too. Saturation denies rather than evicting live limits. */
@Component
public class LoginThrottle {
    private static final Duration WINDOW = Duration.ofMinutes(5);
    private static final int MAX_KEYS = 10_000;
    private final Map<String, Bucket> buckets = new HashMap<>();
    private final Clock clock;

    public LoginThrottle(Clock clock) { this.clock = clock; }

    public synchronized void checkSource(String remoteAddress) {
        take("global", 100);
        take("ip:" + SessionStore.digest(remoteAddress), 20);
    }

    public synchronized void checkEmail(String normalizedEmail) {
        take("email:" + SessionStore.digest(normalizedEmail), 5);
    }

    private void take(String key, int limit) {
        Instant now = clock.instant();
        buckets.values().removeIf(bucket -> !now.isBefore(bucket.expiresAt));
        Bucket bucket = buckets.get(key);
        if (bucket == null) {
            if (buckets.size() >= MAX_KEYS) throw ApiException.throttled();
            bucket = new Bucket(now.plus(WINDOW));
            buckets.put(key, bucket);
        }
        if (bucket.count >= limit) throw ApiException.throttled();
        bucket.count++;
    }

    private static final class Bucket {
        private final Instant expiresAt;
        private int count;
        private Bucket(Instant expiresAt) { this.expiresAt = expiresAt; }
    }
}