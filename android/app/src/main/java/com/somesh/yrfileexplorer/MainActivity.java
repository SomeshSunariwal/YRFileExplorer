package com.somesh.yrfileexplorer;

import com.somesh.yrfileexplorer.apps.AppCatalog;
import com.somesh.yrfileexplorer.archives.ArchiveEngine;
import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.files.FileOperationProgress;
import com.somesh.yrfileexplorer.files.TextFiles;
import com.somesh.yrfileexplorer.storage.DocumentEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;
import com.somesh.yrfileexplorer.media.MediaViewerActivity;
import com.somesh.yrfileexplorer.media.VideoViewerActivity;
import com.somesh.yrfileexplorer.media.PdfReaderActivity;
import com.somesh.yrfileexplorer.network.BluetoothFiles;
import com.somesh.yrfileexplorer.network.NetworkEngine;
import com.somesh.yrfileexplorer.network.DownloadTasks;
import com.somesh.yrfileexplorer.network.WebBrowserView;
import com.somesh.yrfileexplorer.network.NetworkEnvironment;
import com.somesh.yrfileexplorer.network.TransferServer;
import com.somesh.yrfileexplorer.security.ConnectionCredentials;
import com.somesh.yrfileexplorer.sharing.ShareProvider;

import android.app.*;
import android.content.*;
import android.content.pm.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
import android.os.storage.*;
import android.provider.*;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.*;
import org.json.*;
import java.io.*;
import java.nio.file.*;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

public class MainActivity extends FlutterActivity {
    private final ExecutorService workers = Executors.newFixedThreadPool(3);
    private final Map<String, AtomicBoolean> scans = new ConcurrentHashMap<>();
    private EventChannel.EventSink events;

    private MethodChannel.Result treeResult, uninstallResult, bluetoothPermissionResult, localNetworkPermissionResult;
    private BroadcastReceiver bluetoothReceiver;
    private SharedPreferences prefs;

    private final AtomicBoolean lanCancelled = new AtomicBoolean();
    private NetworkEngine network;
    private TransferServer transfer;

    @Override public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        prefs = getSharedPreferences("yr_preferences", MODE_PRIVATE);
        network = new NetworkEngine(getFilesDir());
        engine.getPlatformViewsController().getRegistry().registerViewFactory("yr/web", new WebBrowserView.Factory(engine.getDartExecutor().getBinaryMessenger()));
        new EventChannel(engine.getDartExecutor().getBinaryMessenger(), "yr/events").setStreamHandler(new EventChannel.StreamHandler() {
            @Override public void onListen(Object args, EventChannel.EventSink sink) { events = sink; }
            @Override public void onCancel(Object args) { events = null; }
        });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "yr/files").setMethodCallHandler((call, result) -> {
            try {
                switch (call.method) {
                    case "cancelLanScan": lanCancelled.set(true); result.success(null); return;
                    case "requestLocalNetwork":
                        if(Build.VERSION.SDK_INT < 37 || checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") == PackageManager.PERMISSION_GRANTED) { result.success(true); return; }
                        if(localNetworkPermissionResult != null) { result.error("PERMISSION_BUSY", "A local network permission request is already open", null); return; }
                        localNetworkPermissionResult = result;
                        requestPermissions(new String[]{"android.permission.ACCESS_LOCAL_NETWORK"}, 904); return;
                    case "openDownload": DownloadTasks.open(this, ((Number)call.argument("id")).longValue()); result.success(null); return;
                    case "hotspotSettings": {
                        Intent intent=new Intent("android.settings.TETHER_SETTINGS");
                        if(intent.resolveActivity(getPackageManager())==null)intent=new Intent(Settings.ACTION_WIRELESS_SETTINGS);
                        startActivity(intent);result.success(null);return;
                    }
                    case "networkSettings": startActivity(new Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY));result.success(null);return;
                    case "bluetoothSettings": startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));result.success(null);return;
                    case "requestBluetooth":
                        if(bluetoothPermissionResult!=null)throw new IOException("A Bluetooth permission request is already open");
                        bluetoothPermissionResult=result;requestPermissions(new String[]{android.Manifest.permission.BLUETOOTH_CONNECT,android.Manifest.permission.BLUETOOTH_SCAN},903);return;
                    case "bluetoothScan": {
                        android.bluetooth.BluetoothAdapter adapter=NetworkEnvironment.adapter(this);if(adapter==null)throw new IOException("Bluetooth is not available on this device");
                        if(!adapter.isEnabled())throw new IOException("Turn on Bluetooth first");
                        if(bluetoothReceiver==null){bluetoothReceiver=new BroadcastReceiver(){@Override public void onReceive(Context context,Intent intent){
                            if(events==null)return;
                            if(android.bluetooth.BluetoothDevice.ACTION_FOUND.equals(intent.getAction())){android.bluetooth.BluetoothDevice device=intent.getParcelableExtra(android.bluetooth.BluetoothDevice.EXTRA_DEVICE);if(device!=null)events.success(Map.of("type","bluetoothDevice","device",NetworkEnvironment.device(device)));}
                            else if(android.bluetooth.BluetoothAdapter.ACTION_DISCOVERY_FINISHED.equals(intent.getAction()))events.success(Map.of("type","bluetoothScanDone"));
                        }};IntentFilter filter=new IntentFilter(android.bluetooth.BluetoothDevice.ACTION_FOUND);filter.addAction(android.bluetooth.BluetoothAdapter.ACTION_DISCOVERY_FINISHED);if(Build.VERSION.SDK_INT>=33)registerReceiver(bluetoothReceiver,filter,Context.RECEIVER_EXPORTED);else registerReceiver(bluetoothReceiver,filter);}
                        adapter.cancelDiscovery();if(!adapter.startDiscovery())throw new IOException("Bluetooth discovery could not start");result.success(null);return;
                    }
                    case "bluetoothStop": {android.bluetooth.BluetoothAdapter adapter=NetworkEnvironment.adapter(this);if(adapter!=null&&checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN)==PackageManager.PERMISSION_GRANTED)adapter.cancelDiscovery();result.success(null);return;}
                    case "permission": result.success(Environment.isExternalStorageManager()); return;
                    case "requestPermission": startActivity(new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:" + getPackageName()))); result.success(null); return;
                    case "cancelAnalysis": { AtomicBoolean flag = scans.get(str(call,"id")); if (flag != null) flag.set(true); result.success(null); return; }
                    case "preferences": result.success(prefs.getString("settings", "{}")); return;
                    case "savePreferences": prefs.edit().putString("settings",str(call,"value")).apply(); result.success(null); return;
                    case "open": open(str(call,"path"), false); result.success(null); return;
                    case "openExternal": open(str(call,"path"), true); result.success(null); return;
                    case "share": share(call.argument("paths")); result.success(null); return;
                    case "setWallpaper": {
                        Uri image=ShareProvider.uri(new File(str(call,"path")));
                        Intent wallpaper=new Intent(Intent.ACTION_ATTACH_DATA).setDataAndType(image,"image/*").putExtra("mimeType","image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                        startActivity(Intent.createChooser(wallpaper,"Set background"));result.success(null);return;
                    }
                    case "pickTree":
                        if (treeResult != null) throw new IOException("A folder picker is already open");
                        treeResult = result;
                        startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION), 901); return;
                    case "uninstall":
                        if(uninstallResult!=null)throw new IOException("An uninstall request is already open");
                        uninstallResult=result;
                        try { startActivityForResult(new Intent(Intent.ACTION_DELETE, Uri.parse("package:"+str(call,"package"))).putExtra(Intent.EXTRA_RETURN_RESULT,true),902); }
                        catch(Exception error){uninstallResult=null;throw error;} return;
                    case "launchApp": {
                        Intent launch=getPackageManager().getLaunchIntentForPackage(str(call,"package"));
                        if(launch==null)throw new IOException("This application has no launch activity");startActivity(launch);result.success(null);return;
                    }
                    case "pinApp": {
                        String pkg=str(call,"package"); Intent launch=getPackageManager().getLaunchIntentForPackage(pkg);
                        if(launch==null)throw new IOException("This application has no launch activity");
                        android.content.pm.ShortcutManager manager=getSystemService(android.content.pm.ShortcutManager.class);
                        if(!manager.isRequestPinShortcutSupported())throw new IOException("Your launcher does not support pinned shortcuts");
                        ApplicationInfo app=getPackageManager().getApplicationInfo(pkg,0);
                        manager.requestPinShortcut(new ShortcutInfo.Builder(this,"app-"+pkg).setShortLabel(app.loadLabel(getPackageManager())).setIntent(launch).build(),null);result.success(null);return;
                    }
                    case "appSettings": startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + str(call,"package")))); result.success(null); return;
                    case "installPermission": startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + getPackageName()))); result.success(null); return;
                }
                workers.execute(() -> {
                    try { Object value = work(call); runOnUiThread(() -> result.success(value)); }
                    catch (Exception ex) { runOnUiThread(() -> result.error(ex instanceof InterruptedIOException ? "CANCELLED" : "FILE_ERROR", ex instanceof java.nio.file.AccessDeniedException ? "Android denied access to this folder: "+((java.nio.file.AccessDeniedException)ex).getFile() : ex.getMessage() == null ? ex.toString() : ex.getMessage(), null)); }
                });
            } catch (Exception ex) { result.error("ANDROID_ERROR", ex.getMessage(), null); }
        });
    }
    private static String str(MethodCall c, String key) { Object v = c.argument(key); return v == null ? "" : v.toString(); }
    private static boolean bool(MethodCall c, String key) { return Boolean.TRUE.equals(c.argument(key)); }
    private Object work(MethodCall c) throws Exception {
        String path = str(c,"path");
        switch (c.method) {
            case "appStorage": return getExternalFilesDir(null).getAbsolutePath();
            case "storageStats": { File folder=new File(path);return Map.of("total",folder.getTotalSpace(),"free",folder.getUsableSpace(),"used",folder.getTotalSpace()-folder.getUsableSpace()); }
            case "volumes": {
                List<Map<String,Object>> volumes = new ArrayList<>();
                StorageManager sm = getSystemService(StorageManager.class);
                for (StorageVolume v : sm.getStorageVolumes()) {
                    File f = v.getDirectory(); if (f == null) continue;
                    volumes.add(Map.of("name", v.isPrimary() ? "Internal Storage" : v.getDescription(this), "path", f.getAbsolutePath(), "total", f.getTotalSpace(), "free", f.getUsableSpace(), "removable", v.isRemovable()));
                }
                return volumes;
            }
            case "categoryCounts": {
                Map<String,Object> counts = new HashMap<>();
                for (String key : List.of("Images", "Music", "Videos", "Documents", "Archives")) counts.put(key, 0L);
                Files.walkFileTree(Paths.get(path), new SimpleFileVisitor<Path>() {
                    @Override public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) {
                        if (attrs.isRegularFile()) {
                            String category = FolderAnalyzer.category(file.toString());
                            if (counts.containsKey(category)) counts.put(category, ((Number)counts.get(category)).longValue() + 1);
                        }
                        return FileVisitResult.CONTINUE;
                    }
                    @Override public FileVisitResult visitFileFailed(Path file, IOException error) { return FileVisitResult.CONTINUE; }
                });
                long apps = 0;
                for (ApplicationInfo app : getPackageManager().getInstalledApplications(0)) {
                    if ((app.flags & ApplicationInfo.FLAG_SYSTEM) == 0) apps++;
                }
                counts.put("APP", apps);
                return counts;
            }
            case "list": return path.startsWith("content:") ? new DocumentEngine(this).list(path,bool(c,"hidden")) : FileEngine.list(path,bool(c,"hidden"));
            case "analyze": {
                String id = str(c,"id"); AtomicBoolean cancel = new AtomicBoolean(); scans.put(id,cancel);
                try {
                    java.util.function.Consumer<Map<String,Object>> progress = update -> {
                        update.put("id",id); update.put("type","analysis");
                        runOnUiThread(() -> { if (events != null) events.success(update); });
                    };
                    if(path.startsWith("content:")) return new DocumentEngine(this).analyze(path,cancel,progress);
                    FolderAnalyzer scanner = new FolderAnalyzer(cancel, progress);
                    return scanner.analyze(Paths.get(path), bool(c,"duplicates"));
                } finally { scans.remove(id); }
            }
            case "search": {
                String id=str(c,"id");AtomicBoolean cancel=new AtomicBoolean();scans.put(id,cancel);
                try{return FileEngine.search(path,str(c,"query"),str(c,"category"),10000,bool(c,"recursive"),bool(c,"hidden"),cancel);}finally{scans.remove(id);}
            }
            case "create": {
                Path p = FileEngine.named(Paths.get(path),str(c,"name"));
                if (bool(c,"directory")) Files.createDirectory(p); else Files.createFile(p); return p.toString();
            }
            case "rename": {
                Path p = Paths.get(path), target = FileEngine.named(p.getParent(),str(c,"name"));
                Files.move(p,target); return target.toString();
            }
            case "paste": {
                List<String> sources = c.argument("sources"); List<String> completed = new ArrayList<>();
                // Dragged groups are checked together before moving any source.
                if(bool(c,"preflight")) {
                    Set<Path> targets=new HashSet<>();
                    Path destination=Paths.get(path).toRealPath();
                    for(String source:sources) {
                        Path src=Paths.get(source).toRealPath();
                        Path dst=FileEngine.named(destination,Paths.get(source).getFileName().toString());
                        if(dst.startsWith(src))throw new IOException("Cannot move a folder into itself");
                        if(!targets.add(dst)||Files.exists(dst,LinkOption.NOFOLLOW_LINKS))throw new FileAlreadyExistsException(dst.toString());
                    }
                }
                FileOperationProgress progress = fileProgress(c, sources);
                for (String source : sources) {
                    Path src = Paths.get(source), dst = FileEngine.named(Paths.get(path),src.getFileName().toString());
                    if (dst.toAbsolutePath().normalize().startsWith(src.toAbsolutePath().normalize())) throw new IOException("Cannot paste into the source folder");
                    if(progress!=null)progress.start(src);
                    if (bool(c,"move")) {
                        try { Files.move(src,dst); } catch (FileSystemException ex) { if (Files.exists(dst)) throw ex; FileEngine.copy(src,dst,progress==null?null:progress::fileDone); FileEngine.delete(src); }
                    } else FileEngine.copy(src,dst,progress==null?null:progress::fileDone);
                    if(progress!=null)progress.finish(src);
                    completed.add(dst.toString());
                }
                return completed;
            }
            case "delete": {
                List<String> paths = c.argument("paths");
                FileOperationProgress progress = fileProgress(c, paths);
                for (String item : paths) {
                    Path source = Paths.get(item);
                    if(progress!=null)progress.start(source);
                    if(bool(c,"permanent"))FileEngine.delete(source,progress==null?null:progress::fileDone);
                    else trash(source,progress);
                    if(progress!=null)progress.finish(source);
                }
                return null;
            }
            case "trash": return trashList();
            case "restore": restore(str(c,"id")); return null;
            case "deleteTrash": {
                String id=str(c,"id");if(!id.matches("[a-f0-9-]{36}"))throw new IOException("Invalid recycle bin item");
                Path item=new File(getExternalFilesDir(null),"trash/"+id).toPath();if(Files.exists(item))FileEngine.delete(item);
                prefs.edit().remove("trash_"+id).commit();return null;
            }
            case "emptyTrash": {
                for (var row : trashList()) { FileEngine.delete(Paths.get((String)row.get("path"))); prefs.edit().remove("trash_"+row.get("id")).commit(); } return null;
            }
            case "archiveList": return ArchiveEngine.list(path,str(c,"prefix"),str(c,"password"),str(c,"charset"));
            case "archiveOpen": return ArchiveEngine.open(this,path,str(c,"entry"),str(c,"password"),str(c,"charset"));
            case "archiveExtract": { List<String> entries=c.argument("entries");ArchiveEngine.extract(path,str(c,"destination"),entries==null?List.of():entries,str(c,"password"),str(c,"charset"));return null; }
            case "archiveCreate": { if(str(c,"format").equals("7z"))com.somesh.yrfileexplorer.archives.SevenZipEngine.create(c.argument("paths"),str(c,"destination"),str(c,"password")); else FileEngine.zip(c.argument("paths"),str(c,"destination"),str(c,"password")); return null; }
            case "zip": FileEngine.zip(c.argument("paths"), str(c,"destination"),str(c,"password")); return null;
            case "unzip": FileEngine.unzip(path,str(c,"destination"),str(c,"password")); return null;
            case "crypt": return FileEngine.crypt(path,str(c,"password"),bool(c,"decrypt"),str(c,"name"));
            case "textInfo": return TextFiles.read(path,str(c,"encoding"));
            case "readText": return TextFiles.read(path,str(c,"encoding")).get("text");
            case "writeText": case "writeTextAs": TextFiles.write(path,str(c,"text"),str(c,"encoding"),str(c,"lineEnding"),bool(c,"bom"),c.method.equals("writeTextAs"));return null;
            case "properties": {
                Path p = Paths.get(path); var m = FolderAnalyzer.entry(p,Files.readAttributes(p,BasicFileAttributes.class));
                m.put("readable",Files.isReadable(p)); m.put("writable",Files.isWritable(p)); m.put("hidden",Files.isHidden(p)); return m;
            }
            case "checksum": {
                java.security.MessageDigest d = java.security.MessageDigest.getInstance("SHA-256");
                try(InputStream in=Files.newInputStream(Paths.get(path))) { byte[] b=new byte[131072]; int n; while((n=in.read(b))!=-1)d.update(b,0,n); }
                StringBuilder hash=new StringBuilder(); for(byte b:d.digest())hash.append(String.format("%02x",b)); return hash.toString();
            }
            case "apps": return new AppCatalog(this).installed(bool(c,"system"));
            case "apkFiles": return new AppCatalog(this).archives(path);
            case "exportApp": return new AppCatalog(this).export(str(c,"package"));
            case "backupApp": {
                String pkg=str(c,"package"); ApplicationInfo a=getPackageManager().getApplicationInfo(pkg,0);
                Path dest=Paths.get(str(c,"destination")); Files.createDirectories(dest);
                if(a.splitSourceDirs==null) { Path target=FileEngine.named(dest,pkg+".apk"); Files.copy(Paths.get(a.sourceDir),target); return target.toString(); }
                List<String> all=new ArrayList<>(); all.add(a.sourceDir); all.addAll(Arrays.asList(a.splitSourceDirs));
                String target=FileEngine.named(dest,pkg+".apks").toString(); FileEngine.zip(all,target,""); return target;
            }
            case "connectionPassword": return ConnectionCredentials.read(this,str(c,"id"));
            case "saveConnectionPassword": ConnectionCredentials.save(this,str(c,"id"),str(c,"password"));return null;
            case "networkInfo": return NetworkEnvironment.info(this);
            case "lanScan": lanCancelled.set(false); return NetworkEnvironment.scan(this,lanCancelled);
            case "bluetoothInfo": return NetworkEnvironment.bluetooth(this);
            case "network": return "Bluetooth".equals(str(c,"protocol"))?BluetoothFiles.execute(this,c.arguments()):network.execute(c.arguments());
            case "transferStart": {
                if(transfer!=null)transfer.close(); transfer=new TransferServer(Paths.get(path)); return transfer.start();
            }
            case "transferStop": if(transfer!=null) { transfer.close(); transfer=null; } return null;
            case "download": return DownloadTasks.enqueue(this, c.arguments());
            case "downloads": return DownloadTasks.list(this);
            case "cancelDownload": DownloadTasks.cancel(this, ((Number)c.argument("id")).longValue()); return null;
            case "retryDownload": return DownloadTasks.retry(this, ((Number)c.argument("id")).longValue());
            case "forgetDownload": DownloadTasks.forget(this, ((Number)c.argument("id")).longValue()); return null;
            case "documentImport": {
                Uri uri=Uri.parse(str(c,"uri")); String name=str(c,"name"); Path dest=FileEngine.named(Paths.get(path),name);
                if(Files.exists(dest))throw new IOException("Destination already exists");
                try(InputStream in=getContentResolver().openInputStream(uri)) { if(in==null)throw new IOException("Provider cannot open this file"); Files.copy(in,dest); } return dest.toString();
            }
            default: throw new IOException("Unknown operation: " + c.method);
        }
    }
    private FileOperationProgress fileProgress(MethodCall call,List<String> paths) throws IOException {
        String id=str(call,"operationId");
        return id.isEmpty()?null:new FileOperationProgress(id,paths,event->runOnUiThread(()->{if(events!=null)events.success(event);}));
    }
    private void trash(Path source,FileOperationProgress progress) throws Exception {
        String id=UUID.randomUUID().toString(); File base=new File(getExternalFilesDir(null),"trash"); if(!base.exists()&&!base.mkdirs())throw new IOException("Cannot create recycle bin");
        Path target=base.toPath().resolve(id);
        // Record metadata first so a process interruption cannot orphan a trashed item.
        JSONObject meta=new JSONObject().put("original",source.toString()).put("time",System.currentTimeMillis());
        prefs.edit().putString("trash_"+id,meta.toString()).commit();
        try { Files.move(source,target); }
        catch(FileSystemException ex) { try { FileEngine.copy(source,target,progress==null?null:progress::fileDone); FileEngine.delete(source); } catch(Exception fail) { if(!Files.exists(target))prefs.edit().remove("trash_"+id).commit(); throw fail; } }
    }
    private List<Map<String,Object>> trashList() throws Exception {
        List<Map<String,Object>> result=new ArrayList<>(); Path base=new File(getExternalFilesDir(null),"trash").toPath();
        for(var e:prefs.getAll().entrySet()) if(e.getKey().startsWith("trash_")) {
            String id=e.getKey().substring(6); Path p=base.resolve(id); if(!Files.exists(p))continue;
            JSONObject meta=new JSONObject(e.getValue().toString()); var row=FolderAnalyzer.entry(p,Files.readAttributes(p,BasicFileAttributes.class));
            row.put("id",id); row.put("original",meta.getString("original")); row.put("name",Paths.get(meta.getString("original")).getFileName().toString()); row.put("deleted",meta.getLong("time")); result.add(row);
        }
        return result;
    }
    private void restore(String id) throws Exception {
        if(!id.matches("[a-f0-9-]{36}"))throw new IOException("Invalid recycle bin item");
        JSONObject m=new JSONObject(prefs.getString("trash_"+id,"{}")); Path original=Paths.get(m.getString("original"));
        if(Files.exists(original))throw new IOException("A file already exists at the original location");
        Files.createDirectories(original.getParent()); Files.move(new File(getExternalFilesDir(null),"trash/"+id).toPath(),original); prefs.edit().remove("trash_"+id).commit();
    }
    private void open(String path, boolean external) {
        if(!external && (path.toLowerCase(Locale.ROOT).endsWith(".m3u")||path.toLowerCase(Locale.ROOT).endsWith(".m3u8"))){
            ArrayList<String> list=new ArrayList<>();try{
                Path base=Paths.get(path).toAbsolutePath().getParent();
                for(String line:Files.readAllLines(Paths.get(path),java.nio.charset.StandardCharsets.UTF_8)){
                    String value=line.trim();if(value.isEmpty()||value.startsWith("#")||value.contains("://"))continue;
                    Path file=base.resolve(value).normalize();if(Files.isRegularFile(file)&&Files.isReadable(file))list.add(file.toString());
                }
            }catch(IOException error){throw new IllegalArgumentException(error.getMessage(),error);}
            if(list.isEmpty())throw new IllegalArgumentException("Playlist contains no readable local files");
            String first=list.get(0);startActivity(new Intent(this,MediaViewerActivity.class).setDataAndType(ShareProvider.uri(new File(first)),"audio/*").putExtra("title",new File(first).getName()).putExtra("sourcePath",first).putStringArrayListExtra("playlist",list).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));return;
        }
        Uri u=path.startsWith("content:")?Uri.parse(path):ShareProvider.uri(new File(path));
        String mime=path.startsWith("content:")?getContentResolver().getType(u):new ShareProvider().getType(u);
        if(path.endsWith(".apk"))mime="application/vnd.android.package-archive";
        if(!external && ("application/pdf".equals(mime) || path.toLowerCase(Locale.ROOT).endsWith(".pdf"))) {
            startActivity(new Intent(this,PdfReaderActivity.class).setDataAndType(u,"application/pdf").putExtra("title",new File(path).getName()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)); return;
        }
        if(!external && mime!=null && mime.startsWith("video/")) {
            startActivity(new Intent(this,VideoViewerActivity.class).setDataAndType(u,mime).putExtra("title",new File(path).getName()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)); return;
        }
        if(!external && mime!=null && (mime.startsWith("video/")||mime.startsWith("audio/"))) {
            ArrayList<String> playlist=new ArrayList<>();
            if(mime.startsWith("audio/")&&!path.startsWith("content:")) {
                File parent=new File(path).getParentFile();File[] files=parent==null?null:parent.listFiles(f->f.isFile()&&f.getName().toLowerCase(Locale.ROOT).matches(".*\\.(mp3|m4a|aac|wav|ogg|flac|opus|amr)$"));
                if(files!=null){Arrays.sort(files,Comparator.comparing(File::getName,String.CASE_INSENSITIVE_ORDER));for(File f:files)playlist.add(f.getAbsolutePath());}
            }
            startActivity(new Intent(this,MediaViewerActivity.class).setDataAndType(u,mime).putExtra("title",new File(path).getName()).putExtra("sourcePath",path).putStringArrayListExtra("playlist",playlist).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)); return;
        }
        Intent i=new Intent(Intent.ACTION_VIEW).setDataAndType(u,mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        startActivity(Intent.createChooser(i,"Open with"));
    }
    private void share(List<String> paths) {
        ArrayList<Uri> uris=new ArrayList<>(); for(String p:paths)uris.add(p.startsWith("content:")?Uri.parse(p):ShareProvider.uri(new File(p)));
        Intent i=new Intent(uris.size()==1?Intent.ACTION_SEND:Intent.ACTION_SEND_MULTIPLE).setType("*/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        if(uris.size()==1)i.putExtra(Intent.EXTRA_STREAM,uris.get(0)); else i.putParcelableArrayListExtra(Intent.EXTRA_STREAM,uris);
        ClipData clip=ClipData.newRawUri("YR files",uris.get(0)); for(int n=1;n<uris.size();n++)clip.addItem(new ClipData.Item(uris.get(n))); i.setClipData(clip);
        startActivity(Intent.createChooser(i,"Share files"));
    }
    @Override public void onRequestPermissionsResult(int request,String[] permissions,int[] results){
        super.onRequestPermissionsResult(request,permissions,results);
        if(request==904 && localNetworkPermissionResult!=null) { MethodChannel.Result pending=localNetworkPermissionResult; localNetworkPermissionResult=null; pending.success(results.length>0 && results[0]==PackageManager.PERMISSION_GRANTED); }
        if(request==903&&bluetoothPermissionResult!=null){MethodChannel.Result pending=bluetoothPermissionResult;bluetoothPermissionResult=null;boolean allowed=results.length>0;for(int grant:results)allowed&=grant==PackageManager.PERMISSION_GRANTED;pending.success(allowed);}
    }
    @Override protected void onActivityResult(int request,int code,Intent data) {
        super.onActivityResult(request,code,data);
        if(request==902 && uninstallResult!=null) { MethodChannel.Result pending=uninstallResult;uninstallResult=null;pending.success(code==RESULT_OK);return; }
        if(request==901 && treeResult!=null) {
            MethodChannel.Result r=treeResult; treeResult=null;
            if(code!=RESULT_OK||data==null||data.getData()==null){r.success(null);return;}
            Uri u=data.getData();
            int grants=Intent.FLAG_GRANT_READ_URI_PERMISSION;
            if((data.getFlags()&Intent.FLAG_GRANT_WRITE_URI_PERMISSION)!=0)grants|=Intent.FLAG_GRANT_WRITE_URI_PERMISSION;
            try { getContentResolver().takePersistableUriPermission(u,grants); r.success(u.toString()); }
            catch(SecurityException e){r.error("PROVIDER_PERMISSION",e.getMessage(),null);}
        }
    }
    @Override protected void onDestroy() {
        for(AtomicBoolean flag:scans.values())flag.set(true);
        if(bluetoothReceiver!=null)unregisterReceiver(bluetoothReceiver);
        if(transfer!=null)transfer.close(); workers.shutdownNow(); super.onDestroy();
    }
}
