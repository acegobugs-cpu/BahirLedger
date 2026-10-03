package com.bahirledger.backend.auth;

import java.io.IOException;

import jakarta.servlet.http.HttpServletResponse;
import org.springframework.dao.DataAccessException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiErrors {
    public record ErrorBody(String code, String message) {}

    // All strings come from fixed server constants, never request/exception text.
    public static void write(HttpServletResponse response, ApiException error) throws IOException {
        response.setStatus(error.status());
        response.setContentType("application/json");
        response.setHeader("Cache-Control", "no-store");
        response.getWriter().write("{\"code\":\"" + error.code() + "\",\"message\":\"" + error.getMessage() + "\"}");
    }

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ErrorBody> api(ApiException error) {
        return ResponseEntity.status(error.status()).header("Cache-Control", "no-store")
                .body(new ErrorBody(error.code(), error.getMessage()));
    }

        @ExceptionHandler({MethodArgumentNotValidException.class, HttpMessageNotReadableException.class,
            HttpMediaTypeNotSupportedException.class})
    ResponseEntity<ErrorBody> validation(Exception ignored) { return api(ApiException.validation()); }

    @ExceptionHandler(DataAccessException.class)
    ResponseEntity<ErrorBody> database(Exception ignored) { return api(ApiException.unavailable()); }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorBody> unexpected(Exception ignored) {
        return ResponseEntity.internalServerError().header("Cache-Control", "no-store")
                .body(new ErrorBody("internal_error", "Request could not be completed."));
    }
}