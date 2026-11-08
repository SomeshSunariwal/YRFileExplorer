package com.somesh.yrfileexplorer.network;

import android.app.Activity;
import android.app.DownloadManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.webkit.URLUtil;
import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;
import org.json.JSONObject;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Tracks only downloads explicitly started by this application. */
public final class DownloadTasks {
    private DownloadTasks() {
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences("yr_downloads", Context.MODE_PRIVATE);
    }

    private static Set<String> ids(Context context) {
        return new HashSet<>(preferences(context).getStringSet("ids", Collections.emptySet()));
    }

    private static String value(Map<String, Object> args, String name) {
        return Objects.toString(args.get(name), "").trim();
    }

    public static synchronized long enqueue(Context context, Map<String, Object> args) throws Exception {
        String address = value(args, "url");
        Uri url = Uri.parse(address);
        if (!Set.of("http", "https").contains(Objects.toString(url.getScheme(), "")) || url.getHost() == null
                || url.getUserInfo() != null)
            throw new IOException("Enter a valid HTTP or HTTPS URL without embedded credentials");
        String name = value(args, "name");
        if (name.isEmpty())
            name = URLUtil.guessFileName(address, null, null);
        Path folder = Paths.get(value(args, "path"));
        if (!folder.isAbsolute())
            throw new IOException("Choose an absolute destination folder");
        Files.createDirectories(folder);
        Path destination = FileEngine.named(folder, name);
        if (Files.exists(destination))
            throw new IOException("A file with that name already exists. Choose another name.");
        DownloadManager.Request request = new DownloadManager.Request(url)
                .setTitle(name).setDestinationUri(Uri.fromFile(destination.toFile()))
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
        long id = context.getSystemService(DownloadManager.class).enqueue(request);
        Set<String> ids = ids(context);
        ids.add(Long.toString(id));
        preferences(context).edit().putStringSet("ids", ids)
                .putString("job." + id,
                        new JSONObject(Map.of("url", address, "name", name, "path", folder.toString())).toString())
                .apply();
        return id;
    }

    public static synchronized List<Map<String, Object>> list(Context context) {
        Set<String> ids = ids(context);
        List<Map<String, Object>> jobs = new ArrayList<>();
        if (ids.isEmpty())
            return jobs;
        long[] values = ids.stream().mapToLong(Long::parseLong).toArray();
        DownloadManager manager = context.getSystemService(DownloadManager.class);
        try (Cursor cursor = manager.query(new DownloadManager.Query().setFilterById(values))) {
            if (cursor == null)
                return jobs;
            while (cursor.moveToNext()) {
                long id = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID));
                int status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
                Map<String, Object> job = new HashMap<>();
                job.put("id", id);
                job.put("status", switch (status) {
                    case DownloadManager.STATUS_PENDING -> "Waiting";
                    case DownloadManager.STATUS_RUNNING -> "Downloading";
                    case DownloadManager.STATUS_PAUSED -> "Waiting for network";
                    case DownloadManager.STATUS_SUCCESSFUL -> "Completed";
                    default -> "Failed";
                });
                job.put("name", Objects.toString(
                        cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)), "Download"));
                job.put("url", Objects
                        .toString(cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_URI)), ""));
                job.put("bytes",
                        cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)));
                job.put("total", cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)));
                job.put("reason", cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)));
                jobs.add(job);
            }
        }
        jobs.sort((a, b) -> Long.compare(((Number) b.get("id")).longValue(), ((Number) a.get("id")).longValue()));
        return jobs;
    }

    private static void owned(Context context, long id) throws IOException {
        if (!ids(context).contains(Long.toString(id)))
            throw new IOException("Download is not in this application's history");
    }

    public static synchronized void cancel(Context context, long id) throws IOException {
        owned(context, id);
        boolean active = list(context).stream().anyMatch(job -> ((Number) job.get("id")).longValue() == id &&
                !Set.of("Completed", "Failed").contains(job.get("status")));
        if (!active)
            throw new IOException("Only an active download can be cancelled");
        context.getSystemService(DownloadManager.class).remove(id);
        forget(context, id);
    }

    public static synchronized void forget(Context context, long id) throws IOException {
        owned(context, id);
        Set<String> ids = ids(context);
        ids.remove(Long.toString(id));
        preferences(context).edit().putStringSet("ids", ids).remove("job." + id).apply();
    }

    public static synchronized long retry(Context context, long id) throws Exception {
        owned(context, id);
        if (list(context).stream()
                .noneMatch(job -> ((Number) job.get("id")).longValue() == id && job.get("status").equals("Failed")))
            throw new IOException("Only failed downloads can be retried");
        JSONObject original = new JSONObject(preferences(context).getString("job." + id, "{}"));
        Map<String, Object> args = new HashMap<>();
        for (String name : List.of("url", "name", "path"))
            args.put(name, original.getString(name));
        context.getSystemService(DownloadManager.class).remove(id);
        forget(context, id);
        return enqueue(context, args);
    }

    public static void open(Activity activity, long id) throws IOException {
        owned(activity, id);
        DownloadManager manager = activity.getSystemService(DownloadManager.class);
        Uri uri = manager.getUriForDownloadedFile(id);
        if (uri == null)
            throw new IOException("Download is not complete or no longer exists");
        String type = manager.getMimeTypeForDownloadedFile(id);
        activity.startActivity(Intent.createChooser(
                new Intent(Intent.ACTION_VIEW).setDataAndType(uri, type == null ? "application/octet-stream" : type)
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                "Open downloaded file"));
    }

    public static Map<String, Object> completedMedia(Context context, long id) throws Exception {
        owned(context, id);
        DownloadManager manager = context.getSystemService(DownloadManager.class);
        if (manager.getUriForDownloadedFile(id) == null)
            throw new IOException("Download is not complete or no longer exists");
        JSONObject job = new JSONObject(preferences(context).getString("job." + id, "{}"));
        if (!job.has("path") || !job.has("name"))
            return null;
        Path path = FileEngine.named(Paths.get(job.getString("path")), job.getString("name"));
        if (!Files.isRegularFile(path) || !Files.isReadable(path))
            return null;
        String name = path.getFileName().toString();
        String category = FolderAnalyzer.category(name);
        if (!Set.of("Images", "Music", "Videos").contains(category)
                && !name.toLowerCase(java.util.Locale.ROOT).endsWith(".pdf"))
            return null;
        return Map.of("path", path.toString(), "name", name, "category", category, "directory", false);
    }
}
