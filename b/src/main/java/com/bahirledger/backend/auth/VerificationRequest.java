package com.bahirledger.backend.auth;

/** Transient credential; never include it in diagnostics or return it in JSON. */
public record VerificationRequest(String token) {
    @Override public String toString() { return "VerificationRequest[REDACTED]"; }
}