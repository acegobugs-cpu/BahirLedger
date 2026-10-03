package com.bahirledger.backend.auth;

import java.time.Duration;
import java.util.Map;
import java.util.UUID;

import com.bahirledger.backend.AuthTestConfiguration.MutableClock;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

class AuthStateTest {
    @Test
    void sessionsStoreOnlyDigestsAreBoundedAndExpiredCapacityIsReclaimed() {
        var clock = new MutableClock();
        var store = new SessionStore(clock);
        UUID id = UUID.randomUUID();
        var issued = store.issue(id);
        Map<?, ?> state = (Map<?, ?>) ReflectionTestUtils.getField(store, "sessions");
        assertThat(state).isNotNull();
        assertThat(state.containsKey(issued.accessToken())).isFalse();
        assertThat(state.containsKey(SessionStore.digest(issued.accessToken()))).isTrue();
        assertThat(state.toString()).doesNotContain(issued.accessToken());
        assertThat(new SessionStore(clock).findUser(SessionStore.digest(issued.accessToken()))).isEmpty();
        for (int i = 1; i < 10_000; i++) store.issue(id);
        assertThatThrownBy(() -> store.issue(id)).isInstanceOf(ApiException.class)
                .satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(429));
        assertThat(state).hasSize(10_000);
        clock.advance(Duration.ofMinutes(30));
        assertThat(store.findUser(SessionStore.digest(issued.accessToken()))).isEmpty();
        assertThatCode(() -> store.issue(id)).doesNotThrowAnyException();
        assertThat(state).hasSize(1);
    }

    @Test
    void throttleHasGlobalLimitBoundedKeyStateAndWindowReclamation() {
        var clock = new MutableClock();
        var throttle = new LoginThrottle(clock);
        for (int i = 0; i < 100; i++) throttle.checkSource("192.0.2." + i);
        assertThatThrownBy(() -> throttle.checkSource("new-source")).isInstanceOf(ApiException.class);
        clock.advance(Duration.ofMinutes(5));
        for (int i = 0; i < 10_000; i++) throttle.checkEmail(i + "@example.test");
        assertThatThrownBy(() -> throttle.checkEmail("overflow@example.test")).isInstanceOf(ApiException.class);
        Map<?, ?> state = (Map<?, ?>) ReflectionTestUtils.getField(throttle, "buckets");
        assertThat(state).hasSize(10_000);
        assertThat(state.toString()).doesNotContain("@example.test");
        clock.advance(Duration.ofMinutes(5));
        assertThatCode(() -> throttle.checkEmail("overflow@example.test")).doesNotThrowAnyException();
        assertThat(state).hasSize(1);
    }

    @Test
    void unknownUsersStillRunPasswordMatchAndNoSessionIsIssued() {
        var accounts = mock(AccountStore.class);
        var encoder = mock(PasswordEncoder.class);
        var sessions = mock(SessionStore.class);
        when(encoder.encode(anyString())).thenReturn("synthetic-dummy-hash");
        when(accounts.findByEmail("unknown@example.test")).thenReturn(java.util.Optional.empty());
        var service = new AuthService(accounts, encoder, sessions, new LoginThrottle(new MutableClock()));
        assertThatThrownBy(() -> service.login(new LoginRequest("unknown@example.test", "synthetic-test-password")))
                .isInstanceOf(ApiException.class);
        verify(encoder).matches("synthetic-test-password", "synthetic-dummy-hash");
        verifyNoInteractions(sessions);
    }
}