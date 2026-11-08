package com.somesh.yrfileexplorer.apps;

import android.content.Context;

import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;

import android.graphics.Canvas;

import android.graphics.drawable.Drawable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

public final class AppCatalog {

    private final Context context;

    private final PackageManager packages;

    public AppCatalog(Context context) {
        this.context = context;
        packages = context.getPackageManager();
    }

    private Map<String, Object> entry(PackageInfo info, String source, boolean backup) throws IOException {

        ApplicationInfo app = info.applicationInfo;

        if (backup) {
            app.sourceDir = source;
            app.publicSourceDir = source;
        }

        Map<String, Object> row = new HashMap<>();

        row.put("name", app.loadLabel(packages).toString());
        row.put("package", info.packageName);

        row.put("path", source);
        row.put("version", info.versionName == null ? "" : info.versionName);

        long size = new File(source).length();

        if (!backup && app.splitSourceDirs != null)
            for (String split : app.splitSourceDirs)
                size += new File(split).length();

        row.put("size", size);
        row.put("split", app.splitSourceDirs != null);

        row.put("system", (app.flags & ApplicationInfo.FLAG_SYSTEM) != 0);

        row.put("external", (app.flags & ApplicationInfo.FLAG_EXTERNAL_STORAGE) != 0);

        row.put("installed", info.firstInstallTime);
        row.put("backup", backup);

        try {

            File folder = new File(context.getCacheDir(), "app-icons");
            folder.mkdirs();

            String id = backup ? Integer.toHexString(source.hashCode()) + "-" + new File(source).lastModified()
                    : info.packageName + "-" + info.lastUpdateTime;

            File icon = new File(folder, id + "-192.png");

            if (!icon.isFile()) {

                Drawable drawable = app.loadIcon(packages);
                Bitmap bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888);

                drawable.setBounds(0, 0, 192, 192);
                drawable.draw(new Canvas(bitmap));

                try (OutputStream out = new FileOutputStream(icon)) {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out);
                } finally {
                    bitmap.recycle();
                }

            }

            row.put("icon", icon.getAbsolutePath());

        } catch (Exception ignored) {
            /* UI uses an Android icon if package resources disappeared. */ }

        return row;

    }

    public List<Map<String, Object>> installed(boolean includeSystem) throws Exception {

        List<Map<String, Object>> result = new ArrayList<>();

        for (PackageInfo info : packages.getInstalledPackages(0)) {

            if (info.applicationInfo == null
                    || (!includeSystem && (info.applicationInfo.flags & ApplicationInfo.FLAG_SYSTEM) != 0))
                continue;

            try {
                result.add(entry(info, info.applicationInfo.sourceDir, false));
            } catch (IOException ignored) {
            }

        }

        result.sort(Comparator.comparing(r -> r.get("name").toString().toLowerCase(Locale.ROOT)));
        return result;

    }

    public List<Map<String, Object>> archives(String root) throws Exception {

        List<Map<String, Object>> result = new ArrayList<>();
        Path start = Paths.get(root);

        if (!Files.exists(start))
            return result;

        Files.walkFileTree(start, new SimpleFileVisitor<Path>() {

            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {

                if (attrs.isRegularFile() && file.toString().toLowerCase(Locale.ROOT).endsWith(".apk")) {

                    PackageInfo info = packages.getPackageArchiveInfo(file.toString(), 0);

                    if (info != null && info.applicationInfo != null)
                        result.add(entry(info, file.toString(), true));

                }

                return result.size() >= 5000 ? FileVisitResult.TERMINATE : FileVisitResult.CONTINUE;

            }

            @Override
            public FileVisitResult visitFileFailed(Path file, IOException error) {
                return FileVisitResult.CONTINUE;
            }

        });
        return result;

    }

    /** Extracts package artwork on the platform worker, never the UI thread. */
    public String archiveIcon(String source) {
        File file = new File(source);
        if (!file.isFile() || !source.toLowerCase(Locale.ROOT).endsWith(".apk"))
            return null;
        try {
            PackageInfo info = packages.getPackageArchiveInfo(source, 0);
            if (info == null || info.applicationInfo == null)
                return null;
            return (String) entry(info, source, true).get("icon");
        } catch (Exception ignored) {
            return null;
        }
    }

    public List<String> export(String name) throws Exception {

        ApplicationInfo app = packages.getApplicationInfo(name, 0);

        Path folder = new File(context.getFilesDir(), "exports/" + UUID.randomUUID()).toPath();
        Files.createDirectories(folder);

        List<String> sources = new ArrayList<>();
        sources.add(app.sourceDir);
        if (app.splitSourceDirs != null)
            sources.addAll(Arrays.asList(app.splitSourceDirs));

        List<String> result = new ArrayList<>();

        for (String source : sources) {
            Path target = folder.resolve(new File(source).getName());
            Files.copy(Paths.get(source), target);
            result.add(target.toString());
        }

        return result;

    }

}
