package com.somesh.yrfileexplorer.storage;

import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/**
 * Read and analyze user-granted Storage Access Framework trees, including cloud
 * providers.
 */
public final class DocumentEngine {
    private final Context context;

    public DocumentEngine(Context context) {
        this.context = context;
    }

    private String id(Uri uri) {
        return DocumentsContract.isDocumentUri(context, uri) ? DocumentsContract.getDocumentId(uri)
                : DocumentsContract.getTreeDocumentId(uri);
    }

    public List<Map<String, Object>> list(String path, boolean hidden) throws IOException {
        Uri tree = Uri.parse(path);
        Uri children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id(tree));
        List<Map<String, Object>> rows = new ArrayList<>();
        try (Cursor c = context.getContentResolver().query(children,
                new String[] { DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                        DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE,
                        DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_LAST_MODIFIED },
                null, null, null)) {
            if (c == null)
                throw new IOException("Document provider returned no listing");
            while (c.moveToNext()) {
                String name = c.getString(1);
                if (!hidden && name.startsWith("."))
                    continue;
                rows.add(new LinkedHashMap<>(Map.of("name", name, "path",
                        DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0)).toString(), "directory",
                        DocumentsContract.Document.MIME_TYPE_DIR.equals(c.getString(2)), "size",
                        c.isNull(3) ? 0L : c.getLong(3), "modified", c.isNull(4) ? 0L : c.getLong(4), "category",
                        FolderAnalyzer.category(name), "unknownSize", c.isNull(3))));
            }
        } catch (SecurityException e) {
            throw new IOException("Folder access was revoked. Connect this folder again.", e);
        }
        return rows;
    }

    private record Visit(Map<String, Object> entry, Map<String, Object> owner) {
    }

    public Map<String, Object> analyze(String path, AtomicBoolean cancel, Consumer<Map<String, Object>> progress)
            throws Exception {
        List<Map<String, Object>> children = list(path, true), files = new ArrayList<>(), empty = new ArrayList<>();
        Map<String, long[]> categories = new LinkedHashMap<>();
        for (String name : List.of("Images", "Music", "Videos", "Documents", "Apps", "Archives", "Other"))
            categories.put(name, new long[2]);
        Deque<Visit> stack = new ArrayDeque<>();
        for (var child : children) {
            child.put("files", 0L);
            child.put("folders", 0L);
            child.put("skipped", 0L);
            if (Boolean.TRUE.equals(child.get("directory")))
                child.put("size", 0L);
            stack.add(new Visit(new LinkedHashMap<>(child), child));
        }
        Set<String> seen = new HashSet<>();
        long bytes = 0, fileCount = 0, folderCount = 0, skipped = 0, updated = 0, unknown = 0;
        while (!stack.isEmpty()) {
            if (cancel.get())
                throw new InterruptedIOException("Analysis cancelled");
            Visit visit = stack.removeLast();
            var entry = visit.entry();
            var owner = visit.owner();
            String uri = entry.get("path").toString();
            if (!seen.add(uri)) {
                skipped++;
                continue;
            }
            if (Boolean.TRUE.equals(entry.get("directory"))) {
                folderCount++;
                if (!uri.equals(owner.get("path")))
                    owner.put("folders", (long) owner.get("folders") + 1);
                try {
                    var nested = list(uri, true);
                    if (nested.isEmpty() && empty.size() < 1000)
                        empty.add(entry);
                    for (var e : nested)
                        stack.add(new Visit(e, owner));
                } catch (Exception e) {
                    skipped++;
                    owner.put("skipped", (long) owner.get("skipped") + 1);
                }
            } else {
                fileCount++;
                long size = ((Number) entry.get("size")).longValue();
                bytes += size;
                if (Boolean.TRUE.equals(entry.get("unknownSize")))
                    unknown++;
                owner.put("files", (long) owner.get("files") + 1);
                if (!uri.equals(owner.get("path")))
                    owner.put("size", (long) owner.get("size") + size);
                long[] cat = categories.get(entry.get("category"));
                cat[0] += size;
                cat[1]++;
                files.add(entry);
                if (files.size() > 200) {
                    files.sort(Comparator.comparingLong((Map<String, Object> m) -> ((Number) m.get("size")).longValue())
                            .reversed());
                    files.subList(100, files.size()).clear();
                }
            }
            if (progress != null && System.currentTimeMillis() - updated > 150) {
                updated = System.currentTimeMillis();
                progress.accept(new LinkedHashMap<>(Map.of("bytes", bytes, "files", fileCount, "folders", folderCount,
                        "skipped", skipped, "current", entry.get("name"))));
            }
        }
        files.sort(
                Comparator.comparingLong((Map<String, Object> m) -> ((Number) m.get("size")).longValue()).reversed());
        if (files.size() > 100)
            files.subList(100, files.size()).clear();
        children.sort(
                Comparator.comparingLong((Map<String, Object> m) -> ((Number) m.get("size")).longValue()).reversed());
        List<Map<String, Object>> cats = new ArrayList<>();
        for (var e : categories.entrySet())
            cats.add(Map.of("name", e.getKey(), "size", e.getValue()[0], "files", e.getValue()[1]));
        Map<String, Object> result = new LinkedHashMap<>();
        result.putAll(Map.of("path", path, "bytes", bytes, "files", fileCount, "folders", folderCount, "skipped",
                skipped, "children", children, "categories", cats, "largest", files, "empty", empty));
        result.put("recent", List.of());
        result.put("duplicates", List.of());
        result.put("duplicatesScanned", false);
        result.put("unknownSizes", unknown);
        result.put("provider", true);
        return result;
    }
}
