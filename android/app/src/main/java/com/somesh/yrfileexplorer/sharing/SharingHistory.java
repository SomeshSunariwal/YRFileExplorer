package com.somesh.yrfileexplorer.sharing;

import android.content.Context;
import android.os.SystemClock;
import android.util.AtomicFile;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/** Bounded on-device transfer log; never contains pairing codes or session keys. */
final class SharingHistory {
    private static final int MAX_ENTRIES = 500;
    private static final int MAX_BYTES = 2_000_000;
    private static final Set<String> ACTIVE = Set.of("Queued", "Sending", "Verifying", "Receiving");
    private static final AtomicLong REVISIONS = new AtomicLong();

    record OutgoingFile(File file, String name, String id, long size) {
        OutgoingFile(File file, String name) {
            this(file, name, UUID.randomUUID().toString(), file.length());
        }
    }

    private final LinkedHashMap<String, Map<String, Object>> rows = new LinkedHashMap<>();
    private final AtomicFile file;
    private long revision = REVISIONS.incrementAndGet();
    private long lastWrite = -1000;

    SharingHistory(Context context) {
        file = new AtomicFile(new File(context.getFilesDir(), "sharing-history.json"));
        try (InputStream in = file.openRead()) {
            ByteArrayOutputStream data = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = in.read(buffer)) != -1) {
                if (data.size() + count > MAX_BYTES) return;
                data.write(buffer, 0, count);
            }
            JSONArray saved = new JSONArray(data.toString(StandardCharsets.UTF_8.name()));
            for (int i = 0; i < saved.length() && i < MAX_ENTRIES; i++) {
                JSONObject entry = saved.getJSONObject(i);
                Map<String, Object> row = new HashMap<>();
                Iterator<String> keys = entry.keys();
                while (keys.hasNext()) {
                    String key = keys.next();
                    row.put(key, entry.get(key));
                }
                if (isActive(row)) row.put("status", "Interrupted");
                rows.put(entry.getString("id"), row);
            }
        } catch (IOException | JSONException ignored) { /* History may be absent or unreadable. */ }
    }

    synchronized void enqueue(List<OutgoingFile> files, String peer) {
        for (OutgoingFile file : files) {
            putSent(file, peer, 0, "Queued");
        }
        commit(true);
    }

    synchronized void updateSent(OutgoingFile file, String peer, long bytes, String status) {
        putSent(file, peer, bytes, status);
        commit(!"Sending".equals(status));
    }

    synchronized void failPending(List<OutgoingFile> files) {
        boolean modified = false;
        for (OutgoingFile file : files) {
            Map<String, Object> row = rows.get(file.id());
            if (row != null && isActive(row)) {
                row.put("status", "Failed");
                modified = true;
            }
        }
        if (modified) commit(true);
    }

    synchronized void updateReceived(String id, String name, String peer, long bytes,
                                     long size, String status, String path) {
        put(id, name, peer, "Received", bytes, size, status, path);
        commit(!"Receiving".equals(status));
    }

    synchronized Map<String, Object> since(long knownRevision) {
        if (knownRevision == revision) return null;
        List<Map<String, Object>> result = new ArrayList<>(rows.size());
        for (Map<String, Object> row : rows.values()) {
            result.add(new HashMap<>(row));
        }
        Collections.reverse(result);
        return Map.of("revision", revision, "rows", result);
    }

    synchronized void clear() {
        if (rows.values().removeIf(row -> !isActive(row))) commit(true);
    }

    private static boolean isActive(Map<String, Object> row) {
        return row.get("status") instanceof String status && ACTIVE.contains(status);
    }

    private void putSent(OutgoingFile file, String peer, long bytes, String status) {
        put(file.id(), file.name(), peer, "Sent", bytes, file.size(), status, file.file().getPath());
    }

    private void put(String id, String name, String peer, String direction, long bytes,
                     long size, String status, String path) {
        Map<String, Object> row = rows.computeIfAbsent(id, key -> {
            Map<String, Object> entry = new HashMap<>();
            entry.put("id", key);
            entry.put("time", System.currentTimeMillis());
            return entry;
        });
        row.put("name", name);
        row.put("peer", peer);
        row.put("direction", direction);
        row.put("bytes", bytes);
        row.put("size", size);
        row.put("status", status);
        if (path != null) row.put("path", path);
        if (rows.size() > MAX_ENTRIES) rows.remove(rows.keySet().iterator().next());
    }

    private void commit(boolean persistNow) {
        revision = REVISIONS.incrementAndGet();
        if (persistNow || SystemClock.elapsedRealtime() - lastWrite >= 1000) save();
    }

    private void save() {
        FileOutputStream out = null;
        try {
            out = file.startWrite();
            out.write(new JSONArray(rows.values()).toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(out);
            lastWrite = SystemClock.elapsedRealtime();
        } catch (Exception e) {
            if (out != null) file.failWrite(out);
        }
    }
}
