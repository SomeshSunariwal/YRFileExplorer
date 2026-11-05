package com.somesh.yrfileexplorer.security;

import android.app.Activity;
import android.app.Application;
import android.app.KeyguardManager;
import android.hardware.biometrics.BiometricManager;
import android.hardware.biometrics.BiometricPrompt;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.AtomicFile;
import android.view.WindowManager;
import com.google.crypto.tink.BinaryKeysetReader;
import com.google.crypto.tink.BinaryKeysetWriter;
import com.google.crypto.tink.CleartextKeysetHandle;
import com.google.crypto.tink.KeysetHandle;
import com.google.crypto.tink.StreamingAead;
import com.google.crypto.tink.streamingaead.StreamingAeadConfig;
import com.google.crypto.tink.streamingaead.StreamingAeadKeyTemplates;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.Executors;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Encrypted local vault. No filenames, paths or keysets are stored in plaintext. */
public final class PrivateSpace {
    private static final String ALIAS = "yr.private-space.wrap.v1";
    private static final byte[] KEY_AAD = "yr-private-keyset-v1".getBytes(StandardCharsets.UTF_8);
    private static PrivateSpace instance;
    private final Application app;
    private final File base, objects, previews;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final java.util.concurrent.ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile boolean unlocked, authenticating;
    private StreamingAead streaming;
    private JSONArray entries;
    private CancellationSignal prompt;
    private int started;
    private Runnable onLocked;
    private final Set<Activity> privateViewers = new HashSet<>();
    private boolean privateMedia;
    public void setOnLocked(Runnable callback) { onLocked = callback; }
    public void markPrivateMedia() { privateMedia = true; }

    public static synchronized PrivateSpace get(Activity activity) {
        if (instance == null) instance = new PrivateSpace(activity.getApplication());
        return instance;
    }
    private PrivateSpace(Application application) {
        app = application;
        base = new File(app.getNoBackupFilesDir(), "private-space-v1");
        objects = new File(base, "objects");
        previews = new File(app.getCacheDir(), "private-space-previews");
        app.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            public void onActivityStarted(Activity a) { started++; }
            public void onActivityStopped(Activity a) {
                started = Math.max(0, started - 1);
                main.postDelayed(() -> { if (started == 0 && !authenticating) lock(); }, 200);
            }
            public void onActivityCreated(Activity a, Bundle b) {
                // Native viewers must never expose a private preview in screenshots/recents.
                if (a.getIntent().getBooleanExtra("privateSpace", false)) {
                    privateViewers.add(a);
                    a.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
                }
            }
            public void onActivityDestroyed(Activity a) { privateViewers.remove(a); }
            public void onActivityResumed(Activity a) {}
            public void onActivityPaused(Activity a) {}
            public void onActivitySaveInstanceState(Activity a, Bundle b) {}
        });
        worker.execute(() -> eraseTree(previews.toPath()));
    }
    public boolean isUnlocked() { return unlocked; }
    public void shield(Activity activity, boolean enabled) {
        if (enabled) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        else activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
    }
    public void lock() {
        boolean wasUnlocked = unlocked;
        unlocked = false;
        if (wasUnlocked) main.post(() -> {
            if (privateMedia) app.stopService(new android.content.Intent(app, com.somesh.yrfileexplorer.media.AudioPlaybackService.class));
            privateMedia = false;
            for (Activity viewer : new ArrayList<>(privateViewers)) viewer.finish();
            if (onLocked != null) onLocked.run();
        });
        worker.execute(() -> { streaming = null; entries = null; eraseTree(previews.toPath()); });
    }
    private void requireUnlocked() throws IOException {
        if (!unlocked || streaming == null) throw new IOException("Private Space is locked. Unlock it to continue.");
    }
    public void unlock(Activity activity, MethodChannel.Result result) throws Exception {
        if (authenticating) throw new IOException("An unlock prompt is already open.");
        if (!activity.getSystemService(KeyguardManager.class).isDeviceSecure()) {
            throw new IOException("Set a screen-lock PIN, pattern or password in Android Settings first.");
        }
        authenticating = true;
        prompt = new CancellationSignal();
        new BiometricPrompt.Builder(activity)
            .setTitle("Unlock Private Space")
            .setSubtitle("Use your fingerprint or device screen lock")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG |
                BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            .build().authenticate(prompt, activity.getMainExecutor(), new BiometricPrompt.AuthenticationCallback() {
                @Override public void onAuthenticationError(int code, CharSequence message) {
                    authenticating = false;
                    result.error("PRIVATE_AUTH", message.toString(), null);
                }
                @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult authentication) {
                    worker.execute(() -> {
                        try {
                            loadKeys();
                            main.post(() -> { authenticating = false; shield(activity, true); result.success(true); });
                        } catch (Exception error) {
                            unlocked = false; streaming = null; entries = null;
                            main.post(() -> { authenticating = false; result.error("PRIVATE_KEY", "Cannot unlock Private Space. " + error.getMessage(), null); });
                        }
                    });
                }
            });
    }
    private SecretKey wrappingKey(boolean existing) throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey) store.getKey(ALIAS, null);
        if (existing) throw new IOException("The device security key is unavailable. The encrypted data has been preserved.");
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(30, KeyProperties.AUTH_BIOMETRIC_STRONG | KeyProperties.AUTH_DEVICE_CREDENTIAL)
            .build());
        return generator.generateKey();
    }
    private void loadKeys() throws Exception {
        StreamingAeadConfig.register();
        Files.createDirectories(objects.toPath());
        AtomicFile wrapped = new AtomicFile(new File(base, "keyset.wrap"));
        boolean existing = wrapped.getBaseFile().exists() || new File(base, "keyset.wrap.bak").exists();
        SecretKey key = wrappingKey(existing);
        KeysetHandle handle;
        byte[] clear = null;
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            if (existing) {
                byte[] value = wrapped.readFully();
                if (value.length < 29) throw new IOException("Invalid key envelope.");
                cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, Arrays.copyOf(value, 12)));
                cipher.updateAAD(KEY_AAD);
                clear = cipher.doFinal(Arrays.copyOfRange(value, 12, value.length));
                handle = CleartextKeysetHandle.read(BinaryKeysetReader.withBytes(clear));
            } else {
                handle = KeysetHandle.generateNew(StreamingAeadKeyTemplates.AES256_GCM_HKDF_1MB);
                ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                CleartextKeysetHandle.write(handle, BinaryKeysetWriter.withOutputStream(buffer));
                clear = buffer.toByteArray();
                cipher.init(Cipher.ENCRYPT_MODE, key); cipher.updateAAD(KEY_AAD);
                byte[] encrypted = cipher.doFinal(clear);
                ByteArrayOutputStream value = new ByteArrayOutputStream();
                value.write(cipher.getIV()); value.write(encrypted);
                atomicWrite(wrapped, value.toByteArray());
            }
            streaming = handle.getPrimitive(StreamingAead.class);
            File index = new File(base, "index.enc");
            if (index.exists() || new File(base, "index.enc.bak").exists()) {
                // Recover a committed AtomicFile backup before opening the encrypted stream.
                try (InputStream recovered = new AtomicFile(index).openRead()) { }
                entries = new JSONArray(new String(readEncrypted(index, "index"), StandardCharsets.UTF_8));
            } else entries = new JSONArray();
            unlocked = true;
        } finally { if (clear != null) Arrays.fill(clear, (byte) 0); }
    }
    private static void atomicWrite(AtomicFile file, byte[] data) throws IOException {
        FileOutputStream output = file.startWrite();
        try { output.write(data); file.finishWrite(output); }
        catch (Exception error) { file.failWrite(output); throw error; }
    }
    private byte[] aad(String id) { return ("yr-private-v1:" + id).getBytes(StandardCharsets.UTF_8); }
    private byte[] readEncrypted(File file, String id) throws Exception {
        try (InputStream input = streaming.newDecryptingStream(new FileInputStream(file), aad(id))) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[65536]; int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > 32 * 1024 * 1024) throw new IOException("Private index is too large.");
                output.write(buffer, 0, count);
            }
            return output.toByteArray();
        }
    }
    private void saveIndex(JSONArray next) throws Exception {
        requireUnlocked();
        AtomicFile file = new AtomicFile(new File(base, "index.enc"));
        FileOutputStream raw = file.startWrite();
        try {
            // AtomicFile needs to fsync the still-open descriptor itself.
            OutputStream nonClosing = new FilterOutputStream(raw) { @Override public void close() throws IOException { flush(); } };
            try (OutputStream encrypted = streaming.newEncryptingStream(nonClosing, aad("index"))) {
                encrypted.write(next.toString().getBytes(StandardCharsets.UTF_8));
            }
            file.finishWrite(raw); entries = next;
        } catch (Exception error) { file.failWrite(raw); throw error; }
    }
    private JSONObject entry(String id) throws Exception {
        for (int i = 0; i < entries.length(); i++) if (id.equals(entries.getJSONObject(i).getString("id"))) return entries.getJSONObject(i);
        throw new FileNotFoundException("Private item not found.");
    }
    private File object(String id) throws IOException {
        if (!id.matches("[a-f0-9-]{36}")) throw new IOException("Invalid private item.");
        return new File(objects, id + ".enc");
    }
    private static String validName(String name) throws IOException {
        if (name.trim().isEmpty() || name.equals(".") || name.equals("..") || name.contains("/") || name.contains("\\") || name.indexOf(0) >= 0) throw new IOException("Choose a valid name.");
        return name;
    }
    private void transfer(InputStream input, OutputStream output, MessageDigest digest) throws Exception {
        byte[] buffer = new byte[65536]; int count;
        try {
            while ((count = input.read(buffer)) != -1) {
                requireUnlocked(); output.write(buffer, 0, count);
                if (digest != null) digest.update(buffer, 0, count);
            }
        } finally { Arrays.fill(buffer, (byte) 0); }
    }
    private String importNode(Path source, String parent, JSONArray next, List<String> created) throws Exception {
        requireUnlocked();
        BasicFileAttributes attrs = Files.readAttributes(source, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
        if (attrs.isSymbolicLink() || (!attrs.isDirectory() && !attrs.isRegularFile())) throw new IOException("Links and special files cannot be moved to Private Space.");
        String id = UUID.randomUUID().toString(); created.add(id);
        JSONObject row = new JSONObject().put("id", id).put("parent", parent).put("name", source.getFileName().toString())
            .put("directory", attrs.isDirectory()).put("size", attrs.size()).put("modified", attrs.lastModifiedTime().toMillis()).put("original", source.toString());
        next.put(row);
        if (attrs.isDirectory()) {
            long total = 0;
            try (DirectoryStream<Path> children = Files.newDirectoryStream(source)) {
                for (Path child : children) { String childId = importNode(child, id, next, created); total += find(next, childId).getLong("size"); }
            }
            row.put("size", total);
        } else {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(source, LinkOption.NOFOLLOW_LINKS);
                 OutputStream encrypted = streaming.newEncryptingStream(new FileOutputStream(object(id)), aad(id))) {
                transfer(input, encrypted, digest);
            }
            byte[] expected = digest.digest();
            row.put("hash", android.util.Base64.encodeToString(expected, android.util.Base64.NO_WRAP));
            MessageDigest verify = MessageDigest.getInstance("SHA-256");
            try (InputStream input = streaming.newDecryptingStream(new FileInputStream(object(id)), aad(id))) {
                transfer(input, new OutputStream() { public void write(int value) {} public void write(byte[] b, int offset, int length) {} }, verify);
            }
            if (!MessageDigest.isEqual(expected, verify.digest())) throw new IOException("Encrypted copy verification failed; the source has not been removed.");
        }
        return id;
    }
    private static JSONObject find(JSONArray values, String id) throws Exception {
        for (int i = 0; i < values.length(); i++) if (id.equals(values.getJSONObject(i).getString("id"))) return values.getJSONObject(i);
        throw new FileNotFoundException();
    }
    private void removeOriginal(JSONObject row) throws Exception {
        requireUnlocked();
        String id = row.getString("id");
        if (row.getBoolean("directory")) {
            for (int i = 0; i < entries.length(); i++) {
                JSONObject child = entries.getJSONObject(i);
                if (id.equals(child.getString("parent"))) removeOriginal(child);
            }
        } else {
            Path path = Paths.get(row.getString("original"));
            BasicFileAttributes current = Files.readAttributes(path, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
            if (!current.isRegularFile() || current.size() != row.getLong("size") || current.lastModifiedTime().toMillis() != row.getLong("modified")) throw new IOException("The original changed while moving. Its encrypted copy is saved, but the original was kept.");
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            try (InputStream input = Files.newInputStream(path, LinkOption.NOFOLLOW_LINKS)) {
                transfer(input, new OutputStream() { public void write(int v) {} public void write(byte[] b, int o, int n) {} }, digest);
            }
            if (!MessageDigest.isEqual(android.util.Base64.decode(row.getString("hash"), android.util.Base64.NO_WRAP), digest.digest())) throw new IOException("The source changed. It has been kept alongside its encrypted copy.");
        }
        Files.delete(Paths.get(row.getString("original")));
    }
    private void exportNode(JSONObject row, Path destination) throws Exception {
        requireUnlocked();
        Path target = destination.resolve(validName(row.getString("name")));
        if (Files.exists(target, LinkOption.NOFOLLOW_LINKS)) throw new IOException("Already exists: " + row.getString("name") + ". Choose another folder.");
        if (row.getBoolean("directory")) {
            Files.createDirectory(target);
            for (int i = 0; i < entries.length(); i++) {
                JSONObject child = entries.getJSONObject(i);
                if (row.getString("id").equals(child.getString("parent"))) exportNode(child, target);
            }
        } else {
            try (InputStream input = streaming.newDecryptingStream(new FileInputStream(object(row.getString("id"))), aad(row.getString("id")));
                 OutputStream output = Files.newOutputStream(target, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE)) {
                transfer(input, output, null);
            } catch (Exception error) { Files.deleteIfExists(target); throw error; }
        }
    }
    private Set<String> descendants(Collection<String> ids) throws Exception {
        Set<String> all = new HashSet<>(ids); boolean changed;
        do {
            changed = false;
            for (int i = 0; i < entries.length(); i++) {
                JSONObject row = entries.getJSONObject(i);
                if (all.contains(row.getString("parent"))) changed |= all.add(row.getString("id"));
            }
        } while (changed);
        return all;
    }
    private void deleteEntries(Collection<String> ids) throws Exception {
        Set<String> removed = descendants(ids); JSONArray next = new JSONArray();
        for (int i = 0; i < entries.length(); i++) if (!removed.contains(entries.getJSONObject(i).getString("id"))) next.put(entries.getJSONObject(i));
        saveIndex(next);
        for (String id : removed) Files.deleteIfExists(object(id).toPath());
    }
    private void checkParent(String parent) throws Exception {
        if (!parent.isEmpty() && !entry(parent).getBoolean("directory")) throw new IOException("Choose a private folder.");
    }
    private String cloneNode(JSONObject source, String parent, JSONArray next, List<String> created) throws Exception {
        String id = UUID.randomUUID().toString(); created.add(id);
        JSONObject copy = new JSONObject(source.toString()).put("id", id).put("parent", parent);
        next.put(copy);
        if (source.getBoolean("directory")) {
            for (int i = 0; i < entries.length(); i++) {
                JSONObject child = entries.getJSONObject(i);
                if (source.getString("id").equals(child.getString("parent"))) cloneNode(child, id, next, created);
            }
        } else {
            try (InputStream input = streaming.newDecryptingStream(new FileInputStream(object(source.getString("id"))), aad(source.getString("id")));
                 OutputStream output = streaming.newEncryptingStream(new FileOutputStream(object(id)), aad(id))) {
                transfer(input, output, null);
            }
        }
        return id;
    }
    public void execute(String method, Map<String, Object> args, MethodChannel.Result result) {
        worker.execute(() -> {
            try {
                requireUnlocked(); Object value = null;
                String id = String.valueOf(args.getOrDefault("id", ""));
                if (method.equals("privateList")) {
                    List<Map<String, Object>> rows = new ArrayList<>();
                    for (int i = 0; i < entries.length(); i++) {
                        JSONObject row = entries.getJSONObject(i);
                        if (!id.equals(row.getString("parent"))) continue;
                        Map<String, Object> item = new HashMap<>();
                        for (String key : List.of("id", "parent", "name", "size", "directory", "modified")) item.put(key, row.get(key));
                        item.put("path", row.getString("id"));
                        item.put("category", com.somesh.yrfileexplorer.storage.FolderAnalyzer.category(row.getString("name")));
                        rows.add(item);
                    }
                    value = rows;
                } else if (method.equals("privateImport")) {
                    for (Object source : (List<?>) args.get("paths")) {
                        Path path = Paths.get(source.toString()).toAbsolutePath().normalize();
                        if (!path.toString().startsWith("/storage/") || Files.isSymbolicLink(path) || path.getNameCount() < 3 || path.toString().equals("/storage/emulated/0")) throw new IOException("Select files or folders inside device or removable storage.");
                        // Resolve aliases and reject a path containing any symlink.
                        if (!path.equals(path.toRealPath())) throw new IOException("Storage aliases and links are not supported for private moves.");
                        JSONArray next = new JSONArray(entries.toString()); List<String> created = new ArrayList<>();
                        String root;
                        try { root = importNode(path, "", next, created); saveIndex(next); }
                        catch (Exception error) { for (String object : created) Files.deleteIfExists(object(object).toPath()); throw error; }
                        removeOriginal(entry(root));
                    }
                } else if (method.equals("privateCreate")) {
                    String parent = String.valueOf(args.getOrDefault("parent", "")); checkParent(parent);
                    JSONArray next = new JSONArray(entries.toString());
                    next.put(new JSONObject().put("id", UUID.randomUUID().toString()).put("parent", parent)
                        .put("name", validName(String.valueOf(args.get("name")))).put("directory", true)
                        .put("size", 0).put("modified", System.currentTimeMillis()));
                    saveIndex(next);
                } else if (method.equals("privatePaste")) {
                    String parent = String.valueOf(args.getOrDefault("parent", "")); checkParent(parent);
                    List<String> ids = (List<String>) args.get("ids");
                    if (descendants(ids).contains(parent)) throw new IOException("Cannot move or copy a folder inside itself.");
                    JSONArray next = new JSONArray(entries.toString()); List<String> created = new ArrayList<>();
                    try {
                        for (String source : ids) {
                            if (Boolean.TRUE.equals(args.get("move"))) find(next, source).put("parent", parent);
                            else cloneNode(entry(source), parent, next, created);
                        }
                        saveIndex(next);
                    } catch (Exception error) { for (String object : created) Files.deleteIfExists(object(object).toPath()); throw error; }
                } else if (method.equals("privateRename")) {
                    JSONArray next = new JSONArray(entries.toString());
                    find(next, id).put("name", validName(String.valueOf(args.get("name")))); saveIndex(next);
                } else if (method.equals("privateDelete")) {
                    deleteEntries((List<String>) args.get("ids"));
                } else if (method.equals("privateExport")) {
                    Path destination = Paths.get(String.valueOf(args.get("destination"))).toRealPath();
                    if (!destination.toString().startsWith("/storage/") || !Files.isDirectory(destination)) throw new IOException("Choose a folder in device or removable storage.");
                    List<String> ids = (List<String>) args.get("ids");
                    for (String selected : ids) exportNode(entry(selected), destination);
                    if (Boolean.TRUE.equals(args.get("move"))) deleteEntries(ids);
                } else if (method.equals("privatePreview")) {
                    JSONObject row = entry(id);
                    if (row.getBoolean("directory")) throw new IOException("Open the folder to view its files.");
                    Path directory = previews.toPath().resolve(UUID.randomUUID().toString()); Files.createDirectories(directory);
                    exportNode(row, directory); value = directory.resolve(validName(row.getString("name"))).toString();
                } else throw new IOException("Unknown Private Space operation.");
                final Object response = value; main.post(() -> result.success(response));
            } catch (Exception error) { main.post(() -> result.error("PRIVATE_FILE", error.getMessage(), null)); }
        });
    }
    public static boolean mayReadPreview(android.content.Context context, File file) {
        try {
            return instance != null && instance.unlocked && android.os.Binder.getCallingUid() == android.os.Process.myUid()
                && file.getCanonicalPath().startsWith(new File(context.getCacheDir(), "private-space-previews").getCanonicalPath() + "/");
        } catch (IOException error) { return false; }
    }
    private static void eraseTree(Path path) {
        try { if (Files.exists(path)) Files.walkFileTree(path, new SimpleFileVisitor<Path>() {
            @Override public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException { Files.delete(file); return FileVisitResult.CONTINUE; }
            @Override public FileVisitResult postVisitDirectory(Path directory, IOException error) throws IOException { Files.delete(directory); return FileVisitResult.CONTINUE; }
        }); } catch (IOException ignored) { /* Retry on the next lock/start; never expose this app-private path. */ }
    }
}
