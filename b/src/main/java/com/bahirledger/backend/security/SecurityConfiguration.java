package com.bahirledger.backend.security;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.List;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.ApiErrors;
import com.bahirledger.backend.auth.ApiException;
import com.bahirledger.backend.auth.BearerSessionFilter;
import com.bahirledger.backend.auth.LoginThrottle;
import com.bahirledger.backend.auth.SessionStore;
import com.bahirledger.backend.auth.VerificationThrottle;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.server.ServerHttpResponse;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CsrfFilter;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.security.web.csrf.CsrfTokenRepository;
import org.springframework.security.web.csrf.DefaultCsrfToken;
import org.springframework.security.web.util.matcher.RequestMatcher;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.DefaultCorsProcessor;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

/** Managed bearer sign-in. Organization SSO and tenant membership are not implemented yet. */
@Configuration(proxyBeanMethods = false)
public class SecurityConfiguration {

    @Bean
    UserDetailsService noImplicitAccounts() {
        // The explicit JSON login service is the only password authentication path.
        // Prevent Boot from generating a password or adding an implicit fallback account.
        return username -> { throw new UsernameNotFoundException("Implicit sign-in is disabled"); };
    }

    @Bean
    Clock authClock() { return Clock.systemUTC(); }

    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(12); }

    @Bean
    CorsConfigurationSource corsConfigurationSource(@Value("${bahirledger.auth.web-origin:}") String origin) {
        var source = new UrlBasedCorsConfigurationSource();
        if (origin.isEmpty()) {
            source.registerCorsConfiguration("/**", new CorsConfiguration());
            return source;
        }
        validateOrigin(origin);
        var cors = new CorsConfiguration();
        cors.setAllowedOrigins(List.of(origin));
        cors.setAllowedMethods(List.of("POST"));
        cors.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        cors.setAllowCredentials(false);
        cors.setMaxAge(600L);
        source.registerCorsConfiguration("/api/v1/auth/login", cors);
        source.registerCorsConfiguration("/api/v1/auth/register", cors);
        source.registerCorsConfiguration("/api/v1/auth/logout", cors);
        source.registerCorsConfiguration("/api/v1/auth/email-verification/confirm", cors);
        source.registerCorsConfiguration("/api/v1/auth/email-verification/resend", cors);
        var readCors = new CorsConfiguration(cors);
        readCors.setAllowedMethods(List.of("GET"));
        source.registerCorsConfiguration("/api/v1/me", readCors);
        source.registerCorsConfiguration("/api/v1/health", readCors);
        // Spring 7 skips null CORS configuration, including preflights: explicitly deny all others.
        source.registerCorsConfiguration("/**", new CorsConfiguration());
        return source;
    }

    static void validateOrigin(String origin) {
        try {
            URI uri = URI.create(origin);
            if (!List.of("http", "https").contains(uri.getScheme())
                    || !List.of("localhost", "127.0.0.1", "[::1]").contains(uri.getHost())
                    || uri.getRawUserInfo() != null || uri.getRawQuery() != null || uri.getRawFragment() != null
                    || !uri.getRawPath().isEmpty() || uri.getPort() < 1 || uri.getPort() > 65535) {
                throw new IllegalArgumentException();
            }
        } catch (RuntimeException invalid) {
            throw new IllegalStateException("BAHIRLEDGER_WEB_ORIGIN must be one exact localhost HTTP(S) origin with a port, or empty.");
        }
    }

    @Bean
    SecurityFilterChain apiSecurity(HttpSecurity http, SessionStore sessions, AccountStore accounts,
            LoginThrottle throttle, VerificationThrottle verificationThrottle,
            CorsConfigurationSource corsConfigurationSource) throws Exception {
        RequestMatcher login = request -> request.getMethod().equals("POST")
                && request.getServletPath().equals("/api/v1/auth/login");
        RequestMatcher register = request -> request.getMethod().equals("POST")
            && request.getServletPath().equals("/api/v1/auth/register");
        RequestMatcher logout = request -> request.getMethod().equals("POST")
                && request.getServletPath().equals("/api/v1/auth/logout");
        RequestMatcher confirm = request -> request.getMethod().equals("POST")
            && request.getServletPath().equals("/api/v1/auth/email-verification/confirm");
        RequestMatcher resend = request -> request.getMethod().equals("POST")
            && request.getServletPath().equals("/api/v1/auth/email-verification/resend");
        var corsFilter = new CorsFilter(corsConfigurationSource);
        corsFilter.setCorsProcessor(new DefaultCorsProcessor() {
            @Override protected void rejectRequest(ServerHttpResponse response) throws IOException {
                response.setStatusCode(HttpStatus.FORBIDDEN);
                response.getHeaders().setContentType(MediaType.APPLICATION_JSON);
                response.getHeaders().setCacheControl("no-store");
                response.getBody().write("{\"code\":\"forbidden\",\"message\":\"Request is not permitted.\"}"
                        .getBytes(StandardCharsets.UTF_8));
                response.flush();
            }
        });
        return http
                .cors(AbstractHttpConfigurer::disable)
                .addFilterAt(corsFilter, CorsFilter.class)
                .authorizeHttpRequests(access -> access
                        .requestMatchers(HttpMethod.GET, "/api/v1/health").permitAll()
                        .requestMatchers(login, register).permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/me").authenticated()
                        .requestMatchers(logout, confirm, resend).authenticated()
                        // Future tenant endpoints must require verified email AND tenant membership.
                        // Neither account-only sessions nor verification alone grant tenant access.
                        .anyRequest().denyAll())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .requestCache(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .logout(AbstractHttpConfigurer::disable)
                // No ambient cookie authentication: only these exact POST routes bypass CSRF.
                .csrf(csrf -> csrf.ignoringRequestMatchers(login, register, logout, confirm, resend)
                        .csrfTokenRepository(new CsrfTokenRepository() {
                            // All other unsafe routes remain denied; never create an HTTP session/cookie.
                            @Override public CsrfToken generateToken(HttpServletRequest request) {
                                return new DefaultCsrfToken("X-CSRF-TOKEN", "_csrf", UUID.randomUUID().toString());
                            }
                            @Override public void saveToken(CsrfToken token, HttpServletRequest request, HttpServletResponse response) {}
                            @Override public CsrfToken loadToken(HttpServletRequest request) { return null; }
                        }))
                .addFilterBefore(new BearerSessionFilter(sessions, accounts, throttle, verificationThrottle), CsrfFilter.class)
                .exceptionHandling(errors -> errors
                        .authenticationEntryPoint((request, response, exception) -> ApiErrors.write(response, ApiException.unauthorized()))
                        .accessDeniedHandler((request, response, exception) -> ApiErrors.write(response, ApiException.forbidden())))
                .build();
    }
}

/*
For your app, a practical direction is **BahirLedger-managed sign-in by default, with optional organization SSO**. That would replace the earlier, overly restrictive “organization SSO is mandatory” plan.
agreed

fix the docs and plan(docs/plan it went all over the place after making auth step 2), start implementing the bahirledger managed signin first. both frontend and backend,
*/