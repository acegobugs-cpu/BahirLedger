package com.bahirledger.backend.auth;

import java.nio.charset.StandardCharsets;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
        @NotBlank @Email @Size(max = 254) String email,
        @NotBlank @Size(max = 72) String displayName,
        @NotBlank @Size(max = 72) String password) {
    public RegisterRequest {
        email = AccountStore.normalizeEmail(email);
    }

    @AssertTrue
    public boolean isPasswordWithinBcryptLimit() {
        return password == null || password.getBytes(StandardCharsets.UTF_8).length <= 72;
    }

    @Override
    public String toString() { return "RegisterRequest[REDACTED]"; }
}