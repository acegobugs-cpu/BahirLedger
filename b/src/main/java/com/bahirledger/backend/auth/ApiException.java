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

    public static ApiException validation() {
        return new ApiException(400, "invalid_request", "Request is invalid.");
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