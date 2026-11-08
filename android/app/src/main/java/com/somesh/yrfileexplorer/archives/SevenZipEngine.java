package com.somesh.yrfileexplorer.archives;

import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry;
import org.apache.commons.compress.archivers.sevenz.SevenZFile;
import org.apache.commons.compress.archivers.sevenz.SevenZMethod;
import org.apache.commons.compress.archivers.sevenz.SevenZMethodConfiguration;
import org.apache.commons.compress.archivers.sevenz.SevenZOutputFile;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.channels.SeekableByteChannel;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Offline 7z support. Extract only into a new directory; never overwrite files.
 */
public final class SevenZipEngine {
    private SevenZipEngine() {
    }

    private static SevenZFile reader(String path, String password) throws IOException {
        return SevenZFile.builder().setFile(new File(path))
                .setPassword(password.isEmpty() ? null : password.toCharArray())
                .setMaxMemoryLimitKiB(128 * 1024).get();
    }

    private static String clean(String name) throws IOException {
        if (name == null || name.indexOf('\0') >= 0)
            throw new IOException("Invalid archive path");
        String value = name.replace('\\', '/');
        if (value.startsWith("/") || value.matches("^[a-zA-Z]:.*")
                || Arrays.asList(value.split("/")).contains(".."))
            throw new IOException("Archive contains an unsafe path");
        return value;
    }

    private static boolean encrypted(SevenZArchiveEntry entry) {
        if (entry.getContentMethods() != null)
            for (SevenZMethodConfiguration method : entry.getContentMethods())
                if (method.getMethod() == SevenZMethod.AES256SHA256)
                    return true;
        return false;
    }

    public static List<Map<String, Object>> list(String path, String prefix, String password) throws IOException {
        Map<String, Map<String, Object>> rows = new LinkedHashMap<>();
        try (SevenZFile archive = reader(path, password)) {
            int count = 0;
            for (SevenZArchiveEntry entry : archive.getEntries()) {
                if (++count > 100000)
                    throw new IOException("Archive has too many entries to display");
                String full = clean(entry.getName());
                if (!full.startsWith(prefix) || full.equals(prefix))
                    continue;
                String relative = full.substring(prefix.length());
                int slash = relative.indexOf('/');
                boolean dir = slash >= 0 || entry.isDirectory();
                String name = slash >= 0 ? relative.substring(0, slash) : relative;
                if (name.isEmpty())
                    continue;
                String key = prefix + name + (dir ? "/" : "");
                Map<String, Object> row = rows.get(key);
                if (row == null) {
                    row = new HashMap<>();
                    row.put("name", name);
                    row.put("path", key);
                    row.put("directory", dir);
                    row.put("category", dir ? "Folders" : FolderAnalyzer.category(name));
                    row.put("modified", entry.getHasLastModifiedDate() ? entry.getLastModifiedTime().toMillis() : 0L);
                    row.put("size", 0L);
                    row.put("encrypted", false);
                    rows.put(key, row);
                }
                row.put("size", ((Number) row.get("size")).longValue() + Math.max(0, entry.getSize()));
                row.put("encrypted", Boolean.TRUE.equals(row.get("encrypted")) || encrypted(entry));
            }
        }
        return new ArrayList<>(rows.values());
    }

    public static void extract(String path, String destination, List<String> entries, String password)
            throws Exception {
        Path root = Paths.get(destination).toAbsolutePath().normalize();
        Files.createDirectory(root);
        try (SevenZFile archive = reader(path, password)) {
            long remaining = root.toFile().getUsableSpace();
            byte[] buffer = new byte[65536];
            SevenZArchiveEntry entry;
            while ((entry = archive.getNextEntry()) != null) {
                String name = clean(entry.getName());
                if (!entries.isEmpty() && entries.stream().noneMatch(e -> name.equals(e)
                        || (e.endsWith("/") && name.startsWith(e))))
                    continue;
                Path output = root.resolve(name).normalize();
                if (!output.startsWith(root))
                    throw new IOException("Unsafe archive path");
                if (entry.isDirectory()) {
                    Files.createDirectories(output);
                    continue;
                }
                if (entry.getSize() > remaining)
                    throw new IOException("Not enough storage to extract archive");
                Files.createDirectories(output.getParent());
                try (OutputStream out = Files.newOutputStream(output, StandardOpenOption.CREATE_NEW)) {
                    int n;
                    while ((n = archive.read(buffer)) != -1) {
                        remaining -= n;
                        if (remaining < 0)
                            throw new IOException("Not enough storage to extract archive");
                        out.write(buffer, 0, n);
                    }
                }
                if (entry.getHasLastModifiedDate())
                    Files.setLastModifiedTime(output, entry.getLastModifiedTime());
            }
        } catch (Exception error) {
            try {
                FileEngine.delete(root);
            } catch (Exception cleanup) {
                error.addSuppressed(cleanup);
            }
            throw error;
        }
    }

    public static void create(List<String> sources, String destination, String password) throws Exception {
        if (sources == null || sources.isEmpty())
            throw new IOException("Select files to compress");
        Path target = Paths.get(destination).toAbsolutePath().normalize();
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS))
            throw new IOException("Destination already exists");
        Path parent = target.getParent().toRealPath();
        target = parent.resolve(target.getFileName());
        List<Path> roots = new ArrayList<>();
        Set<String> names = new HashSet<>();
        for (String source : sources) {
            Path input = Paths.get(source);
            if (Files.isSymbolicLink(input))
                throw new IOException("Symbolic links cannot be compressed");
            Path root = input.toRealPath();
            if (root.getFileName() == null || !Files.isReadable(root))
                throw new IOException("Cannot read source");
            if (target.startsWith(root))
                throw new IOException("Save the archive outside the selected folder");
            if (!names.add(root.getFileName().toString()))
                throw new IOException("Selected items have duplicate names");
            roots.add(root);
        }
        Path staging = parent.resolve(".yr-archive-" + UUID.randomUUID() + ".7z");
        boolean owned = false;
        try {
            SeekableByteChannel channel = Files.newByteChannel(staging, StandardOpenOption.CREATE_NEW,
                    StandardOpenOption.READ, StandardOpenOption.WRITE);
            owned = true;
            try (SeekableByteChannel outputChannel = channel;
                    SevenZOutputFile archive = new SevenZOutputFile(outputChannel,
                            password.isEmpty() ? null : password.toCharArray())) {
                for (Path root : roots)
                    Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
                        private void add(Path file, boolean directory) throws IOException {
                            if (Files.isSymbolicLink(file) || (!directory && !Files.isRegularFile(file)))
                                throw new IOException("Symbolic links and special files cannot be compressed");
                            String name = root.getFileName() + (file.equals(root) ? "" : "/" + root.relativize(file));
                            name = clean(name) + (directory ? "/" : "");
                            archive.putArchiveEntry(archive.createArchiveEntry(file, name, LinkOption.NOFOLLOW_LINKS));
                            if (!directory)
                                try (InputStream in = Files.newInputStream(file)) {
                                    byte[] buffer = new byte[65536];
                                    int n;
                                    while ((n = in.read(buffer)) != -1)
                                        archive.write(buffer, 0, n);
                                }
                            archive.closeArchiveEntry();
                        }

                        @Override
                        public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs)
                                throws IOException {
                            add(dir, true);
                            return FileVisitResult.CONTINUE;
                        }

                        @Override
                        public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                            add(file, false);
                            return FileVisitResult.CONTINUE;
                        }
                    });
            }
            Files.move(staging, target);
        } finally {
            if (owned)
                Files.deleteIfExists(staging);
        }
    }
}
