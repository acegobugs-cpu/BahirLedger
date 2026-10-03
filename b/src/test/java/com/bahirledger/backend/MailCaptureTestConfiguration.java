package com.bahirledger.backend;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import com.bahirledger.backend.auth.mail.VerificationMailSender;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

/** Isolated mail double; never writes mail to the filesystem or connects to SMTP. */
@TestConfiguration(proxyBeanMethods = false)
public class MailCaptureTestConfiguration {
    @Bean @Primary
    public CapturingMailSender capturingMailSender() { return new CapturingMailSender(); }

    public static final class CapturingMailSender implements VerificationMailSender {
        public final List<Delivery> deliveries = new CopyOnWriteArrayList<>();
        public volatile boolean fail;
        public volatile Runnable beforeSend = () -> {};
        @Override public void send(String email, String token) {
            beforeSend.run();
            if (fail) throw new IllegalStateException("synthetic-mail-secret-marker");
            deliveries.add(new Delivery(email, token));
        }
        public void reset() { deliveries.clear(); fail = false; beforeSend = () -> {}; }
    }

    public record Delivery(String email, String token) {
        @Override public String toString() { return "Delivery[REDACTED]"; }
    }
}