package com.bahirledger.backend.onboarding;

import java.util.Set;
import jakarta.servlet.http.HttpServletRequest;

/** Shared exact security/body-limit boundary. Not a prefix authorization rule. */
public final class OnboardingRoutes {
    private OnboardingRoutes() {}
    public static final String UUID_PATTERN = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
    public static final String INVITATIONS = "/api/v1/organization/invitations";
    public static final String REVOKE_CORS = INVITATIONS + "/{id:" + UUID_PATTERN + "}/revoke";
    public static final Set<String> POSTS = Set.of(
            "/api/v1/onboarding/bootstrap", "/api/v1/onboarding/bootstrap/activate",
            "/api/v1/onboarding/bootstrap/cancel", "/api/v1/onboarding/invitations/preview",
            "/api/v1/onboarding/invitations/accept", INVITATIONS);
    public static boolean mutation(HttpServletRequest request) {
        return request.getMethod().equals("POST") && (POSTS.contains(request.getServletPath())
                || request.getServletPath().matches(INVITATIONS + "/" + UUID_PATTERN + "/revoke"));
    }
    public static boolean matches(HttpServletRequest request) {
        return mutation(request) || (request.getMethod().equals("GET")
                && Set.of("/api/v1/onboarding", INVITATIONS).contains(request.getServletPath()));
    }
}