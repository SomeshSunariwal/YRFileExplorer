package com.somesh.yrfileexplorer.files;

import java.io.IOException;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import java.util.function.Consumer;

/** Counts real files without following links and reports throttled batch progress. */
public final class FileOperationProgress {
    private final String id;
    private final Consumer<Map<String, Object>> sink;
    private final Map<String, Long> counts = new HashMap<>();
    private long total, completed, rootCompleted, lastEmission;
    private boolean known = true;
    private String current = "";

    public FileOperationProgress(String id, List<String> paths, Consumer<Map<String, Object>> sink) throws IOException {
        this.id = id;
        this.sink = sink;
        current = paths.isEmpty() ? "" : paths.get(0);
        emit(true, true);
        for (String path : paths) {
            final long[] files = {0};
            current = path;
            Files.walkFileTree(Paths.get(path), new SimpleFileVisitor<Path>() {
                @Override public FileVisitResult visitFile(Path p, BasicFileAttributes attributes) {
                    files[0]++;
                    current = p.toString();
                    emit(true, false);
                    return FileVisitResult.CONTINUE;
                }
                @Override public FileVisitResult visitFileFailed(Path p, IOException error) {
                    known = false;
                    return FileVisitResult.CONTINUE;
                }
            });
            counts.put(path, files[0]);
            total += files[0];
        }
        emit(false, true);
    }
    public void start(Path path) {
        current = path.toString();
        rootCompleted = 0;
        emit(false, true);
    }
    public void fileDone(Path path) {
        current = path.toString();
        completed++;
        rootCompleted++;
        total = Math.max(total, completed);
        emit(false, false);
    }
    public void finish(Path path) {
        completed += Math.max(0, counts.getOrDefault(path.toString(), 0L) - rootCompleted);
        total = Math.max(total, completed);
        current = path.toString();
        emit(false, true);
    }
    private void emit(boolean counting, boolean force) {
        long now = System.nanoTime();
        if (!force && now - lastEmission < 100_000_000L) return;
        lastEmission = now;
        Map<String, Object> event = new HashMap<>();
        event.put("type", "fileOperation");
        event.put("id", id);
        event.put("current", current);
        event.put("completed", completed);
        event.put("counting", counting);
        if (!counting && known) event.put("total", total);
        sink.accept(event);
    }
}
