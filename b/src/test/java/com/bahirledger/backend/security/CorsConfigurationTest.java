package com.bahirledger.backend.security;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import static org.assertj.core.api.Assertions.*;

class CorsConfigurationTest {
    @ParameterizedTest
    @ValueSource(strings = {"*", "http://*.localhost:8765", "http://localhost:8765/", "https://example.com:443",
            "http://localhost:8765?query", "http://user@localhost:8765", "http://localhost", "null"})
    void invalidOriginsFailStartup(String origin) {
        assertThatThrownBy(() -> SecurityConfiguration.validateOrigin(origin)).isInstanceOf(IllegalStateException.class);
    }

    @ParameterizedTest
    @ValueSource(strings = {"http://localhost:8765", "http://127.0.0.1:1234", "http://[::1]:8765"})
    void exactLoopbackOriginsAreSupported(String origin) {
        assertThatCode(() -> SecurityConfiguration.validateOrigin(origin)).doesNotThrowAnyException();
    }
}