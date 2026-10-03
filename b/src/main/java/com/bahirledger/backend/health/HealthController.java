package com.bahirledger.backend.health;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    @GetMapping("/api/v1/health")
    public Health health() {
        return new Health("UP");
    }

    public record Health(String status) {}
}