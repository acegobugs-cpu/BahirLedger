package com.bahirledger.backend.auth;

import java.util.UUID;

/** Public identity only; deliberately no membership or credential fields. */
public record UserView(UUID id, String email, String displayName) {}