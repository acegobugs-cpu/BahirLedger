package com.bahirledger.backend;

import java.util.Map;
import java.util.Set;

import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;

import static org.assertj.core.api.Assertions.assertThat;

class OpenApiContractTest {
    @Test
    void contractParsesListsOnlyImplementedRoutesAndHasResolvableReferences() throws Exception {
        try (var input = getClass().getResourceAsStream("/contracts/openapi.yaml")) {
            assertThat(input).isNotNull();
            Map<String, Object> document = new Yaml(new SafeConstructor(new LoaderOptions())).load(input);
            assertThat(document).containsEntry("openapi", "3.1.0");
            var paths = (Map<?, ?>) document.get("paths");
            assertThat(paths.keySet()).isEqualTo(Set.of("/api/v1/health", "/api/v1/auth/login", "/api/v1/auth/register", "/api/v1/me", "/api/v1/auth/logout",
                    "/api/v1/auth/email-verification/confirm", "/api/v1/auth/email-verification/resend"));
            var components = (Map<?, ?>) document.get("components");
            var schemas = (Map<?, ?>) components.get("schemas");
            var user = (Map<?, ?>) schemas.get("User");
            assertThat(((java.util.List<?>) user.get("required")).contains("emailVerified")).isTrue();
            assertThat(((Map<?, ?>) ((Map<?, ?>) user.get("properties")).get("emailVerified")).get("type")).isEqualTo("boolean");
            for (String path : Set.of("/api/v1/auth/email-verification/confirm", "/api/v1/auth/email-verification/resend")) {
                assertThat(((Map<?, ?>) paths.get(path)).keySet()).isEqualTo(Set.of("post"));
            }
            checkReferences(document, document);
        }
    }

    private void checkReferences(Object node, Map<String, Object> document) {
        if (node instanceof Map<?, ?> map) {
            if (map.get("$ref") instanceof String reference) {
                assertThat(reference).startsWith("#/");
                Object target = document;
                for (String segment : reference.substring(2).split("/")) {
                    assertThat(target).isInstanceOf(Map.class);
                    target = ((Map<?, ?>) target).get(segment);
                    assertThat(target).as("Reference %s", reference).isNotNull();
                }
            }
            map.values().forEach(value -> checkReferences(value, document));
        } else if (node instanceof Iterable<?> values) {
            values.forEach(value -> checkReferences(value, document));
        }
    }
}