package com.bahirledger.backend.auth;

import java.util.UUID;

import org.flywaydb.core.Flyway;
import org.h2.jdbcx.JdbcDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.assertj.core.api.Assertions.assertThat;

class EmailVerificationMigrationTest {
    @Test
    void v2PreservesV1AccountsAndDefaultsOldAndNewAccountsToPending() {
        var source = new JdbcDataSource();
        source.setURL("jdbc:h2:mem:" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1");
        source.setUser("sa");
        Flyway.configure().dataSource(source).target("1").load().migrate();
        var jdbc = new JdbcTemplate(source);
        UUID active = UUID.randomUUID();
        UUID inactive = UUID.randomUUID();
        String hash = "$2a$12$" + "a".repeat(53);
        jdbc.update("INSERT INTO accounts VALUES (?, ?, ?, ?, TRUE)", active, "existing@example.test", "Existing", hash);
        jdbc.update("INSERT INTO accounts VALUES (?, ?, ?, ?, FALSE)", inactive, "inactive@example.test", "Inactive", hash);
        var before = jdbc.queryForList("SELECT * FROM accounts ORDER BY email");
        var flyway = Flyway.configure().dataSource(source).target("2").load();
        assertThat(flyway.migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
        assertThat(jdbc.queryForList("SELECT id, email, display_name, password_hash, active FROM accounts ORDER BY email")).isEqualTo(before);
        assertThat(jdbc.queryForList("SELECT email_verified FROM accounts", Boolean.class)).containsExactly(false, false);
        var created = new AccountStore(jdbc).create("new@example.test", "New", hash);
        assertThat(created.emailVerified()).isFalse();
        assertThat(jdbc.queryForObject("SELECT email_verified FROM accounts WHERE id = ?", Boolean.class, created.id())).isFalse();
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM email_verifications", Integer.class)).isZero();
    }
}