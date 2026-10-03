package com.bahirledger.backend.auth.mail;

import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermissions;

import com.bahirledger.backend.auth.ApiException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.*;

class VerificationMailTest {
    @TempDir Path home;

    @Test
    void disabledDeliveryFailsWithoutPretendingSuccess() {
        var sender = new VerificationMailConfiguration().verificationMailSender(new MockEnvironment());
        assertThatThrownBy(() -> sender.send("test@example.test", "A".repeat(43)))
                .isInstanceOf(ApiException.class).satisfies(error -> assertThat(((ApiException) error).status()).isEqualTo(503));
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "http://example.test", "http://localhost:8765", "https://example.test/",
            "https://user@example.test", "https://example.test?x=y", "https://example.test#fragment",
            "https://example.test:0", "https://example.test:65536", "javascript:alert(1)"})
    void publicOriginMustBeAnExactHttpsOrigin(String origin) {
        assertThatThrownBy(() -> VerificationMailConfiguration.validateOrigin(origin, false)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void linkUsesConfiguredOriginAndFragmentOnlyWithManualPasteAlternative() {
        String token = "B".repeat(43);
        VerificationMailConfiguration.validateOrigin("https://app.example.test", false);
        for (String origin : new String[] {"http://localhost:8765", "http://127.0.0.1:8765", "http://[::1]:8765"}) {
            VerificationMailConfiguration.validateOrigin(origin, true);
        }
        assertThatThrownBy(() -> VerificationMailConfiguration.validateOrigin("http://external.example.test", true)).isInstanceOf(IllegalStateException.class);
        String body = VerificationMailConfiguration.body("https://app.example.test", token);
        URI link = URI.create(body.lines().filter(line -> line.startsWith("https://")).findFirst().orElseThrow());
        assertThat(link.getHost()).isEqualTo("app.example.test");
        assertThat(link.getPath()).isEqualTo("/");
        assertThat(link.getQuery()).isNull();
        assertThat(link.getFragment()).isEqualTo("/verify-email?token=" + token);
        assertThat(body).contains("\n" + token + "\n");
    }

    @Test
    void smtpRequiresExplicitHostFromTlsAndBoundedTimeouts() {
        var env = smtpEnvironment();
        var sender = VerificationMailConfiguration.smtp(env, false);
        assertThat(sender.getJavaMailProperties()).containsEntry("mail.smtp.starttls.required", "true")
                .containsEntry("mail.smtp.ssl.checkserveridentity", "true")
                .containsEntry("mail.smtp.connectiontimeout", "5000")
                .containsEntry("mail.smtp.timeout", "5000")
                .containsEntry("mail.smtp.writetimeout", "5000")
                .containsEntry("mail.debug", "false");
        assertThat(sender.getPort()).isEqualTo(587);
        env.setProperty("bahirledger.mail.smtp.starttls", "false");
        assertThatThrownBy(() -> VerificationMailConfiguration.smtp(env, false)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> VerificationMailConfiguration.smtp(env, true)).isInstanceOf(IllegalStateException.class);
        env.setProperty("bahirledger.mail.smtp.host", "localhost");
        assertThatCode(() -> VerificationMailConfiguration.smtp(env, true)).doesNotThrowAnyException();
        env.setProperty("bahirledger.mail.smtp.from", "");
        assertThatThrownBy(() -> VerificationMailConfiguration.smtp(env, true)).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> VerificationMailConfiguration.smtp(new MockEnvironment(), false)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void fileModeIsRejectedOutsideExclusivelyLocalProfileAndUnknownModesFailClosed() {
        var env = new MockEnvironment().withProperty("bahirledger.mail.mode", "file")
                .withProperty("bahirledger.mail.verification-web-origin", "https://app.example.test");
        var config = new VerificationMailConfiguration();
        assertThatThrownBy(() -> config.verificationMailSender(env)).isInstanceOf(IllegalStateException.class);
        env.setActiveProfiles("local", "production");
        assertThatThrownBy(() -> config.verificationMailSender(env)).isInstanceOf(IllegalStateException.class);
        env.setActiveProfiles("local");
        assertThatCode(() -> config.verificationMailSender(env)).doesNotThrowAnyException();
        env.setProperty("bahirledger.mail.mode", "unknown");
        assertThatThrownBy(() -> config.verificationMailSender(env)).isInstanceOf(IllegalStateException.class);
    }

    @Test
    void fileDeliveryCreatesPrivateOutboxAndDistinctPrivateFiles() throws Exception {
        var outbox = new LocalFileOutbox(home);
        String content = "Synthetic token: " + "C".repeat(43);
        outbox.deliver(content);
        outbox.deliver(content);
        Path directory = home.resolve(".local/share/bahirledger/mail");
        assertThat(Files.getPosixFilePermissions(directory)).isEqualTo(PosixFilePermissions.fromString("rwx------"));
        try (var files = Files.list(directory)) {
            var paths = files.toList();
            assertThat(paths).hasSize(2);
            for (Path path : paths) {
                assertThat(Files.getPosixFilePermissions(path)).isEqualTo(PosixFilePermissions.fromString("rw-------"));
                assertThat(Files.readString(path)).isEqualTo(content);
            }
        }
    }

    @Test
    void fileDeliveryRejectsSymlinkAtAnyParentWithoutWritingToTarget() throws Exception {
        Path target = Files.createDirectory(home.resolve("target"));
        Path base = Files.createDirectory(home.resolve("base"));
        Files.createSymbolicLink(base.resolve(".local"), target);
        assertThatThrownBy(() -> new LocalFileOutbox(base).deliver("private-token"))
                .isInstanceOf(ApiException.class).hasMessageNotContaining("private-token");
        try (var files = Files.list(target)) { assertThat(files.toList()).isEmpty(); }
        Path normal = Files.createDirectory(home.resolve("normal"));
        Path parent = Files.createDirectories(normal.resolve(".local/share/bahirledger"));
        Files.createSymbolicLink(parent.resolve("mail"), target);
        assertThatThrownBy(() -> new LocalFileOutbox(normal).deliver("private-token")).isInstanceOf(ApiException.class);
        try (var files = Files.list(target)) { assertThat(files.toList()).isEmpty(); }
    }

    @Test
    void existingNonDirectoryCollisionFailsWithoutOverwrite() throws Exception {
        Path parent = Files.createDirectories(home.resolve(".local/share/bahirledger"));
        Path collision = Files.writeString(parent.resolve("mail"), "keep-existing");
        assertThatThrownBy(() -> new LocalFileOutbox(home).deliver("private-token")).isInstanceOf(ApiException.class);
        assertThat(Files.readString(collision)).isEqualTo("keep-existing");
    }

    private static MockEnvironment smtpEnvironment() {
        return new MockEnvironment().withProperty("bahirledger.mail.smtp.host", "smtp.example.test")
                .withProperty("bahirledger.mail.smtp.from", "noreply@example.test");
    }
}