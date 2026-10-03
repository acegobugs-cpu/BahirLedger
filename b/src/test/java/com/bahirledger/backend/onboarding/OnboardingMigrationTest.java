package com.bahirledger.backend.onboarding;

import java.util.UUID;
import com.bahirledger.backend.auth.AccountStore;
import org.flywaydb.core.Flyway;
import org.h2.jdbcx.JdbcDataSource;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.assertj.core.api.Assertions.*;

class OnboardingMigrationTest {
    @Test void fileDatabaseReopenRecoversPendingActivatedAndIssuedInvitation(@org.junit.jupiter.api.io.TempDir java.nio.file.Path directory) {
        var source = new JdbcDataSource();
        source.setURL("jdbc:h2:file:" + directory.resolve("onboarding").toAbsolutePath());
        source.setUser("sa");
        Flyway.configure().dataSource(source).load().migrate();
        var jdbc = new JdbcTemplate(source);
        var clock = new com.bahirledger.backend.AuthTestConfiguration.MutableClock();
        var service = new OnboardingService(jdbc, clock, new org.springframework.jdbc.support.JdbcTransactionManager(source));
        var accounts = new AccountStore(jdbc);
        var owner = accounts.create("owner@example.test", "Owner", "synthetic-hash");
        var recipient = accounts.create("recipient@example.test", "Recipient", "synthetic-hash");
        jdbc.update("UPDATE accounts SET email_verified = TRUE");
        var pending = service.bootstrap(recipient.id(), "Pending");
        var setup = service.bootstrap(owner.id(), "Durable").bootstrap();
        var activated = service.activate(owner.id(), setup.id());
        var invitation = service.issue(owner.id(), recipient.email());
        jdbc.execute("SHUTDOWN");

        var reopened = new JdbcDataSource();
        reopened.setURL(source.getURL());
        reopened.setUser("sa");
        assertThat(Flyway.configure().dataSource(reopened).load().migrate().migrationsExecuted).isZero();
        var restarted = new OnboardingService(new JdbcTemplate(reopened), clock, new org.springframework.jdbc.support.JdbcTransactionManager(reopened));
        assertThat(restarted.context(recipient.id())).isEqualTo(pending);
        assertThat(restarted.activate(owner.id(), setup.id())).isEqualTo(activated);
        assertThat(restarted.preview(recipient.id(), invitation.token()).organizationName()).isEqualTo("Durable");
        assertThat(restarted.accept(recipient.id(), invitation.token()).membership().organizationId()).isEqualTo(activated.membership().organizationId());
        new JdbcTemplate(reopened).execute("SHUTDOWN");
    }

    @Test void v3IsAdditiveAndDoesNotGrantExistingOrNewAccountsMembership() {
        var source = new JdbcDataSource();
        source.setURL("jdbc:h2:mem:" + UUID.randomUUID() + ";DB_CLOSE_DELAY=-1");
        source.setUser("sa");
        Flyway.configure().dataSource(source).target("2").load().migrate();
        var jdbc = new JdbcTemplate(source);
        var accounts = new AccountStore(jdbc);
        var user = accounts.create("existing@example.test", "Existing", "synthetic-hash");
        jdbc.update("UPDATE accounts SET email_verified = TRUE WHERE id = ?", user.id());
        var before = jdbc.queryForList("SELECT * FROM accounts");
        var flyway = Flyway.configure().dataSource(source).load();
        assertThat(flyway.migrate().migrationsExecuted).isEqualTo(1);
        assertThat(flyway.migrate().migrationsExecuted).isZero();
        assertThat(jdbc.queryForList("SELECT * FROM accounts")).isEqualTo(before);
        assertThat(accounts.create("new@example.test", "New", "synthetic-hash").emailVerified()).isFalse();
        for (String table : java.util.List.of("organizations", "organization_memberships", "organization_bootstraps", "organization_invitations", "onboarding_audit")) {
            assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM " + table, Integer.class)).isZero();
        }
    }
}