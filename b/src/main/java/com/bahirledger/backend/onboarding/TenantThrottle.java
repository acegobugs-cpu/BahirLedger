package com.bahirledger.backend.onboarding;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import com.bahirledger.backend.auth.ApiException;
import com.bahirledger.backend.auth.SessionStore;
import org.springframework.stereotype.Component;

/** Combined mutation/preview budgets; direct peer only, never forwarded headers. */
@Component
public class TenantThrottle {
    private final Clock clock;
    private final Map<String, Bucket> buckets = new HashMap<>();
    public TenantThrottle(Clock clock) { this.clock = clock; }
    public synchronized void check(UUID account, String source) {
        take("global", 200);
        take("source:" + SessionStore.digest(source), 80);
        take("account:" + SessionStore.digest(account.toString()), 20);
    }
    private void take(String key, int limit) {
        Instant now = clock.instant();
        buckets.values().removeIf(value -> !now.isBefore(value.expiresAt));
        var bucket = buckets.get(key);
        if (bucket == null) {
            if (buckets.size() >= 10_000) throw ApiException.tenantThrottled();
            bucket = new Bucket(now.plus(Duration.ofMinutes(5)));
            buckets.put(key, bucket);
        }
        if (bucket.count >= limit) throw ApiException.tenantThrottled();
        bucket.count++;
    }
    private static final class Bucket {
        private final Instant expiresAt;
        private int count;
        private Bucket(Instant expiresAt) { this.expiresAt = expiresAt; }
    }
}