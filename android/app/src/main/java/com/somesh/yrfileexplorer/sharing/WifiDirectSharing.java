package com.somesh.yrfileexplorer.sharing;

import android.Manifest;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.NetworkInfo;
import android.net.wifi.WpsInfo;
import android.net.wifi.p2p.WifiP2pConfig;
import android.net.wifi.p2p.WifiP2pInfo;
import android.net.wifi.p2p.WifiP2pManager;
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo;
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;
import android.provider.Settings;
import android.media.MediaScannerConnection;
import com.somesh.yrfileexplorer.sharing.SharingHistory.OutgoingFile;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.json.JSONObject;
import org.json.JSONException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.SynchronousQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.function.Consumer;

/**
 * Explicit, foreground Wi-Fi Direct sessions. No internet service or cloud
 * account.
 */
public final class WifiDirectSharing implements AutoCloseable {
    private static final int PORT = 47861, PERMISSION = 905;
    private static final String SERVICE_NAME = "YRSharing", SERVICE_TYPE = "_yrsharing._tcp";
    private final Activity activity;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Consumer<Map<String, Object>> events;
    private final WifiP2pManager manager;
    private final WifiP2pManager.Channel channel;
    private final ExecutorService io = new ThreadPoolExecutor(2, 8, 30, TimeUnit.SECONDS, new SynchronousQueue<>(),
            new ThreadPoolExecutor.AbortPolicy());
    private final ExecutorService sends = Executors.newSingleThreadExecutor();
    private final Map<String, Map<String, Object>> nearby = new LinkedHashMap<>();
    private final Map<String, Peer> peers = new ConcurrentHashMap<>();
    private final Set<Socket> handshakes = ConcurrentHashMap.newKeySet();
    private final SharingHistory history;
    private final SecureRandom random = new SecureRandom();
    private volatile ServerSocket server;
    private volatile String code = "", state = "Idle", error = "";
    private volatile int generation, failures;
    private volatile boolean hosting, active, closed;
    private MethodChannel.Result permissionResult, joinResult;
    private String joinCode = "";
    private BroadcastReceiver receiver;
    private WifiP2pDnsSdServiceInfo service;
    private WifiP2pDnsSdServiceRequest request;
    private boolean discoveryStarted;

    public WifiDirectSharing(Activity activity, Consumer<Map<String, Object>> events) {
        this.activity = activity;
        this.events = events;
        history = new SharingHistory(activity);
        manager = (WifiP2pManager) activity.getSystemService(Context.WIFI_P2P_SERVICE);
        channel = manager == null ? null : manager.initialize(activity, Looper.getMainLooper(), () -> {
            stop();
            fail("Wi-Fi Direct disconnected. Open Sharing and reconnect.");
        });
    }

    private boolean supported() {
        return manager != null && channel != null
                && activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT);
    }

    private String permission() {
        return Build.VERSION.SDK_INT >= 33 ? "android.permission.NEARBY_WIFI_DEVICES"
                : Manifest.permission.ACCESS_FINE_LOCATION;
    }

    private void require() throws IOException {
        if (!supported())
            throw new IOException("Wi-Fi Direct is not supported on this device.");
        if (activity.checkSelfPermission(permission()) != PackageManager.PERMISSION_GRANTED)
            throw new IOException("Allow nearby Wi-Fi devices to continue.");
        if (Build.VERSION.SDK_INT <= 32
                && !((LocationManager) activity.getSystemService(Context.LOCATION_SERVICE)).isLocationEnabled())
            throw new IOException("Turn on Location for Wi-Fi Direct discovery on Android 12.");
        register();
    }

    public boolean permissionResult(int requestCode, int[] grants) {
        if (requestCode != PERMISSION)
            return false;
        if (permissionResult != null) {
            MethodChannel.Result r = permissionResult;
            permissionResult = null;
            r.success(grants.length > 0 && grants[0] == PackageManager.PERMISSION_GRANTED);
        }
        return true;
    }

    public void handle(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "sharingStatus": {
                    Number revision = call.argument("historyRevision");
                    Map<String, Object> status = new LinkedHashMap<>(snapshot());
                    Map<String, Object> updatedHistory = history.since(revision == null ? -1 : revision.longValue());
                    if (updatedHistory != null)
                        status.put("history", updatedHistory);
                    result.success(status);
                    return;
                }
                case "sharingClearHistory":
                    history.clear();
                    result.success(null);
                    changed();
                    return;
                case "sharingDefaultReceiveFolder":
                    result.success(defaultReceiveFolder().getPath());
                    return;
                case "sharingValidateReceiveFolder": {
                    String path = call.argument("path");
                    if (path == null || !new File(path).isAbsolute()) {
                        throw new IOException("Choose a folder in device storage.");
                    }
                    io.execute(() -> {
                        try {
                            result.success(validateReceiveFolder(new File(path), false).getPath());
                        } catch (Exception e) {
                            result.error("SHARING_FOLDER", message(e), null);
                        }
                    });
                    return;
                }
                case "sharingPermission":
                    if (!supported())
                        throw new IOException("Wi-Fi Direct is not supported on this device.");
                    if (activity.checkSelfPermission(permission()) == PackageManager.PERMISSION_GRANTED) {
                        result.success(true);
                        return;
                    }
                    if (permissionResult != null)
                        throw new IOException("A permission request is already open.");
                    permissionResult = result;
                    activity.requestPermissions(new String[] { permission() }, PERMISSION);
                    return;
                case "sharingSettings":
                    activity.startActivity(new Intent(Settings.ACTION_WIFI_SETTINGS));
                    result.success(null);
                    return;
                case "sharingStop":
                    stop();
                    result.success(null);
                    return;
                case "sharingCreate":
                    require();
                    if (active)
                        throw new IOException("Disconnect the current sharing session first.");
                    active = true;
                    hosting = true;
                    generation++;
                    failures = 0;
                    error = "";
                    state = "Creating network";
                    code = String.format(Locale.ROOT, "%06d", random.nextInt(1_000_000));
                    changed();
                    manager.createGroup(channel, listener(() -> {
                        manager.requestConnectionInfo(channel, this::connection);
                        result.success(snapshot());
                    }, message -> {
                        stop();
                        fail(message);
                        result.error("WIFI_DIRECT", message, null);
                    }));
                    return;
                case "sharingDiscover": {
                    require();
                    if (hosting)
                        throw new IOException("Disconnect your network before joining another.");
                    nearby.clear();
                    error = "";
                    state = "Searching";
                    active = true;
                    changed();
                    discoveryStarted = false;
                    if (request != null)
                        manager.removeServiceRequest(channel, request, null);
                    // The service-type-only overload requests PTR records, not the TXT data used here.
                    WifiP2pDnsSdServiceRequest scan = WifiP2pDnsSdServiceRequest.newInstance(SERVICE_NAME, SERVICE_TYPE);
                    request = scan;
                    manager.setDnsSdResponseListeners(channel, (name, type, device) -> {
                    }, (domain, record, device) -> {
                        if (request != scan || !active || hosting ||
                                !(SERVICE_NAME + "." + SERVICE_TYPE + ".local.").equalsIgnoreCase(domain)
                                || !"1".equals(record.get("version")))
                            return;
                        String name = record.get("name");
                        if (name == null || name.isBlank())
                            name = device.deviceName;
                        if (name == null || name.isBlank())
                            name = "Android device";
                        nearby.put(device.deviceAddress, Map.of("id", device.deviceAddress, "name", name));
                        changed();
                    });
                    Consumer<String> failed = message -> {
                        if (request == scan) {
                            stop();
                            fail(message);
                        }
                        result.error("WIFI_DIRECT", message, null);
                    };
                    manager.addServiceRequest(channel, scan, listener(() -> {
                        if (request != scan) {
                            result.error("CANCELLED", "Discovery stopped.", null);
                            return;
                        }
                        manager.discoverServices(channel, listener(() -> {
                            if (request == scan && "Searching".equals(state)) {
                                discoveryStarted = true;
                                main.postDelayed(() -> {
                                    if (request == scan && "Searching".equals(state)) {
                                        finishDiscovery();
                                        if (activity.checkSelfPermission(
                                                permission()) == PackageManager.PERMISSION_GRANTED) {
                                            manager.stopPeerDiscovery(channel, null);
                                        }
                                    }
                                }, TimeUnit.MINUTES.toMillis(2));
                            }
                            result.success(snapshot());
                        }, failed));
                    }, failed));
                    return;
                }
                case "sharingJoin": {
                    require();
                    if (joinResult != null || !peers.isEmpty())
                        throw new IOException("Disconnect before joining another network.");
                    String address = call.argument("device"), secret = call.argument("code");
                    if (address == null || !nearby.containsKey(address) || secret == null
                            || !secret.matches("[0-9]{6}"))
                        throw new IOException("Choose a network and enter its six-digit code.");
                    joinCode = secret;
                    joinResult = result;
                    hosting = false;
                    active = true;
                    error = "";
                    state = "Connecting";
                    int attempt = ++generation;
                    changed();
                    WifiP2pConfig config = new WifiP2pConfig();
                    config.deviceAddress = address;
                    config.wps.setup = WpsInfo.PBC;
                    config.groupOwnerIntent = 0;
                    manager.connect(channel, config, listener(() -> {
                    }, this::joinFailed));
                    main.postDelayed(() -> {
                        if (joinResult != null && generation == attempt)
                            joinFailed("Connection timed out. Check the other phone and try again.");
                    }, 60000);
                    return;
                }
                case "sharingSend": {
                    String id = call.argument("device");
                    List<String> paths = call.argument("paths");
                    Peer peer = peers.get(id);
                    if (peer == null || paths == null || paths.isEmpty())
                        throw new IOException("Choose a connected device and at least one file.");
                    List<String> copy = new ArrayList<>(paths);
                    sends.execute(() -> send(peer, copy, result));
                    return;
                }
                default:
                    result.notImplemented();
            }
        } catch (Exception e) {
            result.error("SHARING", message(e), null);
        }
    }

    private WifiP2pManager.ActionListener listener(Runnable success, Consumer<String> failure) {
        return new WifiP2pManager.ActionListener() {
            public void onSuccess() {
                success.run();
            }

            public void onFailure(int reason) {
                failure.accept(reason == WifiP2pManager.P2P_UNSUPPORTED ? "Wi-Fi Direct is unavailable."
                        : reason == WifiP2pManager.BUSY
                                ? "Wi-Fi Direct is busy. Disconnect another P2P session and retry."
                                : "Wi-Fi Direct could not start. Turn on Wi-Fi and retry.");
            }
        };
    }

    private void finishDiscovery() {
        if (!discoveryStarted || !"Searching".equals(state))
            return;
        discoveryStarted = false;
        state = "Scan complete";
        changed();
    }

    private void register() {
        if (receiver != null)
            return;
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                if (WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION.equals(i.getAction())) {
                    if (i.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1) != WifiP2pManager.WIFI_P2P_STATE_ENABLED
                            && active) {
                        stop();
                        fail("Wi-Fi Direct is off. Turn on Wi-Fi to share files.");
                    }
                } else if (WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION.equals(i.getAction())) {
                    if (i.getIntExtra(WifiP2pManager.EXTRA_DISCOVERY_STATE,
                            -1) == WifiP2pManager.WIFI_P2P_DISCOVERY_STOPPED)
                        finishDiscovery();
                } else if (active) {
                    manager.requestConnectionInfo(channel, WifiDirectSharing.this::connection);
                }
            }
        };
        IntentFilter f = new IntentFilter(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION);
        f.addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION);
        f.addAction(WifiP2pManager.WIFI_P2P_DISCOVERY_CHANGED_ACTION);
        if (Build.VERSION.SDK_INT >= 33)
            activity.registerReceiver(receiver, f, Context.RECEIVER_EXPORTED);
        else
            activity.registerReceiver(receiver, f);
    }

    private void connection(WifiP2pInfo info) {
        if (!active)
            return;
        if (!info.groupFormed) {
            if (server != null || !peers.isEmpty()) {
                stop();
                fail("Sharing network disconnected.");
            }
            return;
        }
        if (hosting && info.isGroupOwner && server == null) {
            try {
                ServerSocket socket = new ServerSocket();
                socket.bind(new InetSocketAddress(info.groupOwnerAddress, PORT));
                server = socket;
                int session = generation;
                state = "Network ready";
                changed();
                service = WifiP2pDnsSdServiceInfo.newInstance(SERVICE_NAME, SERVICE_TYPE,
                        Map.of("version", "1", "name", Build.MODEL));
                manager.addLocalService(channel, service, listener(() -> {
                }, this::fail));
                io.execute(() -> accept(socket, session));
            } catch (Exception e) {
                stop();
                fail(message(e));
            }
        } else if (!hosting && !info.isGroupOwner && joinResult != null && "Connecting".equals(state)) {
            state = "Authenticating";
            changed();
            int session = generation;
            String secret = joinCode;
            io.execute(() -> {
                Socket socket = new Socket();
                try {
                    socket.connect(new InetSocketAddress(info.groupOwnerAddress, PORT), 15000);
                    handshakes.add(socket);
                    authenticate(socket, secret, false, session);
                } catch (Exception e) {
                    try {
                        socket.close();
                    } catch (Exception ignored) {
                    }
                    main.post(() -> {
                        if (generation == session)
                            joinFailed("Unable to authenticate. Check the six-digit code and retry.");
                    });
                } finally {
                    handshakes.remove(socket);
                }
            });
        } else if (!hosting && info.isGroupOwner && joinResult != null)
            joinFailed("The other phone must create the network first. Disconnect and try again.");
    }

    private void accept(ServerSocket socket, int session) {
        while (active && generation == session) {
            try {
                Socket client = socket.accept();
                if (failures >= 5 || peers.size() >= 4 || handshakes.size() >= 2) {
                    client.close();
                    continue;
                }
                handshakes.add(client);
                try {
                    io.execute(() -> {
                        try {
                            authenticate(client, code, true, session);
                        } catch (Exception e) {
                            failures++;
                            try {
                                client.close();
                            } catch (Exception ignored) {
                            }
                            if (failures >= 5)
                                main.post(() -> {
                                    stop();
                                    fail("Too many unsuccessful codes. Create a new network to continue.");
                                });
                        } finally {
                            handshakes.remove(client);
                        }
                    });
                } catch (RejectedExecutionException e) {
                    handshakes.remove(client);
                    client.close();
                }
            } catch (IOException e) {
                if (active && generation == session)
                    main.post(() -> fail("Sharing network stopped."));
                break;
            }
        }
    }

    private void authenticate(Socket socket, String secret, boolean host, int session) throws Exception {
        DirectChannel secure = new DirectChannel(socket, secret, host);
        secure.send(new JSONObject().put("type", "hello").put("name", Build.MODEL));
        JSONObject hello = secure.receive();
        if (!"hello".equals(hello.optString("type")))
            throw new IOException("Invalid sharing device");
        String name = hello.optString("name", "");
        Peer peer = new Peer(secure, name.isBlank() ? "Android device" : name);
        if (!active || generation != session) {
            peer.close();
            return;
        }
        peers.put(secure.id, peer);
        main.post(() -> {
            if (!active || generation != session)
                return;
            state = "Connected";
            error = "";
            joinCode = "";
            if (joinResult != null) {
                MethodChannel.Result result = joinResult;
                joinResult = null;
                result.success(snapshot());
            }
            changed();
        });
        try {
            socket.setSoTimeout(0);
            peer.read();
        } finally {
            peer.close();
            // The reader owns the incoming file. Closing the socket wakes it for cleanup.
            if (peer.incoming != null)
                peer.incoming.abort();
            peers.remove(secure.id);
            main.post(() -> {
                if (active && generation == session) {
                    state = hosting ? "Network ready" : "Disconnected";
                    changed();
                }
            });
        }
    }

    private void joinFailed(String message) {
        MethodChannel.Result r = joinResult;
        joinResult = null;
        joinCode = "";
        generation++;
        for (Socket socket : handshakes)
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        handshakes.clear();
        if (r != null)
            r.error("PAIRING", message, null);
        active = false;
        manager.cancelConnect(channel, null);
        manager.removeGroup(channel, null);
        fail(message);
    }

    public Map<String, Object> snapshot() {
        List<Map<String, Object>> connected = new ArrayList<>();
        for (Peer p : peers.values())
            connected.add(Map.of("id", p.channel.id, "name", p.name));
        return Map.of("supported", supported(), "permission",
                activity.checkSelfPermission(permission()) == PackageManager.PERMISSION_GRANTED, "state", state,
                "error", error, "hosting", hosting, "code", hosting ? code : "", "networks",
                new ArrayList<>(nearby.values()), "devices", connected);
    }

    private void changed() {
        main.post(() -> {
            if (!closed)
                events.accept(Map.of("type", "sharingChanged"));
        });
    }

    private void fail(String message) {
        state = "Attention needed";
        error = message;
        changed();
    }

    private static String message(Exception e) {
        return e.getMessage() == null ? "Sharing could not finish. Reconnect and retry." : e.getMessage();
    }

    private File defaultReceiveFolder() {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
    }

    private File receiveFolder() throws IOException {
        String preferences = activity.getSharedPreferences("yr_preferences", Context.MODE_PRIVATE)
                .getString("settings", "{}");
        Object configured = null;
        try {
            configured = new JSONObject(preferences).opt("sharingReceiveFolder");
        } catch (JSONException ignored) {
            /* Use the default if preferences cannot be read. */ }
        if (configured instanceof String path && new File(path).isAbsolute()) {
            return validateReceiveFolder(new File(path), false);
        }
        return validateReceiveFolder(defaultReceiveFolder(), true);
    }

    private File validateReceiveFolder(File folder, boolean create) throws IOException {
        if (!Environment.isExternalStorageManager()) {
            throw new IOException("Allow storage access before receiving files.");
        }
        File canonical = folder.getCanonicalFile();
        Path path = canonical.toPath();
        for (StorageVolume volume : activity.getSystemService(StorageManager.class).getStorageVolumes()) {
            File directory = volume.getDirectory();
            if (directory == null || !Environment.MEDIA_MOUNTED.equals(volume.getState()))
                continue;
            Path root = directory.getCanonicalFile().toPath();
            if (!path.startsWith(root)
                    || path.startsWith(root.resolve("Android/data"))
                    || path.startsWith(root.resolve("Android/obb")))
                continue;
            if (create)
                Files.createDirectories(path);
            if (Files.isDirectory(path) && Files.isWritable(path))
                return canonical;
        }
        throw new IOException("The receive folder is unavailable or not writable. Choose a folder in Settings.");
    }

    private void collect(File f, String relative, List<OutgoingFile> files, Set<String> seen, int depth)
            throws IOException {
        if (depth > 64 || files.size() >= 10000)
            throw new IOException("Select fewer files or a less deeply nested folder.");
        if (Files.isSymbolicLink(f.toPath()) || !seen.add(f.getCanonicalPath()))
            throw new IOException("Symbolic links cannot be shared.");
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children == null)
                throw new IOException("This folder cannot be read.");
            for (File child : children)
                collect(child, relative + "/" + child.getName(), files, seen, depth + 1);
        } else if (f.isFile() && f.canRead())
            files.add(new OutgoingFile(f, relative));
        else
            throw new IOException("This file cannot be read.");
    }

    private void send(Peer peer, List<String> sources, MethodChannel.Result result) {
        List<OutgoingFile> files = new ArrayList<>();
        try {
            Set<String> seen = new HashSet<>();
            for (String path : sources) {
                File f = new File(path);
                String canonical = f.getCanonicalPath();
                if (!canonical.startsWith("/storage/") || canonical.startsWith(activity.getFilesDir().getPath()))
                    throw new IOException("Only shared-storage files can be sent.");
                if (seen.contains(canonical))
                    continue;
                collect(f, f.getName(), files, seen, 0);
            }
            if (files.isEmpty())
                throw new IOException("There are no readable files to send.");
            if (!peers.containsKey(peer.channel.id))
                throw new IOException("Device disconnected.");
            history.enqueue(files, peer.name);
        } catch (Exception e) {
            main.post(() -> result.error("SHARING_FILES", message(e), null));
            return;
        }

        changed();
        main.post(() -> result.success(null));
        String batch = UUID.randomUUID().toString();
        try {
            byte[] buffer = new byte[65536];
            synchronized (peer.channel.batchLock) {
                for (OutgoingFile file : files)
                    sendFile(peer, batch, file, buffer);
            }
        } catch (Exception e) {
            history.failPending(files);
            peer.close();
            main.post(() -> fail(message(e)));
        }
    }

    private void sendFile(Peer peer, String batch, OutgoingFile file, byte[] buffer) throws Exception {
        if (!peers.containsKey(peer.channel.id))
            throw new IOException("Device disconnected.");
        String id = file.id();
        CompletableFuture<Boolean> ready = new CompletableFuture<>(), done = new CompletableFuture<>();
        peer.ready.put(id, ready);
        peer.done.put(id, done);
        try {
            peer.channel.send(new JSONObject().put("type", "file").put("id", id)
                    .put("batch", batch).put("name", file.name()).put("size", file.size()));
            if (!ready.get(30, TimeUnit.SECONDS))
                throw new IOException("The receiving device declined this file.");
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            long bytes = 0, lastUpdate = -250;
            try (InputStream in = new FileInputStream(file.file())) {
                int count;
                while ((count = in.read(buffer)) != -1) {
                    bytes += count;
                    if (bytes > file.size())
                        throw new IOException("The source file changed during sharing.");
                    digest.update(buffer, 0, count);
                    byte[] chunk = count == buffer.length ? buffer : Arrays.copyOf(buffer, count);
                    peer.channel.send(new JSONObject().put("type", "data").put("id", id)
                            .put("data", Base64.getEncoder().encodeToString(chunk)));
                    long now = SystemClock.elapsedRealtime();
                    if (now - lastUpdate >= 250) {
                        recordSent(peer, file, bytes, "Sending");
                        lastUpdate = now;
                    }
                }
            }
            if (bytes != file.size())
                throw new IOException("The source file changed during sharing.");
            recordSent(peer, file, bytes, "Verifying");
            peer.channel.send(new JSONObject().put("type", "end").put("id", id)
                    .put("hash", Base64.getEncoder().encodeToString(digest.digest())));
            if (!done.get(60, TimeUnit.SECONDS))
                throw new IOException("The receiving device could not save this file.");
            recordSent(peer, file, bytes, "Completed");
        } finally {
            peer.ready.remove(id);
            peer.done.remove(id);
        }
    }

    private void recordSent(Peer peer, OutgoingFile file, long bytes, String status) {
        history.updateSent(file, peer.name, bytes, status);
        changed();
    }

    private final class Peer implements AutoCloseable {
        final DirectChannel channel;
        final String name;
        final Map<String, CompletableFuture<Boolean>> ready = new ConcurrentHashMap<>(),
                done = new ConcurrentHashMap<>();
        Incoming incoming;
        String receivingBatch;
        File receivingFolder;

        Peer(DirectChannel c, String name) {
            channel = c;
            this.name = name.length() > 80 ? name.substring(0, 80) : name;
        }

        File folderForBatch(String batch) throws IOException {
            if (!batch.equals(receivingBatch)) {
                receivingFolder = receiveFolder();
                receivingBatch = batch;
            }
            return receivingFolder;
        }

        void read() throws Exception {
            while (active) {
                JSONObject m = channel.receive();
                String id = m.optString("id");
                switch (m.optString("type")) {
                    case "ready": {
                        CompletableFuture<Boolean> f = ready.get(id);
                        if (f != null)
                            f.complete(m.optBoolean("ok"));
                        break;
                    }
                    case "saved": {
                        CompletableFuture<Boolean> f = done.get(id);
                        if (f != null)
                            f.complete(m.optBoolean("ok"));
                        break;
                    }
                    case "file":
                        if (incoming != null)
                            throw new IOException("Unexpected file in sharing stream.");
                        try {
                            incoming = new Incoming(m, this);
                        } catch (Exception e) {
                            int session = generation;
                            main.post(() -> {
                                if (active && generation == session) {
                                    error = message(e);
                                    changed();
                                }
                            });
                            channel.send(new JSONObject().put("type", "ready").put("id", id).put("ok", false));
                            return;
                        }
                        channel.send(new JSONObject().put("type", "ready").put("id", id).put("ok", true));
                        break;
                    case "data":
                        if (incoming == null || !incoming.id.equals(id))
                            throw new IOException("Unexpected sharing data.");
                        incoming.write(Base64.getDecoder().decode(m.getString("data")));
                        break;
                    case "end":
                        if (incoming == null || !incoming.id.equals(id))
                            throw new IOException("Unexpected file completion.");
                        incoming.finish(m.getString("hash"));
                        incoming = null;
                        channel.send(new JSONObject().put("type", "saved").put("id", id).put("ok", true));
                        break;
                    default:
                        throw new IOException("Unrecognized sharing message.");
                }
            }
        }

        @Override
        public void close() {
            channel.close();
            ready.values().forEach(f -> f.complete(false));
            done.values().forEach(f -> f.complete(false));
        }
    }

    private final class Incoming {
        final String id, name, peer;
        final long size;
        long bytes, last;
        final File target, temp;
        final FileOutputStream out;
        final MessageDigest digest;

        Incoming(JSONObject m, Peer source) throws Exception {
            id = m.getString("id");
            name = m.getString("name");
            peer = source.name;
            size = m.getLong("size");
            String batch = m.getString("batch");
            if (!id.matches("[a-f0-9-]{36}") || !batch.matches("[a-f0-9-]{36}") || size < 0 || name.length() > 2048)
                throw new IOException("Invalid sharing file.");
            if (!Environment.isExternalStorageManager())
                throw new IOException("Allow storage access before receiving files.");
            File base = new File(source.folderForBatch(batch), batch);
            File parent = base;
            String[] parts = name.split("/", -1);
            for (int i = 0; i < parts.length; i++) {
                String part = parts[i];
                if (part.isEmpty() || part.equals(".") || part.equals("..") || part.contains("\\")
                        || part.indexOf('\0') >= 0)
                    throw new IOException("Unsafe sharing filename.");
                if (i < parts.length - 1)
                    parent = new File(parent, part);
            }
            if (!parent.getCanonicalFile().equals(parent))
                throw new IOException("Unsafe receiving folder.");
            Files.createDirectories(parent.toPath());
            if (!parent.getCanonicalFile().equals(parent))
                throw new IOException("Unsafe receiving folder.");
            if (size > parent.getUsableSpace() - 8 * 1024 * 1024)
                throw new IOException("Not enough storage to receive this file.");
            File chosen = new File(parent, parts[parts.length - 1]);
            for (int n = 1; chosen.exists(); n++)
                chosen = new File(parent, n + "_" + parts[parts.length - 1]);
            target = chosen;
            temp = File.createTempFile(".yr-sharing-", ".part", parent);
            out = new FileOutputStream(temp);
            digest = MessageDigest.getInstance("SHA-256");
            recordReceived("Receiving", null);
        }

        void write(byte[] data) throws IOException {
            if (bytes + data.length > size)
                throw new IOException("File exceeds its declared size.");
            out.write(data);
            digest.update(data);
            bytes += data.length;
            long now = SystemClock.elapsedRealtime();
            if (now - last >= 250) {
                recordReceived("Receiving", null);
                last = now;
            }
        }

        void finish(String hash) throws IOException {
            if (bytes != size || !MessageDigest.isEqual(digest.digest(), Base64.getDecoder().decode(hash))) {
                throw new IOException("File verification failed.");
            }
            out.getFD().sync();
            out.close();
            Files.move(temp.toPath(), target.toPath());
            recordReceived("Completed", target.getPath());
            MediaScannerConnection.scanFile(activity, new String[] { target.getPath() }, null, null);
        }

        void abort() {
            try {
                out.close();
            } catch (IOException ignored) {
            }
            temp.delete();
            recordReceived("Interrupted", null);
        }

        private void recordReceived(String status, String path) {
            history.updateReceived(id, name, peer, bytes, size, status, path);
            changed();
        }
    }

    public void stop() {
        active = false;
        hosting = false;
        generation++;
        code = "";
        joinCode = "";
        state = "Idle";
        error = "";
        nearby.clear();
        discoveryStarted = false;
        if (joinResult != null) {
            MethodChannel.Result r = joinResult;
            joinResult = null;
            r.error("CANCELLED", "Sharing disconnected.", null);
        }
        ServerSocket s = server;
        server = null;
        if (s != null)
            try {
                s.close();
            } catch (IOException ignored) {
            }
        for (Socket socket : handshakes)
            try {
                socket.close();
            } catch (IOException ignored) {
            }
        handshakes.clear();
        peers.values().forEach(Peer::close);
        peers.clear();
        if (manager != null && channel != null
                && activity.checkSelfPermission(permission()) == PackageManager.PERMISSION_GRANTED) {
            manager.stopPeerDiscovery(channel, null);
            manager.cancelConnect(channel, null);
            if (service != null)
                manager.removeLocalService(channel, service, null);
            service = null;
            if (request != null)
                manager.removeServiceRequest(channel, request, null);
            request = null;
            manager.removeGroup(channel, null);
        }
        changed();
    }

    @Override
    public void close() {
        stop();
        closed = true;
        if (receiver != null) {
            activity.unregisterReceiver(receiver);
            receiver = null;
        }
        if (channel != null)
            channel.close();
        io.shutdownNow();
        sends.shutdownNow();
        if (permissionResult != null) {
            permissionResult.error("CANCELLED", "Sharing closed.", null);
            permissionResult = null;
        }
    }
}
