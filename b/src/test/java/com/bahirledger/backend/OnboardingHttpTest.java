package com.bahirledger.backend;

import java.io.ByteArrayInputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.UserView;
import com.bahirledger.backend.onboarding.OnboardingRoutes;
import com.bahirledger.backend.onboarding.OnboardingService;
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
import tools.jackson.databind.ObjectMapper;
import static org.assertj.core.api.Assertions.*;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "bahirledger.auth.web-origin=http://localhost:8765")
@Import({AuthTestConfiguration.class, MailCaptureTestConfiguration.class})
@ExtendWith(OutputCaptureExtension.class)
class OnboardingHttpTest {
    static final String ROOT = "/api/v1/onboarding";
    static final String INVITES = OnboardingRoutes.INVITATIONS;
    static final String INVALID = "{\"code\":\"invalid_invitation\",\"message\":\"Invitation is invalid or unavailable.\"}";
    @LocalServerPort int port;
    @Autowired AccountStore accounts;
    @Autowired SessionStore sessions;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper json;
    @Autowired OnboardingService service;
    @Autowired AuthTestConfiguration.MutableClock clock;
    @Autowired MailCaptureTestConfiguration.CapturingMailSender mail;
    final HttpClient client = HttpClient.newHttpClient();
    UserView owner;
    String bearer;

    @BeforeEach void reset() {
        clock.advance(Duration.ofMinutes(31));
        // Shared Spring context with existing auth tests: leave it empty after each test too.
        clear();
        mail.reset();
        owner = user("owner@example.test", true);
        bearer = sessions.issue(owner.id()).accessToken();
    }
    @org.junit.jupiter.api.AfterEach void clear() {
        for (String table : List.of("onboarding_audit", "organization_invitations", "organization_memberships", "organization_bootstraps", "organizations", "accounts")) {
            jdbc.update("DELETE FROM " + table);
        }
    }
    UserView user(String email, boolean verified) {
        var user = accounts.create(email, "HTTP fixture", "synthetic-hash");
        jdbc.update("UPDATE accounts SET email_verified = ? WHERE id = ?", verified, user.id());
        return accounts.findActiveUser(user.id()).orElseThrow();
    }
    HttpRequest.Builder request(String path) {
        return HttpRequest.newBuilder(URI.create("http://127.0.0.1:" + port + path));
    }
    HttpResponse<String> send(HttpRequest.Builder request) throws Exception {
        var response = client.send(request.build(), HttpResponse.BodyHandlers.ofString());
        assertThat(response.headers().allValues("set-cookie")).isEmpty();
        assertThat(response.headers().allValues("location")).isEmpty();
        assertThat(response.headers().firstValue("cache-control")).hasValueSatisfying(value -> assertThat(value).contains("no-store"));
        return response;
    }
    HttpResponse<String> post(String path, String token, String body) throws Exception {
        var request = request(path).header("Content-Type", "application/json");
        if (token != null) request.header("Authorization", "Bearer " + token);
        return send(request.POST(body == null ? HttpRequest.BodyPublishers.noBody() : HttpRequest.BodyPublishers.ofString(body)));
    }
    HttpResponse<String> get(String path, String token) throws Exception {
        var request = request(path);
        if (token != null) request.header("Authorization", "Bearer " + token);
        return send(request.GET());
    }
    String body(String key, Object value) { return json.writeValueAsString(Map.of(key, value)); }
    String idBody(UUID id) { return body("bootstrapId", id.toString()); }
    void activateOwner() { service.activate(owner.id(), service.bootstrap(owner.id(), "Owner organization").bootstrap().id()); }

    @Test void exactHappyPathContractAndNoMailOrBusinessRights(CapturedOutput output) throws Exception {
        assertThat(get(ROOT, bearer).body()).isEqualTo("{\"membership\":null,\"bootstrap\":null}");
        var setup = post(ROOT + "/bootstrap", bearer, body("name", "  Example  "));
        assertThat(setup.statusCode()).isEqualTo(200);
        var bootstrap = json.readTree(setup.body()).get("bootstrap");
        assertThat(bootstrap.propertyNames()).containsExactlyInAnyOrder("id", "name", "expiresAt");
        assertThat(bootstrap.get("name").asString()).isEqualTo("Example");
        assertThat(bootstrap.get("expiresAt").asString()).endsWith("Z");
        var id = UUID.fromString(bootstrap.get("id").asString());
        assertThat(get(INVITES, bearer).statusCode()).isEqualTo(403);
        assertThat(post(INVITES, bearer, body("email", "person@example.test")).statusCode()).isEqualTo(403);
        var activated = post(ROOT + "/bootstrap/activate", bearer, idBody(id));
        assertThat(activated.statusCode()).isEqualTo(200);
        var context = json.readTree(activated.body());
        assertThat(context.propertyNames()).containsExactlyInAnyOrder("membership", "bootstrap");
        assertThat(context.get("membership").propertyNames()).containsExactlyInAnyOrder("organizationId", "organizationName", "role");
        assertThat(context.get("membership").get("role").asString()).isEqualTo("OWNER");
        assertThat(post(ROOT + "/bootstrap/activate", bearer, idBody(id)).body()).isEqualTo(activated.body());
        var recipient = user("person@example.test", true);
        var recipientBearer = sessions.issue(recipient.id()).accessToken();
        var issued = post(INVITES, bearer, body("email", " PERSON@EXAMPLE.TEST "));
        assertThat(issued.statusCode()).isEqualTo(201);
        var issuance = json.readTree(issued.body());
        assertThat(issuance.propertyNames()).containsExactlyInAnyOrder("invitation", "token");
        var invitation = issuance.get("invitation");
        assertThat(invitation.propertyNames()).containsExactlyInAnyOrder("id", "email", "status", "expiresAt");
        assertThat(invitation.get("email").asString()).isEqualTo(recipient.email());
        String token = issuance.get("token").asString();
        assertThat(token).matches("[A-Za-z0-9_-]{43}");
        var listing = get(INVITES, bearer);
        assertThat(listing.statusCode()).isEqualTo(200);
        assertThat(json.readTree(listing.body()).propertyNames()).containsExactly("invitations");
        assertThat(listing.body()).doesNotContain(token, "digest", "issuedBy");
        var preview = post(ROOT + "/invitations/preview", recipientBearer, body("token", token));
        assertThat(preview.statusCode()).isEqualTo(200);
        assertThat(json.readTree(preview.body()).propertyNames()).containsExactlyInAnyOrder("organizationName", "expiresAt");
        var accepted = post(ROOT + "/invitations/accept", recipientBearer, body("token", token));
        assertThat(accepted.statusCode()).isEqualTo(200);
        assertThat(json.readTree(accepted.body()).get("membership").get("role").asString()).isEqualTo("MEMBER");
        assertThat(post(ROOT + "/invitations/accept", recipientBearer, body("token", token)).body()).isEqualTo(INVALID);
        assertThat(get(INVITES, recipientBearer).statusCode()).isEqualTo(403);
        for (String path : List.of("/api/v1/projects", "/api/v1/policy", "/api/v1/admin", "/api/v1/organization", "/api/v1/unknown")) {
            assertThat(get(path, bearer).statusCode()).isEqualTo(403);
            assertThat(get(path, recipientBearer).statusCode()).isEqualTo(403);
        }
        assertThat(json.readTree(get("/api/v1/me", bearer).body()).propertyNames()).containsExactlyInAnyOrder("id", "email", "displayName", "emailVerified");
        assertThat(mail.deliveries).isEmpty();
        assertThat(output.getAll()).doesNotContain(token, bearer, recipientBearer);
    }

    @Test void everyEndpointRequiresActiveVerifiedBearerNotCookiesOrQuery() throws Exception {
        var unverified = user("pending@example.test", false);
        String unverifiedBearer = sessions.issue(unverified.id()).accessToken();
        var posts = new java.util.ArrayList<>(OnboardingRoutes.POSTS);
        posts.add(INVITES + "/" + UUID.randomUUID() + "/revoke");
        for (String path : posts) {
            assertThat(post(path, null, "{}").statusCode()).isEqualTo(401);
            assertThat(post(path, "A".repeat(43), "{}").statusCode()).isEqualTo(401);
            var denied = post(path, unverifiedBearer, "{}");
            assertThat(denied.statusCode()).isEqualTo(403);
            assertThat(json.readTree(denied.body()).get("code").asString()).isEqualTo("email_verification_required");
            assertThat(send(request(path + "?token=" + bearer).header("Cookie", "accessToken=" + bearer).POST(HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(401);
        }
        for (String path : List.of(ROOT, INVITES)) {
            assertThat(get(path, null).statusCode()).isEqualTo(401);
            assertThat(get(path, unverifiedBearer).statusCode()).isEqualTo(403);
        }
        jdbc.update("UPDATE accounts SET active = FALSE WHERE id = ?", owner.id());
        for (String path : posts) assertThat(post(path, bearer, "{}").statusCode()).isEqualTo(401);
        assertThat(get(ROOT, bearer).statusCode()).isEqualTo(401);
    }

    @Test void cancelStaleIdsValidationAndAllBodiesAreBounded() throws Exception {
        for (String value : List.of("", " ", "a".repeat(121), "first\nsecond", "first\u007fsecond")) {
            assertThat(post(ROOT + "/bootstrap", bearer, body("name", value)).statusCode()).isEqualTo(400);
        }
        var id = service.bootstrap(owner.id(), "Pending").bootstrap().id();
        var cancelled = post(ROOT + "/bootstrap/cancel", bearer, idBody(id));
        assertThat(cancelled.statusCode()).isEqualTo(204);
        assertThat(cancelled.body()).isEmpty();
        assertThat(post(ROOT + "/bootstrap/cancel", bearer, idBody(id)).statusCode()).isEqualTo(409);
        for (String path : OnboardingRoutes.POSTS) {
            assertThat(post(path, bearer, " ".repeat(4097)).statusCode()).isEqualTo(400);
            assertThat(post(path, bearer, "{").statusCode()).isEqualTo(400);
        }
        clock.advance(Duration.ofMinutes(5));
        assertThat(send(request(ROOT + "/bootstrap").header("Authorization", "Bearer " + bearer).header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofInputStream(() -> new ByteArrayInputStream(new byte[4097])))).statusCode()).isEqualTo(400);
        assertThat(send(request(ROOT + "/bootstrap").header("Authorization", "Bearer " + bearer).header("Content-Type", "text/plain")
            .POST(HttpRequest.BodyPublishers.ofString("{}"))).statusCode()).isEqualTo(400);
        assertThat(post(ROOT + "/bootstrap/activate", bearer, "{\"bootstrapId\":\"not-a-uuid\"}").statusCode()).isEqualTo(400);
        assertThat(post(ROOT + "/bootstrap/activate", bearer, "{}").statusCode()).isEqualTo(400);
        assertThat(post(ROOT + "/invitations/accept", bearer, "{}").body()).isEqualTo(INVALID);
    }

    @Test void exactCorsRoutesAndCsrfMethodsIncludingUuidRevokePattern() throws Exception {
        var posts = new java.util.ArrayList<>(OnboardingRoutes.POSTS);
        posts.add(INVITES + "/" + UUID.randomUUID() + "/revoke");
        for (String path : posts) {
            var response = client.send(request(path).header("Origin", "http://localhost:8765")
                    .header("Access-Control-Request-Method", "POST").header("Access-Control-Request-Headers", "Authorization, Content-Type")
                    .method("OPTIONS", HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
            assertThat(response.statusCode()).as(path).isEqualTo(200);
            assertThat(response.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
            assertThat(response.headers().allValues("access-control-allow-credentials")).isEmpty();
            for (String method : List.of("PATCH", "PUT", "DELETE", "HEAD")) {
                assertThat(send(request(path).header("Authorization", "Bearer " + bearer).method(method, HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
                assertThat(send(request(path).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", method)
                        .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
            }
            assertThat(post(path + "/", bearer, "{}").statusCode()).isEqualTo(403);
        }
        for (String path : List.of(ROOT, INVITES)) {
            var response = client.send(request(path).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", "GET")
                    .method("OPTIONS", HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
            assertThat(response.statusCode()).isEqualTo(200);
        }
        for (String path : List.of(INVITES + "/not-a-uuid/revoke", INVITES + "/a/b/revoke", ROOT + "/other", INVITES + "/" + UUID.randomUUID() + "/revoke/extra")) {
            assertThat(post(path, bearer, null).statusCode()).isEqualTo(403);
            assertThat(send(request(path).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", "POST")
                    .method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        }
        assertThat(send(request(ROOT).header("Origin", "https://evil.example").header("Authorization", "Bearer " + bearer).GET()).statusCode()).isEqualTo(403);
        assertThat(send(request(ROOT).header("Origin", "http://localhost:8765").header("Access-Control-Request-Method", "GET")
                .header("Access-Control-Request-Headers", "X-Unapproved").method("OPTIONS", HttpRequest.BodyPublishers.noBody())).statusCode()).isEqualTo(403);
        var actual = send(request(ROOT + "/bootstrap").header("Origin", "http://localhost:8765").header("Authorization", "Bearer " + bearer)
                .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body("name", "Cors"))));
        assertThat(actual.statusCode()).isEqualTo(200);
        assertThat(actual.headers().firstValue("access-control-allow-origin")).hasValue("http://localhost:8765");
    }

    @Test void tenantThrottleCountsMalformedBodiesAndCannotBeResetByNewBearer() throws Exception {
        for (int i = 0; i < 20; i++) assertThat(post(ROOT + "/invitations/preview", bearer, "{").statusCode()).isEqualTo(400);
        var limited = post(ROOT + "/bootstrap", sessions.issue(owner.id()).accessToken(), body("name", "New"));
        assertThat(limited.statusCode()).isEqualTo(429);
        assertThat(limited.body()).isEqualTo("{\"code\":\"rate_limited\",\"message\":\"Too many requests. Try again later.\"}");
        assertThat(get(ROOT, bearer).statusCode()).isEqualTo(200);
        clock.advance(Duration.ofMinutes(5));
        assertThat(post(ROOT + "/bootstrap", bearer, body("name", "New")).statusCode()).isEqualTo(200);
    }

    @Test void sourceThrottleIgnoresForwardedHeadersAcrossAccounts() throws Exception {
        for (int i = 0; i < 80; i++) {
            String session = sessions.issue(user("source" + i + "@example.test", true).id()).accessToken();
            var result = send(request(ROOT + "/invitations/preview").header("Authorization", "Bearer " + session)
                    .header("X-Forwarded-For", "192.0.2." + i).header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString("{")));
            assertThat(result.statusCode()).isEqualTo(400);
        }
        assertThat(post(ROOT + "/bootstrap", bearer, body("name", "Blocked")).statusCode()).isEqualTo(429);
    }

    @Test void ownerScopeWrongRecipientRevocationAndSuspensionReturnFixedErrors() throws Exception {
        activateOwner();
        var other = user("other@example.test", true);
        String otherBearer = sessions.issue(other.id()).accessToken();
        service.activate(other.id(), service.bootstrap(other.id(), "Other organization").bootstrap().id());
        var issued = service.issue(owner.id(), "recipient@example.test");
        String path = INVITES + "/" + issued.invitation().id() + "/revoke";
        var cross = post(path, otherBearer, null);
        assertThat(cross.statusCode()).isEqualTo(404);
        assertThat(cross.body()).isEqualTo("{\"code\":\"invitation_not_found\",\"message\":\"Invitation was not found.\"}");
        for (String action : List.of("preview", "accept")) {
            var wrong = post(ROOT + "/invitations/" + action, otherBearer, body("token", issued.token()));
            assertThat(wrong.statusCode()).isEqualTo(400);
            assertThat(wrong.body()).isEqualTo(INVALID);
        }
        assertThat(post(path, bearer, "{}").statusCode()).isEqualTo(400);
        assertThat(post(path, bearer, null).statusCode()).isEqualTo(204);
        assertThat(post(path, bearer, null).statusCode()).isEqualTo(204);
        jdbc.update("UPDATE organization_memberships SET status = 'SUSPENDED' WHERE account_id = ?", owner.id());
        assertThat(get(ROOT, bearer).statusCode()).isEqualTo(403);
        assertThat(json.readTree(get(INVITES, bearer).body()).get("code").asString()).isEqualTo("organization_unavailable");
        assertThat(post(path, bearer, null).statusCode()).isEqualTo(403);
    }
}