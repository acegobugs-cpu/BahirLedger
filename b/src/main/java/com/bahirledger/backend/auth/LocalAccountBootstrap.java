package com.bahirledger.backend.auth;

import jakarta.validation.Validator;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/** Opt-in, create-only provisioning; never log the supplied identity or password. */
@Component
@Profile("local")
public class LocalAccountBootstrap implements ApplicationRunner {
    private final Environment environment;
    private final AccountStore accounts;
    private final PasswordEncoder encoder;
    private final Validator validator;

    public LocalAccountBootstrap(Environment environment, AccountStore accounts, PasswordEncoder encoder, Validator validator) {
        this.environment = environment;
        this.accounts = accounts;
        this.encoder = encoder;
        this.validator = validator;
    }

    @Override
    public void run(ApplicationArguments args) {
        String email = environment.getProperty("BAHIRLEDGER_DEV_EMAIL");
        String password = environment.getProperty("BAHIRLEDGER_DEV_PASSWORD");
        String name = environment.getProperty("BAHIRLEDGER_DEV_NAME");
        if (email == null && password == null && name == null) return;
        if (!validator.validate(new LoginRequest(email, password)).isEmpty()
                || name == null || name.isBlank() || name.strip().length() > 120) {
            throw new IllegalStateException("Local provisioning requires valid BAHIRLEDGER_DEV_EMAIL, BAHIRLEDGER_DEV_PASSWORD and BAHIRLEDGER_DEV_NAME.");
        }
        if (accounts.findByEmail(email).isPresent()) return;
        try {
            accounts.create(email, name.strip(), encoder.encode(password));
        } catch (DuplicateKeyException ignored) {
            // Concurrent provisioning won the unique email constraint. Never overwrite it.
        }
    }
}