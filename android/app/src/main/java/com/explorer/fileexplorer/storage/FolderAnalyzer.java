package com.explorer.fileexplorer.storage;

import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/** Android-independent, streaming, no symlink following. All counts are recursive. */
public final class FolderAnalyzer {
    private final AtomicBoolean cancelled;
    private final Consumer<Map<String, Object>> progress;
    private long bytes, files, folders, skipped, lastUpdate;
    private final Map<String, long[]> categories = new LinkedHashMap<>();
    private final List<Map<String, Object>> children = new ArrayList<>();
    private final PriorityQueue<Map<String, Object>> largest = new PriorityQueue<>(Comparator.comparingLong(m -> (long)m.get("size")));
    private final PriorityQueue<Map<String, Object>> newest = new PriorityQueue<>(Comparator.comparingLong(m -> (long)m.get("modified")));
    private final Map<Long, List<Path>> sizes = new HashMap<>();
    private final List<Map<String, Object>> emptyFolders = new ArrayList<>();

    public FolderAnalyzer(AtomicBoolean cancelled, Consumer<Map<String, Object>> progress) {
        this.cancelled = cancelled;
        this.progress = progress;
        for (String c : List.of("Images", "Music", "Videos", "Documents", "Apps", "Archives", "Other")) categories.put(c, new long[2]);
    }
    public static Map<String, Object> entry(Path p, BasicFileAttributes a) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("name", p.getFileName() == null ? p.toString() : p.getFileName().toString());
        m.put("path", p.toString()); m.put("directory", a.isDirectory());
        m.put("size", a.isDirectory() ? 0L : a.size()); m.put("modified", a.lastModifiedTime().toMillis());
        m.put("category", category(p.toString()));
        return m;
    }
    public static String category(String name) {
        String ext = name.toLowerCase(Locale.ROOT).replaceAll("^.*\\.", "");
        if (Set.of("jpg","jpeg","png","webp","gif","bmp","heic","avif","svg","raw").contains(ext)) return "Images";
        if (Set.of("mp3","aac","flac","wav","ogg","m4a","opus").contains(ext)) return "Music";
        if (Set.of("mp4","mkv","avi","mov","webm","3gp","m4v","mpeg").contains(ext)) return "Videos";
        if (Set.of("txt","md","pdf","doc","docx","xls","xlsx","csv","ppt","pptx","json","xml","html","epub","log","dart","java").contains(ext)) return "Documents";
        if (Set.of("apk","apks","xapk","aab").contains(ext)) return "Apps";
        if (Set.of("zip","rar","7z","tar","gz","bz2","xz").contains(ext)) return "Archives";
        return "Other";
    }
    private void check() throws InterruptedIOException {
        if (cancelled.get() || Thread.currentThread().isInterrupted()) throw new InterruptedIOException("Analysis cancelled");
    }
    private void publish(Path p) {
        long now = System.currentTimeMillis();
        if (progress != null && now - lastUpdate > 150) {
            lastUpdate = now;
            progress.accept(new LinkedHashMap<>(Map.of("bytes", bytes, "files", files, "folders", folders, "skipped", skipped, "current", p.toString())));
        }
    }
    public Map<String, Object> analyze(Path root, boolean duplicates) throws IOException {
        if (!Files.isDirectory(root, LinkOption.NOFOLLOW_LINKS)) throw new IOException("Select an accessible folder");
        BasicFileAttributes rootAttr = Files.readAttributes(root, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        // One walk per immediate child keeps memory proportional to immediate children, not the full tree.
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(root)) {
            for (Path child : stream) {
                check();
                BasicFileAttributes attr;
                try { attr = Files.readAttributes(child, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS); }
                catch (IOException | SecurityException ex) { skipped++; continue; }
                if (attr.isSymbolicLink()) { skipped++; continue; }
                Map<String, Object> row = entry(child, attr);
                long beforeBytes = bytes, beforeFiles = files, beforeFolders = folders, beforeSkipped = skipped;
                Files.walkFileTree(child, new SimpleFileVisitor<Path>() {
                    @Override public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes a) throws IOException {
                        check(); folders++; publish(dir); return FileVisitResult.CONTINUE;
                    }
                    @Override public FileVisitResult visitFile(Path p, BasicFileAttributes a) throws IOException {
                        check();
                        if (!a.isRegularFile()) { skipped++; return FileVisitResult.CONTINUE; }
                        files++; bytes += a.size();
                        long[] cat = categories.get(category(p.toString())); cat[0] += a.size(); cat[1]++;
                        Map<String, Object> item = entry(p, a);
                        largest.add(item); if (largest.size() > 100) largest.poll();
                        newest.add(item); if (newest.size() > 100) newest.poll();
                        if (duplicates && a.size() > 0) sizes.computeIfAbsent(a.size(), k -> new ArrayList<>()).add(p);
                        publish(p); return FileVisitResult.CONTINUE;
                    }
                    @Override public FileVisitResult visitFileFailed(Path p, IOException e) { skipped++; publish(p); return FileVisitResult.CONTINUE; }
                    @Override public FileVisitResult postVisitDirectory(Path dir, IOException e) throws IOException {
                        check();
                        if (e != null) skipped++;
                        else if (emptyFolders.size() < 1000) {
                            try (DirectoryStream<Path> d = Files.newDirectoryStream(dir)) {
                                if (!d.iterator().hasNext()) emptyFolders.add(entry(dir, Files.readAttributes(dir, BasicFileAttributes.class)));
                            } catch (IOException | SecurityException ex) { skipped++; }
                        }
                        return FileVisitResult.CONTINUE;
                    }
                });
                row.put("size", bytes - beforeBytes);
                row.put("files", files - beforeFiles);
                row.put("folders", attr.isDirectory() ? Math.max(0, folders - beforeFolders - 1) : 0L);
                row.put("skipped", skipped - beforeSkipped);
                children.add(row);
            }
        }
        children.sort(Comparator.comparingLong((Map<String, Object> m) -> (long)m.get("size")).reversed());
        List<Map<String, Object>> cats = new ArrayList<>();
        for (var e : categories.entrySet()) cats.add(Map.of("name", e.getKey(), "size", e.getValue()[0], "files", e.getValue()[1]));
        List<Map<String, Object>> large = new ArrayList<>(largest), recent = new ArrayList<>(newest);
        large.sort(Comparator.comparingLong((Map<String, Object> m) -> (long)m.get("size")).reversed());
        recent.sort(Comparator.comparingLong((Map<String, Object> m) -> (long)m.get("modified")).reversed());
        Map<String, Object> result = entry(root, rootAttr);
        result.putAll(Map.of("bytes", bytes, "files", files, "folders", folders, "skipped", skipped,
            "children", children, "categories", cats, "largest", large, "recent", recent, "empty", emptyFolders));
        result.put("duplicates", duplicates ? duplicates() : List.of());
        result.put("skipped", skipped);
        result.put("duplicatesScanned", duplicates);
        return result;
    }
    private List<Map<String, Object>> duplicates() throws IOException {
        List<Map<String, Object>> groups = new ArrayList<>();
        byte[] buffer = new byte[128 * 1024];
        for (var bucket : sizes.entrySet()) {
            if (bucket.getValue().size() < 2) continue;
            Map<String, List<String>> hashes = new LinkedHashMap<>();
            for (Path p : bucket.getValue()) {
                check(); publish(p);
                try {
                    MessageDigest md = MessageDigest.getInstance("SHA-256");
                    try (InputStream in = Files.newInputStream(p)) {
                        int n; while ((n = in.read(buffer)) != -1) { check(); md.update(buffer, 0, n); }
                    }
                    StringBuilder hash = new StringBuilder();
                    for (byte b : md.digest()) hash.append(String.format("%02x", b));
                    hashes.computeIfAbsent(hash.toString(), k -> new ArrayList<>()).add(p.toString());
                } catch (InterruptedIOException ex) { throw ex; }
                catch (Exception ex) { skipped++; }
            }
            for (var e : hashes.entrySet()) if (e.getValue().size() > 1) groups.add(Map.of("hash", e.getKey(), "size", bucket.getKey(), "paths", e.getValue(), "wasted", bucket.getKey() * (e.getValue().size() - 1)));
        }
        groups.sort(Comparator.comparingLong((Map<String, Object> m) -> (long)m.get("wasted")).reversed());
        return groups;
    }
}
