package com.bahirledger.backend.auth;

import java.util.UUID;
import java.util.concurrent.Semaphore;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
public class AuthService {
    private final AccountStore accounts;
    private final PasswordEncoder encoder;
    private final SessionStore sessions;
    private final LoginThrottle throttle;
    private final Semaphore passwordWork = new Semaphore(4);
    private final String dummyHash;

    public AuthService(AccountStore accounts, PasswordEncoder encoder, SessionStore sessions, LoginThrottle throttle) {
        this.accounts = accounts;
        this.encoder = encoder;
        this.sessions = sessions;
        this.throttle = throttle;
        dummyHash = encoder.encode(UUID.randomUUID().toString());
    }

    public RegisterResponse register(RegisterRequest request) {
        throttle.checkEmail(request.email());
        if (!passwordWork.tryAcquire()) throw ApiException.throttled();
        try {
            var account = accounts.findByEmail(request.email());
            if (account.isPresent()) throw ApiException.conflict();
            var user = accounts.create(request.email(), request.displayName(), encoder.encode(request.password()));
            var issued = sessions.issue(user.id());
            return new RegisterResponse(issued.accessToken(), issued.expiresAt(), user);
        } finally {
            passwordWork.release();
        }
    }

    public LoginResponse login(LoginRequest request) {
        throttle.checkEmail(request.email());
        if (!passwordWork.tryAcquire()) throw ApiException.throttled();
        try {
            var account = accounts.findByEmail(request.email());
            boolean matches = encoder.matches(request.password(), account.map(AccountStore.Account::passwordHash).orElse(dummyHash));
            if (!matches || account.isEmpty() || !account.get().active()) throw ApiException.invalidCredentials();
            var user = account.get().user();
            var issued = sessions.issue(user.id());
            return new LoginResponse(issued.accessToken(), issued.expiresAt(), user);
        } finally {
            passwordWork.release();
        }
    }

    public record LoginResponse(String accessToken, java.time.Instant expiresAt, UserView user) {
        @Override public String toString() { return "LoginResponse[REDACTED]"; }
    }

    public record RegisterResponse(String accessToken, java.time.Instant expiresAt, UserView user) {
        @Override public String toString() { return "RegisterResponse[REDACTED]"; }
    }
}