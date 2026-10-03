package com.bahirledger.backend;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;

import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.UserView;
import com.bahirledger.backend.auth.VerificationRequest;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "bahirledger.auth.web-origin=http://localhost:8765")
@Import({AuthTestConfiguration.class, MailCaptureTestConfiguration.class})
@ExtendWith(OutputCaptureExtension.class)
class EmailVerificationHttpTest {
    private static final String CONFIRM = "/api/v1/auth/email-verification/confirm";
    private static final String RESEND = "/api/v1/auth/email-verification/resend";
    private static final String INVALID = "{\"code\":\"invalid_verification_token\",\"message\":\"Verification token is invalid or expired.\"}";
    @LocalServerPort int port;
    @Autowired AccountStore accounts;
    @Autowired SessionStore sessions;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Autowired AuthTestConfiguration.MutableClock clock;
    @Autowired MailCaptureTestConfiguration.CapturingMailSender mail;
    private final HttpClient client = HttpClient.newHttpClient();
    private UserView user;
    private String bearer;

    @BeforeEach
    void reset() {
        clock.advance(Duration.ofMinutes(31));
        jdbc.update("DELETE FROM accounts");
        mail.reset();
        user = accounts.create("verify@example.test", "Verification Person", "synthetic-encoded-fixture");
        bearer = sessions.issue(user.id()).accessToken();
    }

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
    }

    private HttpResponse<String> send(HttpRequest.Builder builder) throws Exception {
        var response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
        assertThat(response.headers().allValues("location")).isEmpty();
        assertThat(response.headers().firstValue("cache-control")).hasValueSatisfying(value -> assertThat(value).contains("no-store"));
        return response;
    }

    private HttpResponse<String> post(String path, String session, String body) throws Exception {
        var builder = request(path).header("Content-Type", "application/json");
        if (session != null) builder.header("Authorization", "Bearer " + session);
        return send(builder.POST(body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(body)));
    }

    private HttpResponse<String> confirm(String token) throws Exception {
        return post(CONFIRM, bearer, json.writeValueAsString(Map.of("token", token)));
    }

    @Test
    void confirmUpdatesExactIdentityWithoutExtendingSessionOrGrantingTenantAccess(CapturedOutput output) throws Exception {
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(204);
        String token = mail.deliveries.getFirst().token();
        assertThat(token).matches("[A-Za-z0-9_-]{43}").isNotEqualTo(bearer);
        assertThat(user.emailVerified()).isFalse();
        assertThat(send(request("/api/v1/projects").header("Authorization", "Bearer " + bearer).GET()).statusCode()).isEqualTo(403);
        var result = confirm(token);
        assertThat(result.statusCode()).isEqualTo(200);
        var identity = json.readTree(result.body());
        assertThat(identity.propertyNames()).containsExactlyInAnyOrder("id", "email", "displayName", "emailVerified");
        assertThat(identity.get("emailVerified").asBoolean()).isTrue();
        assertThat(result.body()).doesNotContain(token, bearer, "token_digest", "expiresAt");
        assertThat(json.readTree(send(request("/api/v1/me").header("Authorization", "Bearer " + bearer).GET()).body())).isEqualTo(identity);
        assertThat(send(request("/api/v1/projects").header("Authorization", "Bearer " + bearer).GET()).statusCode()).isEqualTo(403);
        assertThat(confirm(token).body()).isEqualTo(INVALID);
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(204);
        assertThat(mail.deliveries).hasSize(1);
        assertThat(new VerificationRequest(token).toString()).doesNotContain(token);
        assertThat(output.getAll()).doesNotContain(token, bearer);
        clock.advance(Duration.ofMinutes(30));
        assertThat(send(request("/api/v1/me").header("Authorization", "Bearer " + bearer).GET()).statusCode()).isEqualTo(401);
    }

    @Test
    void registrationSendsExactlyOnceAndNeverReturnsVerificationToken(CapturedOutput output) throws Exception {
        String body = json.writeValueAsString(Map.of("email", "new@example.test", "displayName", "New", "password", "Synthetic-signup-password!"));
        var result = post("/api/v1/auth/register", null, body);
        assertThat(result.statusCode()).isEqualTo(200);
        assertThat(json.readTree(result.body()).get("user").get("emailVerified").asBoolean()).isFalse();
        assertThat(mail.deliveries).hasSize(1);
        String token = mail.deliveries.getFirst().token();
        assertThat(result.body()).doesNotContain(token);
        assertThat(post("/api/v1/auth/register", null, body).statusCode()).isEqualTo(409);
        assertThat(mail.deliveries).hasSize(1);
        String session = json.readTree(result.body()).get("accessToken").asString();
        assertThat(post(CONFIRM, session, json.writeValueAsString(Map.of("token", token))).statusCode()).isEqualTo(200);
        var login = post("/api/v1/auth/login", null, json.writeValueAsString(Map.of(
            "email", "new@example.test", "password", "Synthetic-signup-password!")));
        assertThat(login.statusCode()).isEqualTo(200);
        assertThat(json.readTree(login.body()).get("user").get("emailVerified").asBoolean()).isTrue();
        assertThat(output.getAll()).doesNotContain(token, "Synthetic-signup-password!");
    }

    @Test
    void simultaneousDuplicateRegistrationsReturnSuccessAndConflictWithOneEmail() throws Exception {
        String body = json.writeValueAsString(Map.of("email", "race@example.test", "displayName", "Race", "password", "Synthetic-race-password!"));
        var start = new java.util.concurrent.CountDownLatch(1);
        try (var executor = java.util.concurrent.Executors.newFixedThreadPool(2)) {
            java.util.concurrent.Callable<Integer> register = () -> {
                assertThat(start.await(10, java.util.concurrent.TimeUnit.SECONDS)).isTrue();
                return post("/api/v1/auth/register", null, body).statusCode();
            };
            var first = executor.submit(register);
            var second = executor.submit(register);
            start.countDown();
            assertThat(java.util.List.of(first.get(10, java.util.concurrent.TimeUnit.SECONDS), second.get(10, java.util.concurrent.TimeUnit.SECONDS)))
                    .containsExactlyInAnyOrder(200, 409);
        }
        assertThat(mail.deliveries).hasSize(1);
    }

    @Test
    void failedRegistrationLeavesPendingAccountNoHiddenSessionAndLoginResendRecovers(CapturedOutput output) throws Exception {
        mail.fail = true;
        Map<?, ?> sessionState = (Map<?, ?>) ReflectionTestUtils.getField(sessions, "sessions");
        int previous = sessionState.size();
        String credentials = json.writeValueAsString(Map.of("email", "pending@example.test", "password", "Synthetic-pending-password!"));
        var result = post("/api/v1/auth/register", null, json.writeValueAsString(Map.of(
                "email", "pending@example.test", "displayName", "Pending", "password", "Synthetic-pending-password!")));
        assertThat(result.statusCode()).isEqualTo(503);
        assertThat(result.body()).isEqualTo("{\"code\":\"service_unavailable\",\"message\":\"Service is temporarily unavailable.\"}");
        assertThat(sessionState).hasSize(previous);
        assertThat(accounts.findByEmail("pending@example.test").orElseThrow().user().emailVerified()).isFalse();
        var login = post("/api/v1/auth/login", null, credentials);
        assertThat(login.statusCode()).isEqualTo(200);
        String session = json.readTree(login.body()).get("accessToken").asString();
        assertThat(post(RESEND, session, null).statusCode()).isEqualTo(429);
        mail.fail = false;
        clock.advance(Duration.ofMinutes(1));
        assertThat(post(RESEND, session, null).statusCode()).isEqualTo(204);
        assertThat(mail.deliveries).hasSize(1);
        assertThat(output.getAll()).doesNotContain("synthetic-mail-secret-marker", "Synthetic-pending-password!");
    }

    @Test
    void missingInvalidAndInactiveBearerFailBeforeTokenValidation() throws Exception {
        for (String path : new String[] {CONFIRM, RESEND}) {
            assertThat(post(path, null, "{}").statusCode()).isEqualTo(401);
            assertThat(post(path, "A".repeat(43), "{}").statusCode()).isEqualTo(401);
            assertThat(send(request(path).header("Cookie", "accessToken=" + bearer).POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(401);
        }
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", user.id());
        assertThat(post(CONFIRM, bearer, "{}").statusCode()).isEqualTo(401);
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(401);
    }

    @Test
    void invalidWrongAccountExpiredAndReplayedTokensShareFixedResponse() throws Exception {
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(204);
        String token = mail.deliveries.getFirst().token();
        for (String body : new String[] {"{}", "{\"token\":null}", "{\"token\":\"short\"}", "{\"token\":\"" + "A".repeat(43) + "\"}"}) {
            var invalid = post(CONFIRM, bearer, body);
            assertThat(invalid.statusCode()).isEqualTo(400);
            assertThat(invalid.body()).isEqualTo(INVALID);
        }
        var other = accounts.create("other@example.test", "Other", "synthetic-hash");
        assertThat(post(CONFIRM, sessions.issue(other.id()).accessToken(), json.writeValueAsString(Map.of("token", token))).body()).isEqualTo(INVALID);
        clock.advance(Duration.ofMinutes(30));
        bearer = sessions.issue(user.id()).accessToken();
        assertThat(confirm(token).body()).isEqualTo(INVALID);
        assertThat(accounts.findActiveUser(user.id()).orElseThrow().emailVerified()).isFalse();
    }

    @Test
    void confirmBodyIsBoundedIncludingChunkedAndMalformedAttemptsAreThrottled() throws Exception {
        assertThat(post(CONFIRM, bearer, " ".repeat(4097)).statusCode()).isEqualTo(400);
        assertThat(send(request(CONFIRM).header("Authorization", "Bearer " + bearer).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofInputStream(() -> new ByteArrayInputStream(new byte[4097])))).statusCode()).isEqualTo(400);
        assertThat(send(request(CONFIRM).header("Authorization", "Bearer " + bearer).header("Content-Type", "text/plain")
                .POST(HttpRequest.BodyPublishers.ofString("{}"))).statusCode()).isEqualTo(400);
        for (int i = 3; i < 10; i++) assertThat(post(CONFIRM, bearer, "{").statusCode()).isEqualTo(400);
        assertThat(post(CONFIRM, bearer, "{}").statusCode()).isEqualTo(429);
        // New sessions do not reset the account budget.
        assertThat(post(CONFIRM, sessions.issue(user.id()).accessToken(), "{}").statusCode()).isEqualTo(429);
    }

    @Test
    void resendCooldownAndAccountBudgetApplyWithoutBodyOrCookieAuthentication() throws Exception {
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(204);
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(429);
        clock.advance(Duration.ofMinutes(1));
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(204);
        clock.advance(Duration.ofMinutes(1));
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(429);
        clock.advance(Duration.ofMinutes(5));
        assertThat(post(RESEND, bearer, "{}").statusCode()).isEqualTo(400);
        mail.fail = true;
        assertThat(post(RESEND, bearer, null).statusCode()).isEqualTo(503);
    }

    @Test
    void directSourceLimitsCannotBeBypassedByChangingAccountsOrForwardedHeaders() throws Exception {
        for (boolean confirm : new boolean[] {true, false}) {
            int limit = confirm ? 20 : 10;
            for (int i = 0; i < limit; i++) {
                var account = accounts.create((confirm ? "c" : "r") + i + "@example.test", "Source", "synthetic-hash");
                var result = send(request(confirm ? CONFIRM : RESEND).header("Authorization", "Bearer " + sessions.issue(account.id()).accessToken())
                        .header("X-Forwarded-For", "192.0.2." + i).header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString("{")));
                assertThat(result.statusCode()).isEqualTo(400);
            }
            assertThat(post(confirm ? CONFIRM : RESEND, bearer, null).statusCode()).isEqualTo(429);
        }
    }

    @Test
    void corsAndCsrfExceptionsAreExactRoutesAndPostOnly() throws Exception {
        for (String path : new String[] {CONFIRM, RESEND}) {
            // CORS preflight does not consume a bearer, body or email budget.
            var preflight = client.send(request(path).header("Origin", "http://localhost:8765")
                    .header("Access-Control-Request-Method", "POST").header("Access-Control-Request-Headers", "Authorization, Content-Type")
                    .method("OPTIONS", HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
            assertThat(preflight.statusCode()).isEqualTo(200);
            assertThat(preflight.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
            assertThat(preflight.headers().allValues("access-control-allow-credentials")).isEmpty();
            for (String method : new String[] {"GET", "PATCH", "DELETE"}) {
                assertThat(send(request(path).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", method)
                        .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
                assertThat(send(request(path).header("Authorization", "Bearer " + bearer)
                        .method(method, HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
            }
            assertThat(send(request(path + "/").header("Authorization", "Bearer " + bearer).POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
            assertThat(send(request(path).header("Origin", "https://evil.example").POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
            assertThat(send(request(path).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", "POST")
                    .header("Access-Control-Request-Headers", "X-Unapproved").method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        }
        var actual = send(request(RESEND).header("Authorization", "Bearer " + bearer).header("Origin", "http://localhost:8765")
                .POST(HttpRequest.BodyPublishers.noBody()));
        assertThat(actual.statusCode()).isEqualTo(204);
        assertThat(actual.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
    }
}