package com.bahirledger.backend;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.LocalAccountBootstrap;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;

/** Exercise real profile-driven startup provisioning, still using only in-memory test H2. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "bahirledger.auth.web-origin=http://localhost:8765",
        "BAHIRLEDGER_DEV_EMAIL=Local-Profile@Example.Test",
        "BAHIRLEDGER_DEV_PASSWORD=Synthetic-local-profile-test-only!",
        "BAHIRLEDGER_DEV_NAME=Local Profile Person"
})
@ActiveProfiles("local")
@Import(AuthTestConfiguration.class)
class LocalProfileHttpTest {
    @LocalServerPort int port;
    @Autowired ApplicationContext context;
    @Autowired AccountStore accounts;
    @Autowired ObjectMapper json;
    private final HttpClient client = HttpClient.newHttpClient();

    private HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
    }

    @Test
    void automaticallyProvisionedAccountCanLogInAndReadIdentity() throws Exception {
        assertThat(context.getBeansOfType(LocalAccountBootstrap.class)).hasSize(1);
        var account = accounts.findByEmail("local-profile@example.test").orElseThrow();
        var response = client.send(request("/api/v1/auth/login").header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(Map.of(
                        "email", "LOCAL-PROFILE@example.test", "password", "Synthetic-local-profile-test-only!"))))
                .build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
        var body = json.readTree(response.body());
        assertThat(body.get("user")).isEqualTo(json.valueToTree(account.user()));
        var me = client.send(request("/api/v1/me")
                .header("Authorization", "Bearer " + body.get("accessToken").asString()).GET().build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(me.statusCode()).isEqualTo(200);
        assertThat(json.readTree(me.body())).isEqualTo(body.get("user"));
    }

    @Test
        void localProfileUsesTheExplicitlyConfiguredWebOrigin() throws Exception {
        var response = client.send(request("/api/v1/auth/login").header("Origin", "http://localhost:8765")
                .header("Access-Control-Request-Method", "POST")
                .header("Access-Control-Request-Headers", "Content-Type")
                .method("OPTIONS", HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
        assertThat(response.headers().allValues("access-control-allow-credentials")).isEmpty();
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
    }
}