package com.bahirledger.backend.auth.mail;

import java.net.URI;
import java.nio.file.Path;
import java.util.List;
import java.util.Properties;

import com.bahirledger.backend.auth.ApiException;
import jakarta.mail.internet.InternetAddress;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSenderImpl;

@Configuration(proxyBeanMethods = false)
public class VerificationMailConfiguration {
    @Bean
    VerificationMailSender verificationMailSender(Environment environment) {
        String mode = environment.getProperty("bahirledger.mail.mode", "disabled");
        if (mode.equals("disabled")) return (email, token) -> { throw ApiException.unavailable(); };
        // Explicit local-only development escape hatch; never combine local with deployment profiles.
        boolean local = List.of(environment.getActiveProfiles()).equals(List.of("local"));
        String origin = environment.getProperty("bahirledger.mail.verification-web-origin", "");
        validateOrigin(origin, local);
        if (mode.equals("file") && local) {
            var outbox = new LocalFileOutbox(Path.of(System.getProperty("user.home")));
            return (email, token) -> outbox.deliver("To: " + email + "\nSubject: Verify your BahirLedger email\n\n" + body(origin, token));
        }
        if (!mode.equals("smtp")) throw invalidConfiguration();
        var smtp = smtp(environment, local);
        String from = environment.getProperty("bahirledger.mail.smtp.from", "");
        return (email, token) -> {
            try {
                var message = new SimpleMailMessage();
                message.setFrom(from);
                message.setTo(email);
                message.setSubject("Verify your BahirLedger email");
                message.setText(body(origin, token));
                smtp.send(message);
            } catch (RuntimeException unavailable) {
                throw ApiException.unavailable();
            }
        };
    }

    static String body(String origin, String token) {
        return "Confirm this email for your BahirLedger account within 30 minutes.\n"
                + "Sign in to the same account, then open:\n" + origin + "/#/verify-email?token=" + token
                + "\n\nOr paste this verification token in the app:\n" + token
                + "\n\nIf you did not request this, ignore this message.\n";
    }

    static void validateOrigin(String origin, boolean local) {
        try {
            URI uri = URI.create(origin);
            boolean secure = "https".equals(uri.getScheme());
            boolean localHttp = local && "http".equals(uri.getScheme()) && loopback(uri.getHost());
            if ((!secure && !localHttp) || uri.getHost() == null || uri.getRawUserInfo() != null
                    || uri.getRawQuery() != null || uri.getRawFragment() != null || !uri.getRawPath().isEmpty()
                    || uri.getPort() == 0 || uri.getPort() > 65535 || origin.endsWith(":")) {
                throw invalidConfiguration();
            }
        } catch (RuntimeException invalid) {
            throw invalidConfiguration();
        }
    }

    static JavaMailSenderImpl smtp(Environment environment, boolean local) {
        try {
            String host = environment.getProperty("bahirledger.mail.smtp.host", "");
            int port = Integer.parseInt(environment.getProperty("bahirledger.mail.smtp.port", "587"));
            String from = environment.getProperty("bahirledger.mail.smtp.from", "");
            String tls = environment.getProperty("bahirledger.mail.smtp.starttls", "true");
            if (!host.matches("[A-Za-z0-9.:-]+") || port < 1 || port > 65535
                    || !List.of("true", "false").contains(tls)
                    || (tls.equals("false") && !(local && loopback(host)))
                    || from.contains("\r") || from.contains("\n")) throw invalidConfiguration();
            var address = new InternetAddress(from, true);
            address.validate();
            if (!address.getAddress().equals(from) || !from.contains("@")) throw invalidConfiguration();
            var sender = new JavaMailSenderImpl();
            sender.setHost(host);
            sender.setPort(port);
            sender.setDefaultEncoding("UTF-8");
            String username = environment.getProperty("bahirledger.mail.smtp.username", "");
            String password = environment.getProperty("bahirledger.mail.smtp.password", "");
            if (username.isEmpty() != password.isEmpty()) throw invalidConfiguration();
            if (!username.isEmpty()) {
                sender.setUsername(username);
                sender.setPassword(password);
            }
            var properties = new Properties();
            properties.setProperty("mail.smtp.auth", Boolean.toString(!username.isEmpty()));
            properties.setProperty("mail.smtp.starttls.enable", tls);
            properties.setProperty("mail.smtp.starttls.required", tls);
            properties.setProperty("mail.smtp.ssl.checkserveridentity", "true");
            properties.setProperty("mail.smtp.connectiontimeout", "5000");
            properties.setProperty("mail.smtp.timeout", "5000");
            properties.setProperty("mail.smtp.writetimeout", "5000");
            properties.setProperty("mail.debug", "false");
            sender.setJavaMailProperties(properties);
            return sender;
        } catch (Exception invalid) {
            throw invalidConfiguration();
        }
    }

    private static boolean loopback(String host) {
        return host != null && List.of("localhost", "127.0.0.1", "[::1]", "::1").contains(host);
    }

    private static IllegalStateException invalidConfiguration() {
        return new IllegalStateException("Invalid verification mail configuration. Check BAHIRLEDGER_MAIL_MODE, BAHIRLEDGER_VERIFICATION_WEB_ORIGIN and BAHIRLEDGER_SMTP_* settings.");
    }
}