package com.bahirledger.backend.auth;

import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class AccountStore {
    private final JdbcTemplate jdbc;

    public AccountStore(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public static String normalizeEmail(String email) {
        return email == null ? null : email.strip().toLowerCase(Locale.ROOT);
    }

    public Optional<Account> findByEmail(String email) {
        return jdbc.query("SELECT id, email, display_name, password_hash, active, email_verified FROM accounts WHERE email = ?",
                (rs, row) -> new Account(new UserView(rs.getObject("id", UUID.class), rs.getString("email"),
                rs.getString("display_name"), rs.getBoolean("email_verified")), rs.getString("password_hash"), rs.getBoolean("active")),
                normalizeEmail(email)).stream().findFirst();
    }

    public Optional<UserView> findActiveUser(UUID id) {
        return jdbc.query("SELECT id, email, display_name, email_verified FROM accounts WHERE id = ? AND active = TRUE",
                (rs, row) -> new UserView(rs.getObject("id", UUID.class), rs.getString("email"),
                rs.getString("display_name"), rs.getBoolean("email_verified")), id).stream().findFirst();
    }

    /** Internal provisioning only. The caller must supply an encoded password. */
    public UserView create(String email, String displayName, String encodedPassword) {
        var user = new UserView(UUID.randomUUID(), normalizeEmail(email), displayName, false);
        jdbc.update("INSERT INTO accounts (id, email, display_name, password_hash, active) VALUES (?, ?, ?, ?, TRUE)",
                user.id(), user.email(), user.displayName(), encodedPassword);
        return user;
    }

    // No generated toString(): never include the encoded password in diagnostic output.
    public static final class Account {
        private final UserView user;
        private final String passwordHash;
        private final boolean active;

        Account(UserView user, String passwordHash, boolean active) {
            this.user = user;
            this.passwordHash = passwordHash;
            this.active = active;
        }

        public UserView user() { return user; }
        public String passwordHash() { return passwordHash; }
        public boolean active() { return active; }
    }
}