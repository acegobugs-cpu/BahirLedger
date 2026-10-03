package com.bahirledger.backend.auth;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Collections;
import java.util.List;

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

    public BearerSessionFilter(SessionStore sessions, AccountStore accounts, LoginThrottle throttle) {
        this.sessions = sessions;
        this.accounts = accounts;
        this.throttle = throttle;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (request.getServletPath().startsWith("/api/v1/auth/") || request.getServletPath().equals("/api/v1/me")) {
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
                authenticate(request);
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