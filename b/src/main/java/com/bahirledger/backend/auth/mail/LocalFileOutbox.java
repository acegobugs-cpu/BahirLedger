package com.bahirledger.backend.auth.mail;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.NoSuchFileException;
import java.nio.file.Path;
import java.nio.file.SecureDirectoryStream;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.PosixFileAttributeView;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Set;
import java.util.UUID;

import com.bahirledger.backend.auth.ApiException;

/** Local POSIX development only. Descriptor-relative traversal and CREATE_NEW prevent token-file substitution. */
final class LocalFileOutbox {
    private final Path directory;

    LocalFileOutbox(Path home) {
        if (!home.isAbsolute()) throw new IllegalArgumentException("An absolute home directory is required.");
        directory = home.resolve(".local/share/bahirledger/mail").normalize();
    }

    void deliver(String message) {
        try (DirectoryStream<Path> root = Files.newDirectoryStream(directory.getRoot())) {
            if (!(root instanceof SecureDirectoryStream<Path> secure)) throw new IOException();
            write(secure, directory.getRoot(), 0, message);
        } catch (IOException | RuntimeException unavailable) {
            // No path, recipient or token in diagnostic exceptions.
            throw ApiException.unavailable();
        }
    }

    private void write(SecureDirectoryStream<Path> parent, Path absolute, int index, String message) throws IOException {
        if (index == directory.getNameCount()) {
            parent.getFileAttributeView(PosixFileAttributeView.class)
                    .setPermissions(PosixFilePermissions.fromString("rwx------"));
            Path name = Path.of(UUID.randomUUID() + ".eml");
            try (var file = parent.newByteChannel(name,
                    Set.of(StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE, LinkOption.NOFOLLOW_LINKS),
                    PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------")))) {
                var bytes = ByteBuffer.wrap(message.getBytes(StandardCharsets.UTF_8));
                while (bytes.hasRemaining()) file.write(bytes);
            }
            return;
        }
        Path name = directory.getName(index);
        Path next = absolute.resolve(name);
        SecureDirectoryStream<Path> child;
        try {
            child = parent.newDirectoryStream(name, LinkOption.NOFOLLOW_LINKS);
        } catch (NoSuchFileException missing) {
            try {
                Files.createDirectory(next, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")));
            } catch (FileAlreadyExistsException race) {
                // Reopen relative to the held parent descriptor; a symlink is still rejected.
            }
            child = parent.newDirectoryStream(name, LinkOption.NOFOLLOW_LINKS);
        }
        try (var opened = child) {
            write(opened, next, index + 1, message);
        }
    }
}