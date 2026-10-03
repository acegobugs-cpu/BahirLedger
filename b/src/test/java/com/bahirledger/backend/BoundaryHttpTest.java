package com.bahirledger.backend;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.annotation.Import;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
    properties = "bahirledger.mail.mode=disabled")
@Import(AuthTestConfiguration.class)
class BoundaryHttpTest {
    @LocalServerPort
    int port;

    @org.springframework.beans.factory.annotation.Autowired
    com.bahirledger.backend.auth.AccountStore accounts;
    @org.springframework.beans.factory.annotation.Autowired
    com.bahirledger.backend.auth.SessionStore sessions;

    private final HttpClient client = HttpClient.newHttpClient();

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
    }

    @Test
    void healthContractExposesOnlyLivenessAndCreatesNoSession() throws Exception {
        var response = client.send(request("/api/v1/health").GET().build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).isEqualTo("{\"status\":\"UP\"}");
        assertThat(response.headers().firstValue("content-type")).hasValue("application/json");
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
    }

    @ParameterizedTest
    @ValueSource(strings = {"/api/v1/projects", "/login", "/actuator/env", "/contracts/openapi.yaml", "/unknown"})
    void allOtherPathsAreClosed(String path) throws Exception {
        var response = client.send(request(path).GET().build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(401);
        assertThat(response.headers().allValues("location")).isEmpty();
        assertThat(response.body()).isEqualTo("{\"code\":\"unauthorized\",\"message\":\"Authentication is required.\"}");
    }

    @Test
    void inventedBasicCredentialsDoNotEnableAccess() throws Exception {
        var response = client.send(request("/api/v1/projects")
                .header("Authorization", "Basic dXNlcjpwYXNzd29yZA==").GET().build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(401);
    }

    @Test
    void postToHealthIsNotPublic() throws Exception {
        var response = client.send(request("/api/v1/health").POST(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(403);
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
    }

    @Test
    void corsHasNoDefaultOriginOutsideLocalProfile() throws Exception {
        var response = client.send(request("/api/v1/auth/login").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "POST")
                .method("OPTIONS", HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(403);
        assertThat(response.headers().allValues("access-control-allow-origin")).isEmpty();
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
    }

    @Test
    void disabledMailMakesRegistrationAndResendUnavailableButLeavesLoginPossible() throws Exception {
        String payload = "{\"email\":\"disabled@example.test\",\"displayName\":\"Disabled\",\"password\":\"Synthetic-disabled-password!\"}";
        var register = client.send(request("/api/v1/auth/register").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(payload)).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(register.statusCode()).isEqualTo(503);
        assertThat(register.body()).doesNotContain("accessToken", "Synthetic-disabled-password!");
        assertThat(accounts.findByEmail("disabled@example.test").orElseThrow().user().emailVerified()).isFalse();
        var login = client.send(request("/api/v1/auth/login").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"disabled@example.test\",\"password\":\"Synthetic-disabled-password!\"}")).build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(login.statusCode()).isEqualTo(200);
        var other = accounts.create("disabled-resend@example.test", "Other", "synthetic-hash");
        var resend = client.send(request("/api/v1/auth/email-verification/resend")
                .header("Authorization", "Bearer " + sessions.issue(other.id()).accessToken())
                .POST(HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(resend.statusCode()).isEqualTo(503);
    }
}