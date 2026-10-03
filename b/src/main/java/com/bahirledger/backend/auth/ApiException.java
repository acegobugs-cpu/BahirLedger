package com.bahirledger.backend.auth;

public final class ApiException extends RuntimeException {
    private final int status;
    private final String code;

    private ApiException(int status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }

    public int status() { return status; }
    public String code() { return code; }

    public static ApiException invalidCredentials() {
        return new ApiException(401, "invalid_credentials", "Email or password is incorrect.");
    }

    public static ApiException unauthorized() {
        return new ApiException(401, "unauthorized", "Authentication is required.");
    }

    public static ApiException forbidden() {
        return new ApiException(403, "forbidden", "Request is not permitted.");
    }

    public static ApiException emailVerificationRequired() {
        return new ApiException(403, "email_verification_required", "Email verification is required.");
    }

    public static ApiException organizationUnavailable() {
        return new ApiException(403, "organization_unavailable", "Organization is unavailable.");
    }

    public static ApiException membershipExists() {
        return new ApiException(409, "membership_exists", "Account already has an organization membership.");
    }

    public static ApiException bootstrapUnavailable() {
        return new ApiException(409, "bootstrap_unavailable", "Organization setup is unavailable.");
    }

    public static ApiException invitationUnavailable() {
        return new ApiException(409, "invitation_unavailable", "Invitation is unavailable.");
    }

    public static ApiException invalidInvitation() {
        return new ApiException(400, "invalid_invitation", "Invitation is invalid or unavailable.");
    }

    public static ApiException invitationNotFound() {
        return new ApiException(404, "invitation_not_found", "Invitation was not found.");
    }

    public static ApiException tenantThrottled() {
        return new ApiException(429, "rate_limited", "Too many requests. Try again later.");
    }

    public static ApiException validation() {
        return new ApiException(400, "invalid_request", "Request is invalid.");
    }

    public static ApiException invalidVerificationToken() {
        return new ApiException(400, "invalid_verification_token", "Verification token is invalid or expired.");
    }

    public static ApiException throttled() {
        return new ApiException(429, "too_many_requests", "Too many requests. Try again later.");
    }

    public static ApiException unavailable() {
        return new ApiException(503, "service_unavailable", "Service is temporarily unavailable.");
    }

    public static ApiException conflict() {
        return new ApiException(409, "conflict", "Email is already registered.");
    }
}