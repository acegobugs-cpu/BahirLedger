package com.bahirledger.backend;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.AuthService;
import com.bahirledger.backend.auth.LocalAccountBootstrap;
import com.bahirledger.backend.auth.LoginRequest;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.UserView;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "bahirledger.auth.web-origin=http://localhost:8765")
@Import({AuthTestConfiguration.class, MailCaptureTestConfiguration.class})
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@ExtendWith(OutputCaptureExtension.class)
class AuthHttpTest {
    private static final String PASSWORD = "Synthetic-test-only-password!";
    private static final String INVALID = "{\"code\":\"invalid_credentials\",\"message\":\"Email or password is incorrect.\"}";
    @LocalServerPort int port;
    @Autowired ObjectMapper json;
    @MockitoSpyBean AccountStore accounts;
    @Autowired PasswordEncoder encoder;
    @Autowired JdbcTemplate jdbc;
    @Autowired AuthTestConfiguration.MutableClock clock;
    @Autowired ApplicationContext context;
    private final HttpClient client = HttpClient.newHttpClient();
    private String encodedPassword;
    private UserView user;

    @BeforeAll
    void encodeFixture() { encodedPassword = encoder.encode(PASSWORD); }

    @BeforeEach
    void reset() {
        clock.advance(Duration.ofMinutes(31));
        jdbc.update("DELETE FROM accounts");
        user = accounts.create("person@example.test", "Test Person", encodedPassword);
    }

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
    }

    private HttpResponse<String> send(HttpRequest.Builder request) throws Exception {
        var response = client.send(request.build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
        assertThat(response.headers().allValues("location")).isEmpty();
        if (request.build().uri().getPath().startsWith("/api/v1/auth/")
                || request.build().uri().getPath().equals("/api/v1/me")) {
            assertThat(response.headers().firstValue("cache-control")).hasValueSatisfying(value -> assertThat(value).contains("no-store"));
        }
        return response;
    }

    private HttpResponse<String> login(String email, String password) throws Exception {
        return postJson(json.writeValueAsString(Map.of("email", email, "password", password)));
    }

    private HttpResponse<String> postJson(String body) throws Exception {
        return send(request("/api/v1/auth/login").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body)));
    }

    private String token() throws Exception {
        var response = login(user.email(), PASSWORD);
        assertThat(response.statusCode()).isEqualTo(200);
        return json.readTree(response.body()).get("accessToken").asString();
    }

    private HttpResponse<String> me(String token) throws Exception {
        return send(request("/api/v1/me").header("Authorization", "Bearer " + token).GET());
    }

        private HttpResponse<String> register(String body) throws Exception {
        return send(request("/api/v1/auth/register").header("Origin", "http://localhost:8765")
            .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body)));
        }

        @Test
        void registrationPreflightAndAnonymousPostReachController() throws Exception {
        var preflight = send(request("/api/v1/auth/register").header("Origin", "http://localhost:8765")
            .header("Access-Control-Request-Method", "POST")
            .header("Access-Control-Request-Headers", "content-type")
            .method("OPTIONS", HttpRequest.BodyPublishers.noBody()));
        assertThat(preflight.statusCode()).isEqualTo(200);
        assertThat(preflight.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
        assertThat(preflight.headers().allValues("access-control-allow-credentials")).isEmpty();
        String payload = json.writeValueAsString(Map.of("email", " NEW@Example.Test ",
            "displayName", "New Person", "password", PASSWORD));
        var response = register(payload);
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
        JsonNode body = json.readTree(response.body());
        String token = body.get("accessToken").asString();
        assertThat(token).matches("[A-Za-z0-9_-]{43}");
        assertThat(body.get("user").get("email").asString()).isEqualTo("new@example.test");
        var identity = me(token);
        assertThat(identity.statusCode()).isEqualTo(200);
        assertThat(json.readTree(identity.body())).isEqualTo(body.get("user"));
        assertThat(register(payload).statusCode()).isEqualTo(409);
        assertThat(login("new@example.test", PASSWORD).statusCode()).isEqualTo(200);
        }

        @Test
        void registrationRetainsOriginMethodBodyValidationAndSourceLimits() throws Exception {
        assertThat(send(request("/api/v1/auth/register").header("Origin", "https://evil.example")
            .header("Access-Control-Request-Method", "POST")
            .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        assertThat(send(request("/api/v1/auth/register").header("Origin", "http://localhost:8765")
            .header("Access-Control-Request-Method", "PATCH")
            .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        assertThat(send(request("/api/v1/auth/register/")
            .POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        assertThat(register(" ".repeat(4097)).statusCode()).isEqualTo(400);
        assertThat(register(json.writeValueAsString(Map.of("email", "new@example.test",
            "displayName", "New Person", "password", "é".repeat(37)))).statusCode()).isEqualTo(400);
        clock.advance(Duration.ofMinutes(5));
        for (int i = 0; i < 20; i++) assertThat(register("{}").statusCode()).isEqualTo(400);
        assertThat(register("{}").statusCode()).isEqualTo(429);
        assertThat(accounts.findByEmail("new@example.test")).isEmpty();
        }

    @Test
    void loginAndMeHaveExactPublicContractAndAbsoluteUtcExpiry(CapturedOutput output) throws Exception {
        Instant now = clock.instant();
        var response = login("  PERSON@Example.Test  ", PASSWORD);
        assertThat(response.statusCode()).isEqualTo(200);
        JsonNode body = json.readTree(response.body());
        assertThat(body.propertyNames()).containsExactlyInAnyOrder("accessToken", "expiresAt", "user");
        String token = body.get("accessToken").asString();
        assertThat(token).matches("[A-Za-z0-9_-]{43}");
        assertThat(body.get("expiresAt").asString()).isEqualTo(now.plusSeconds(1800).toString());
        assertThat(body.get("user")).isEqualTo(json.valueToTree(user));
        var me = me(token);
        assertThat(me.statusCode()).isEqualTo(200);
        assertThat(json.readTree(me.body())).isEqualTo(body.get("user"));
        assertThat(response.body() + me.body()).doesNotContain(PASSWORD, encodedPassword, "passwordHash", "active", "membership");
        assertThat(me.body()).doesNotContain(token);
        assertThat(output.getAll()).doesNotContain(PASSWORD, encodedPassword, token);
        assertThat(jdbc.queryForObject("SELECT password_hash FROM accounts WHERE id = ?", String.class, user.id()))
                .isEqualTo(encodedPassword).startsWith("$2a$12$");
        assertThat(context.getBeansOfType(LocalAccountBootstrap.class)).isEmpty();
    }

    @Test
    void wrongUnknownAndInactiveCredentialsHaveIdenticalResponses() throws Exception {
        var wrong = login(user.email(), "Wrong-test-password!");
        var unknown = login("unknown@example.test", PASSWORD);
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", user.id());
        var inactive = login(user.email(), PASSWORD);
        for (var response : new HttpResponse[] {wrong, unknown, inactive}) {
            assertThat(response.statusCode()).isEqualTo(401);
            assertThat(response.body()).isEqualTo(INVALID);
        }
    }

    @Test
    void logoutRevokesOnlyCurrentSessionAndCannotBeRepeated() throws Exception {
        String first = token();
        String second = token();
        assertThat(second).isNotEqualTo(first);
        var logout = send(request("/api/v1/auth/logout").header("Authorization", "Bearer " + first)
                .POST(HttpRequest.BodyPublishers.noBody()));
        assertThat(logout.statusCode()).isEqualTo(204);
        assertThat(logout.body()).isEmpty();
        assertThat(me(first).statusCode()).isEqualTo(401);
        assertThat(me(second).statusCode()).isEqualTo(200);
        assertThat(send(request("/api/v1/auth/logout").header("Authorization", "Bearer " + first)
                .POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(401);
        assertThat(send(request("/api/v1/auth/logout").POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(401);
    }

    @Test
    void expiryIsAbsoluteAndNotExtendedByMe() throws Exception {
        String token = token();
        clock.advance(Duration.ofMinutes(29));
        assertThat(me(token).statusCode()).isEqualTo(200);
        clock.advance(Duration.ofMinutes(1));
        assertThat(me(token).statusCode()).isEqualTo(401);
        assertThat(send(request("/api/v1/auth/logout").header("Authorization", "Bearer " + token)
                .POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(401);
    }

    @Test
    void deactivationImmediatelyDisablesExistingSessions() throws Exception {
        String token = token();
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", user.id());
        assertThat(me(token).statusCode()).isEqualTo(401);
    }

    @ParameterizedTest
    @ValueSource(strings = {"Bearer invalid", "Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "Basic dXNlcjpwYXNz", "Bearer", "Bearer a b"})
    void invalidAuthorizationIsGeneric(String header) throws Exception {
        var response = send(request("/api/v1/me").header("Authorization", header).GET());
        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(response.body()).isEqualTo("{\"code\":\"unauthorized\",\"message\":\"Authentication is required.\"}");
    }

    @Test
    void cookiesQueryTokensDuplicateHeadersAndImplicitLoginCannotAuthenticate() throws Exception {
        String token = token();
        assertThat(send(request("/api/v1/me?access_token=" + token).GET()).statusCode()).isEqualTo(401);
        assertThat(send(request("/api/v1/me").header("Cookie", "accessToken=" + token + "; JSESSIONID=" + token).GET())
                .statusCode()).isEqualTo(401);
        assertThat(send(request("/api/v1/me").header("Authorization", "Bearer " + token)
                .header("Authorization", "Bearer " + token).GET()).statusCode()).isEqualTo(401);
        assertThat(send(request("/login").GET()).statusCode()).isEqualTo(401);
    }

    @Test
    void authenticatedUnknownRoutesStayDeniedAndCsrfIsNotGloballyDisabled() throws Exception {
        String token = token();
        for (String path : new String[] {"/api/v1/projects", "/api/v1/auth/signup", "/api/v1/auth/refresh", "/contracts/openapi.yaml"}) {
            assertThat(send(request(path).header("Authorization", "Bearer " + token).GET()).statusCode()).isEqualTo(403);
        }
        for (String path : new String[] {"/api/v1/health", "/api/v1/me", "/api/v1/auth/login", "/api/v1/auth/logout", "/unknown"}) {
            assertThat(send(request(path).header("Authorization", "Bearer " + token)
                    .method("PATCH", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        }
        assertThat(send(request("/api/v1/auth/login/").POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        assertThat(send(request("/api/v1/health").POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "null", "[]", "{", "{\"email\":\"bad\",\"password\":\"test\"}",
            "{\"email\":\"person@example.test\",\"password\":null}",
            "{\"email\":\"person@example.test\",\"password\":\"   \"}"})
    void malformedOrInvalidLoginReturnsGeneric400(String body) throws Exception {
        var response = postJson(body);
        assertThat(response.statusCode()).isEqualTo(400);
        assertThat(response.body()).isEqualTo("{\"code\":\"invalid_request\",\"message\":\"Request is invalid.\"}");
    }

    @Test
    void passwordByteLimitEmailLimitAndBoundedBodyApplyBeforeBcrypt() throws Exception {
        assertThat(login(user.email(), "a".repeat(73)).statusCode()).isEqualTo(400);
        assertThat(login(user.email(), "é".repeat(37)).statusCode()).isEqualTo(400);
        assertThat(login("a".repeat(255) + "@example.test", PASSWORD).statusCode()).isEqualTo(400);
        assertThat(postJson(" ".repeat(4097)).statusCode()).isEqualTo(400);
        assertThat(send(request("/api/v1/auth/login").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofInputStream(() -> new ByteArrayInputStream(new byte[4097]))))
                .statusCode()).isEqualTo(400);
        assertThat(send(request("/api/v1/auth/login").header("Content-Type", "text/plain")
                .POST(HttpRequest.BodyPublishers.ofString(PASSWORD))).statusCode()).isEqualTo(400);
        assertThat(login(user.email(), "a".repeat(72)).statusCode()).isEqualTo(401);
    }

    @Test
    void emailThrottleUsesNormalizedAddressAndRecoversAfterWindow() throws Exception {
        for (int i = 0; i < 5; i++) assertThat(login(" PERSON@EXAMPLE.TEST ", "wrong").statusCode()).isEqualTo(401);
        var blocked = login(user.email(), PASSWORD);
        assertThat(blocked.statusCode()).isEqualTo(429);
        assertThat(blocked.body()).isEqualTo("{\"code\":\"too_many_requests\",\"message\":\"Too many requests. Try again later.\"}");
        clock.advance(Duration.ofMinutes(5));
        assertThat(login(user.email(), PASSWORD).statusCode()).isEqualTo(200);
    }

    @Test
    void sourceThrottleIncludesMalformedBodiesAndIgnoresForwardedHeaders() throws Exception {
        for (int i = 0; i < 20; i++) {
            assertThat(send(request("/api/v1/auth/login").header("Content-Type", "application/json")
                    .header("X-Forwarded-For", "192.0.2." + i).POST(HttpRequest.BodyPublishers.ofString("{}")))
                    .statusCode()).isEqualTo(400);
        }
        assertThat(login(user.email(), PASSWORD).statusCode()).isEqualTo(429);
        assertThat(send(request("/api/v1/health").GET()).statusCode()).isEqualTo(200);
    }

    @Test
    void corsPreflightAllowsOnlyConfiguredOriginHeadersAndPaths() throws Exception {
        var allowed = send(request("/api/v1/me").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "GET")
                .header("Access-Control-Request-Headers", "Authorization, Content-Type")
                .method("OPTIONS", HttpRequest.BodyPublishers.noBody()));
        assertThat(allowed.statusCode()).isEqualTo(200);
        assertThat(allowed.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
        assertThat(allowed.headers().allValues("access-control-allow-credentials")).isEmpty();
        for (String origin : new String[] {"http://localhost:8766", "https://evil.example", "null"}) {
            var denied = send(request("/api/v1/auth/login").header("Origin", origin)
                    .header("Access-Control-Request-Method", "POST").method("OPTIONS", HttpRequest.BodyPublishers.noBody()));
            assertThat(denied.statusCode()).isEqualTo(403);
            assertThat(denied.headers().allValues("access-control-allow-origin")).isEmpty();
        }
        assertThat(send(request("/api/v1/projects").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "GET").method("OPTIONS", HttpRequest.BodyPublishers.noBody()))
                .statusCode()).isEqualTo(403);
        assertThat(send(request("/api/v1/me").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "DELETE").method("OPTIONS", HttpRequest.BodyPublishers.noBody()))
                .statusCode()).isEqualTo(403);
        assertThat(send(request("/api/v1/me").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "GET").header("Access-Control-Request-Headers", "X-Unapproved")
                .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
    }

    @Test
    void actualCorsResponsesAndErrorsHaveNoCredentialsOrWildcard() throws Exception {
        var response = send(request("/api/v1/auth/login").header("Origin", "http://localhost:8765")
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(Map.of("email", user.email(), "password", PASSWORD)))));
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
        assertThat(response.headers().allValues("access-control-allow-credentials")).isEmpty();
        assertThat(send(request("/api/v1/me").header("Origin", "https://evil.example").GET()).statusCode()).isEqualTo(403);
    }

    @Test
    void databaseFailureHasGenericResponseAndDoesNotLeakException(CapturedOutput output) throws Exception {
        String secretMarker = "synthetic-database-secret-marker";
        doThrow(new DataAccessResourceFailureException(secretMarker)).when(accounts).findByEmail("failure@example.test");
        var response = login("failure@example.test", PASSWORD);
        assertThat(response.statusCode()).isEqualTo(503);
        assertThat(response.body()).isEqualTo("{\"code\":\"service_unavailable\",\"message\":\"Service is temporarily unavailable.\"}");
        assertThat(output.getAll()).doesNotContain(secretMarker, PASSWORD);
    }

    @Test
    void sensitiveDtosHaveRedactedDiagnosticStrings() {
        String token = UUID.randomUUID().toString();
        assertThat(new LoginRequest(user.email(), PASSWORD).toString()).doesNotContain(PASSWORD, user.email());
        assertThat(new SessionStore.IssuedSession(token, clock.instant()).toString()).doesNotContain(token);
        assertThat(new AuthService.LoginResponse(token, clock.instant(), user).toString()).doesNotContain(token);
        assertThat(accounts.findByEmail(user.email()).orElseThrow().toString()).doesNotContain(encodedPassword);
    }
}