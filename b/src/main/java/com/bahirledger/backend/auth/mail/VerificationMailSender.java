package com.bahirledger.backend.auth.mail;

/** Synchronous acceptance, not a guarantee of inbox delivery. Never log arguments or mail exceptions. */
@FunctionalInterface
public interface VerificationMailSender {
    void send(String email, String token);
}