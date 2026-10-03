package com.bahirledger.backend.auth;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.stereotype.Component;

/** Separate, bounded five-minute budgets, including malformed bodies and successful requests. */
@Component
public class VerificationThrottle {
    private final Clock clock;
    private final Map<String, Bucket> buckets = new HashMap<>();

    public VerificationThrottle(Clock clock) { this.clock = clock; }

    public synchronized void checkSource(boolean confirm, String source) {
        String operation = confirm ? "confirm:" : "resend:";
        take(operation + "global", confirm ? 100 : 30);
        take(operation + "source:" + SessionStore.digest(source), confirm ? 20 : 10);
    }

    public synchronized void checkAccount(boolean confirm, UUID id) {
        take((confirm ? "confirm:" : "resend:") + SessionStore.digest(id.toString()), confirm ? 10 : 3);
    }

    private void take(String key, int limit) {
        Instant now = clock.instant();
        buckets.values().removeIf(bucket -> !now.isBefore(bucket.expiresAt));
        Bucket bucket = buckets.get(key);
        if (bucket == null) {
            if (buckets.size() >= 10_000) throw ApiException.throttled();
            bucket = new Bucket(now.plus(Duration.ofMinutes(5)));
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