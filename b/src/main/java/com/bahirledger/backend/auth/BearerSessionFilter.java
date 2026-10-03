package com.bahirledger.backend.auth;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.List;

import com.bahirledger.backend.onboarding.OnboardingRoutes;
import com.bahirledger.backend.onboarding.TenantThrottle;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.dao.DataAccessException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

/** Installed only in the security chain; no servlet-container duplicate registration. */
public final class BearerSessionFilter extends OncePerRequestFilter {
    public static final String SESSION_DIGEST = BearerSessionFilter.class.getName() + ".digest";
    private final SessionStore sessions;
    private final AccountStore accounts;
    private final LoginThrottle throttle;
        private final VerificationThrottle verificationThrottle;
    private final TenantThrottle tenantThrottle;

        public BearerSessionFilter(SessionStore sessions, AccountStore accounts, LoginThrottle throttle,
            VerificationThrottle verificationThrottle, TenantThrottle tenantThrottle) {
        this.sessions = sessions;
        this.accounts = accounts;
        this.throttle = throttle;
        this.verificationThrottle = verificationThrottle;
        this.tenantThrottle = tenantThrottle;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (request.getServletPath().startsWith("/api/v1/auth/") || request.getServletPath().equals("/api/v1/me")
            || request.getServletPath().startsWith("/api/v1/onboarding") || request.getServletPath().startsWith("/api/v1/organization")) {
            response.setHeader("Cache-Control", "no-store");
        }
        HttpServletRequest filtered = request;
        try {
            if (request.getMethod().equals("POST")
                    && (request.getServletPath().equals("/api/v1/auth/login")
                        || request.getServletPath().equals("/api/v1/auth/register"))) {
                // Never trust forwarded IP headers; bound parsing even for chunked bodies.
                throttle.checkSource(request.getRemoteAddr());
                byte[] body = request.getInputStream().readNBytes(4097);
                if (body.length > 4096) throw ApiException.validation();
                filtered = bodyRequest(request, body);
            } else {
                boolean confirm = request.getMethod().equals("POST")
                        && request.getServletPath().equals("/api/v1/auth/email-verification/confirm");
                boolean resend = request.getMethod().equals("POST")
                        && request.getServletPath().equals("/api/v1/auth/email-verification/resend");
                authenticate(request);
                if (OnboardingRoutes.matches(request)) {
                    var authentication = SecurityContextHolder.getContext().getAuthentication();
                    if (authentication == null) throw ApiException.unauthorized();
                    var user = (UserView) authentication.getPrincipal();
                    if (!user.emailVerified()) throw ApiException.emailVerificationRequired();
                    if (OnboardingRoutes.mutation(request)) {
                        tenantThrottle.check(user.id(), request.getRemoteAddr());
                        byte[] body = request.getInputStream().readNBytes(4097);
                        if (body.length > 4096) throw ApiException.validation();
                        if (request.getServletPath().endsWith("/revoke") && body.length != 0) throw ApiException.validation();
                        filtered = bodyRequest(request, body);
                    }
                }
                if (confirm || resend) {
                    var authentication = SecurityContextHolder.getContext().getAuthentication();
                    if (authentication == null) throw ApiException.unauthorized();
                    verificationThrottle.checkSource(confirm, request.getRemoteAddr());
                    var user = (UserView) authentication.getPrincipal();
                    // Already-verified resend is a no-op; no account email budget is spent.
                    if (confirm || !user.emailVerified()) verificationThrottle.checkAccount(confirm, user.id());
                    if (confirm) {
                        byte[] body = request.getInputStream().readNBytes(4097);
                        if (body.length > 4096) throw ApiException.validation();
                        filtered = bodyRequest(request, body);
                    } else if (request.getInputStream().read() != -1) {
                        throw ApiException.validation();
                    }
                }
            }
        } catch (ApiException error) {
            ApiErrors.write(response, error);
            return;
        } catch (DataAccessException error) {
            ApiErrors.write(response, ApiException.unavailable());
            return;
        }
        chain.doFilter(filtered, response);
    }

    private void authenticate(HttpServletRequest request) {
        List<String> headers = Collections.list(request.getHeaders("Authorization"));
        if (headers.isEmpty()) return;
        if (headers.size() != 1 || !headers.getFirst().matches("(?i:Bearer) [A-Za-z0-9_-]{43}")) {
            throw ApiException.unauthorized();
        }
        String digest = SessionStore.digest(headers.getFirst().substring(7));
        var userId = sessions.findUser(digest).orElseThrow(ApiException::unauthorized);
        var user = accounts.findActiveUser(userId).orElseThrow(ApiException::unauthorized);
        var context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(UsernamePasswordAuthenticationToken.authenticated(user, null, List.of()));
        SecurityContextHolder.setContext(context);
        request.setAttribute(SESSION_DIGEST, digest);
    }

    private static HttpServletRequest bodyRequest(HttpServletRequest request, byte[] body) {
        return new HttpServletRequestWrapper(request) {
            @Override public ServletInputStream getInputStream() {
                var input = new ByteArrayInputStream(body);
                return new ServletInputStream() {
                    @Override public int read() { return input.read(); }
                    @Override public boolean isFinished() { return input.available() == 0; }
                    @Override public boolean isReady() { return true; }
                    @Override public void setReadListener(ReadListener listener) {
                        throw new UnsupportedOperationException("Synchronous request body only");
                    }
                };
            }
        };
    }
}