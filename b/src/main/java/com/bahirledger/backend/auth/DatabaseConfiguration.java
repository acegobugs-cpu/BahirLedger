package com.bahirledger.backend.auth;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;

@Configuration(proxyBeanMethods = false)
public class DatabaseConfiguration {

    @Bean
    @ConditionalOnMissingBean(DataSource.class)
    DataSource dataSource(Environment environment) {
        boolean local = environment.acceptsProfiles(Profiles.of("local"));

        String rawUrl = environment.getProperty("bahirledger.database.url", "").trim();
        String username = environment.getProperty("bahirledger.database.username", "").trim();
        String password = environment.getProperty("bahirledger.database.password", "");

        // Format raw PostgreSQL URL if "jdbc:" prefix was omitted
        String url = normalizeJdbcUrl(rawUrl, local);

        validate(local, url, username, password);

        var config = new HikariConfig();
        config.setJdbcUrl(url);
        config.setDriverClassName(local ? "org.h2.Driver" : "org.postgresql.Driver");
        config.setUsername(local ? "sa" : username);
        config.setPassword(local ? "" : password);
        config.setMaximumPoolSize(8);
        config.setConnectionTimeout(5000);

        return new HikariDataSource(config);
    }

    private static String normalizeJdbcUrl(String rawUrl, boolean local) {
        if (rawUrl.isBlank() || local) {
            return rawUrl;
        }
        if (rawUrl.startsWith("postgresql://")) {
            return "jdbc:" + rawUrl;
        }
        return rawUrl;
    }

    static void validate(boolean local, String url, String username, String password) {
        if (local) {
            if (!url.startsWith("jdbc:h2:file:")) {
                throw new IllegalStateException("The local profile requires a file-backed H2 database.");
            }
        } else if (!url.startsWith("jdbc:postgresql:") || username.isBlank() || password.isBlank()) {
            throw new IllegalStateException("Configure bahirledger.database.url, username and password in application.properties for PostgreSQL.");
        }
    }
}