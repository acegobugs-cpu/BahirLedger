package com.bahirledger.backend.auth;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class AuthController {
    private final AuthService auth;
    private final SessionStore sessions;
    private final EmailVerificationService verification;

    public AuthController(AuthService auth, SessionStore sessions, EmailVerificationService verification) {
        this.auth = auth;
        this.sessions = sessions;
        this.verification = verification;
    }

    @PostMapping(value = "/auth/register", consumes = "application/json")
    public AuthService.RegisterResponse register(@Valid @RequestBody RegisterRequest request) {
        return auth.register(request);
    }

    @PostMapping(value = "/auth/login", consumes = "application/json")
    public AuthService.LoginResponse login(@Valid @RequestBody LoginRequest request) {
        return auth.login(request);
    }

    @GetMapping("/me")
    public UserView me(@AuthenticationPrincipal UserView user) { return user; }

    @PostMapping(value = "/auth/email-verification/confirm", consumes = "application/json")
    public UserView confirm(@AuthenticationPrincipal UserView user, @RequestBody VerificationRequest request) {
        return verification.confirm(user.id(), request.token());
    }

    @PostMapping("/auth/email-verification/resend")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void resend(@AuthenticationPrincipal UserView user) {
        verification.resend(user.id());
    }

    @PostMapping("/auth/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(HttpServletRequest request) {
        sessions.revoke((String) request.getAttribute(BearerSessionFilter.SESSION_DIGEST));
    }
}