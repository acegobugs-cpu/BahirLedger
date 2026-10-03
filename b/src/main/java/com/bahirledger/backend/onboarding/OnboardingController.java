package com.bahirledger.backend.onboarding;

import java.util.UUID;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import com.bahirledger.backend.auth.AccountStore;
import com.bahirledger.backend.auth.UserView;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class OnboardingController {
    private final OnboardingService service;
    public OnboardingController(OnboardingService service) { this.service = service; }

    public record NameRequest(@NotBlank @Size(max = 120) String name) {
        public NameRequest { name = name == null ? null : name.strip(); }
        @Override public String toString() { return "NameRequest[redacted]"; }
    }
    public record BootstrapRequest(@NotNull UUID bootstrapId) {}
    public record EmailRequest(@NotBlank @Email @Size(max = 254) String email) {
        public EmailRequest { email = AccountStore.normalizeEmail(email); }
        @Override public String toString() { return "EmailRequest[redacted]"; }
    }
    public record TokenRequest(String token) {
        @Override public String toString() { return "TokenRequest[redacted]"; }
    }
    @GetMapping("/onboarding")
    public OnboardingService.Context context(@AuthenticationPrincipal UserView user) { return service.context(user.id()); }
    @PostMapping(value = "/onboarding/bootstrap", consumes = "application/json")
    public OnboardingService.Context bootstrap(@AuthenticationPrincipal UserView user, @Valid @RequestBody NameRequest body) {
        return service.bootstrap(user.id(), body.name());
    }
    @PostMapping(value = "/onboarding/bootstrap/activate", consumes = "application/json")
    public OnboardingService.Context activate(@AuthenticationPrincipal UserView user, @Valid @RequestBody BootstrapRequest body) {
        return service.activate(user.id(), body.bootstrapId());
    }
    @PostMapping(value = "/onboarding/bootstrap/cancel", consumes = "application/json")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void cancel(@AuthenticationPrincipal UserView user, @Valid @RequestBody BootstrapRequest body) {
        service.cancel(user.id(), body.bootstrapId());
    }
    @GetMapping("/organization/invitations")
    public OnboardingService.InvitationList invitations(@AuthenticationPrincipal UserView user) { return service.invitations(user.id()); }
    @PostMapping(value = "/organization/invitations", consumes = "application/json")
    @ResponseStatus(HttpStatus.CREATED)
    public OnboardingService.IssuedInvitation issue(@AuthenticationPrincipal UserView user, @Valid @RequestBody EmailRequest body) {
        return service.issue(user.id(), body.email());
    }
    @PostMapping("/organization/invitations/{id}/revoke")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(@AuthenticationPrincipal UserView user, @PathVariable UUID id) { service.revoke(user.id(), id); }
    @PostMapping(value = "/onboarding/invitations/preview", consumes = "application/json")
    public OnboardingService.Preview preview(@AuthenticationPrincipal UserView user, @RequestBody TokenRequest body) {
        return service.preview(user.id(), body.token());
    }
    @PostMapping(value = "/onboarding/invitations/accept", consumes = "application/json")
    public OnboardingService.Context accept(@AuthenticationPrincipal UserView user, @RequestBody TokenRequest body) {
        return service.accept(user.id(), body.token());
    }
}