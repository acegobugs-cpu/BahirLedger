package com.bahirledger.backend.auth;

import com.bahirledger.backend.AuthTestConfiguration;
import jakarta.validation.Validator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.DefaultApplicationArguments;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.env.MockEnvironment;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.*;

@SpringBootTest
@Import(AuthTestConfiguration.class)
class AccountProvisioningTest {
    @Autowired AccountStore accounts;
    @Autowired PasswordEncoder encoder;
    @Autowired Validator validator;
    @Autowired JdbcTemplate jdbc;

    @BeforeEach
    void clearAccounts() { jdbc.update("DELETE FROM accounts"); }

    private void bootstrap(MockEnvironment environment) {
        new LocalAccountBootstrap(environment, accounts, encoder, validator).run(new DefaultApplicationArguments());
    }

    @Test
    void bootstrapIsOptInAndPartialConfigurationFailsClosed() {
        bootstrap(new MockEnvironment());
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM accounts", Integer.class)).isZero();
        assertThatThrownBy(() -> bootstrap(new MockEnvironment().withProperty("BAHIRLEDGER_DEV_EMAIL", "test@example.test")))
                .isInstanceOf(IllegalStateException.class);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM accounts", Integer.class)).isZero();
    }

    @Test
    void bootstrapNormalizesPersistsAndNeverOverwritesExistingAccount() {
        var environment = new MockEnvironment().withProperty("BAHIRLEDGER_DEV_EMAIL", " LOCAL@Example.Test ")
                .withProperty("BAHIRLEDGER_DEV_PASSWORD", "Synthetic-bootstrap-test-password!")
                .withProperty("BAHIRLEDGER_DEV_NAME", " Local Person ");
        bootstrap(environment);
        var first = accounts.findByEmail("local@example.test").orElseThrow();
        assertThat(first.user().displayName()).isEqualTo("Local Person");
        assertThat(first.user().emailVerified()).isFalse();
        assertThat(first.passwordHash()).startsWith("$2a$12$");
        assertThat(encoder.matches("Synthetic-bootstrap-test-password!", first.passwordHash())).isTrue();
        environment.setProperty("BAHIRLEDGER_DEV_PASSWORD", "Different-synthetic-test-password!");
        environment.setProperty("BAHIRLEDGER_DEV_NAME", "Changed Person");
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", first.user().id());
        bootstrap(environment);
        // New repository instance reads the same durable row, not an in-memory account cache.
        var second = new AccountStore(jdbc).findByEmail("local@example.test").orElseThrow();
        assertThat(second.user()).isEqualTo(first.user());
        assertThat(second.passwordHash()).isEqualTo(first.passwordHash());
        assertThat(second.active()).isFalse();
    }

    @Test
    void databaseEnforcesUniqueNormalizedEmails() {
        String hash = encoder.encode("Synthetic-duplicate-test-password!");
        var first = accounts.create(" Duplicate@Example.Test ", "Person", hash);
        assertThatThrownBy(() -> accounts.create("duplicate@example.test", "Other Person", hash))
                .isInstanceOf(DuplicateKeyException.class);
        assertThat(accounts.findByEmail("DUPLICATE@example.test").orElseThrow().user()).isEqualTo(first);
        assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM accounts", Integer.class)).isEqualTo(1);
    }

    @Test
    void productionDatabaseConfigurationFailsClosedWithoutEchoingSecrets() {
                new ApplicationContextRunner().withUserConfiguration(DatabaseConfiguration.class).run(context -> {
                        assertThat(context).hasFailed();
                        assertThat(context.getStartupFailure()).hasRootCauseInstanceOf(IllegalStateException.class);
                });
        assertThatThrownBy(() -> DatabaseConfiguration.validate(false, "", "", ""))
                .isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> DatabaseConfiguration.validate(false, "jdbc:h2:mem:forbidden", "user", "synthetic-secret"))
                .isInstanceOf(IllegalStateException.class).hasMessageNotContaining("synthetic-secret");
        assertThatThrownBy(() -> DatabaseConfiguration.validate(false, "jdbc:postgresql://localhost/db", "", ""))
                .isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> DatabaseConfiguration.validate(false, "jdbc:postgresql://localhost/db", "user", "synthetic-secret"))
                .doesNotThrowAnyException();
        assertThatThrownBy(() -> DatabaseConfiguration.validate(true, "jdbc:h2:mem:forbidden", "", ""))
                .isInstanceOf(IllegalStateException.class);
        assertThatCode(() -> DatabaseConfiguration.validate(true, "jdbc:h2:file:/tmp/example", "", ""))
                .doesNotThrowAnyException();
    }

        @Test
        void invalidBootstrapValuesFailWithoutPersistingAnything() {
                var environment = new MockEnvironment().withProperty("BAHIRLEDGER_DEV_EMAIL", "bad-email")
                                .withProperty("BAHIRLEDGER_DEV_PASSWORD", "Synthetic-bootstrap-test-password!")
                                .withProperty("BAHIRLEDGER_DEV_NAME", "Person");
                assertThatThrownBy(() -> bootstrap(environment)).isInstanceOf(IllegalStateException.class);
                environment.setProperty("BAHIRLEDGER_DEV_EMAIL", "valid@example.test");
                environment.setProperty("BAHIRLEDGER_DEV_PASSWORD", "é".repeat(37));
                assertThatThrownBy(() -> bootstrap(environment)).isInstanceOf(IllegalStateException.class);
                environment.setProperty("BAHIRLEDGER_DEV_PASSWORD", "Synthetic-bootstrap-test-password!");
                environment.setProperty("BAHIRLEDGER_DEV_NAME", "N".repeat(121));
                assertThatThrownBy(() -> bootstrap(environment)).isInstanceOf(IllegalStateException.class);
                assertThat(jdbc.queryForObject("SELECT COUNT(*) FROM accounts", Integer.class)).isZero();
        }
}