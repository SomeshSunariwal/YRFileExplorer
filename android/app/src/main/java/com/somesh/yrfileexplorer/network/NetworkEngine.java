package com.somesh.yrfileexplorer.network;

import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Base64;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import com.jcraft.jsch.ChannelSftp;
import com.jcraft.jsch.HostKey;
import com.jcraft.jsch.HostKeyRepository;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.JSchException;
import com.jcraft.jsch.SftpATTRS;
import com.jcraft.jsch.SftpException;
import com.jcraft.jsch.UserInfo;
import org.apache.commons.net.ftp.FTP;
import org.apache.commons.net.ftp.FTPClient;
import org.apache.commons.net.ftp.FTPFile;
import org.apache.commons.net.ftp.FTPReply;
import org.apache.commons.net.ftp.FTPSClient;
import com.hierynomus.smbj.SMBClient;
import com.hierynomus.smbj.SmbConfig;
import com.hierynomus.smbj.auth.AuthenticationContext;
import com.hierynomus.smbj.share.DiskShare;
import com.hierynomus.msdtyp.AccessMask;
import com.hierynomus.mssmb2.SMB2CreateDisposition;
import com.hierynomus.mssmb2.SMB2ShareAccess;
import okhttp3.Credentials;
import okhttp3.HttpUrl;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import javax.xml.parsers.DocumentBuilderFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

/** Explicit user-configured connections only; no discovery, telemetry, or remote configuration. */
public final class NetworkEngine {

    private final Path privateDirectory;

    public NetworkEngine(File privateDir) { privateDirectory=privateDir.toPath(); }
    private static void pump(InputStream in, OutputStream out) throws IOException {
        byte[] b=new byte[131072]; int n; while((n=in.read(b))!=-1)out.write(b,0,n);
    }
    private static byte[] bounded(InputStream in,int limit) throws IOException {
        ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] b=new byte[16384];int n;
        while(out.size()<limit&&(n=in.read(b,0,Math.min(b.length,limit-out.size())))!=-1)out.write(b,0,n);return out.toByteArray();
    }
    private static String s(Map<String,Object> m,String k) { return Objects.toString(m.get(k),""); }
    private static Map<String,Object> row(String name,String path,boolean dir,long bytes,long modified) {
        return Map.of("name",name,"path",path,"directory",dir,"size",bytes,"modified",modified,"category",FolderAnalyzer.category(name));
    }
    private static Path local(Map<String,Object> a) throws IOException {
        Path p=Paths.get(s(a,"local")).toAbsolutePath();Files.createDirectories(p.getParent()); if(Files.exists(p))throw new FileAlreadyExistsException(p.toString()); return p;
    }
    @FunctionalInterface private interface Writer {void write(OutputStream out)throws IOException;}
    private static void receive(Map<String,Object> a,Writer writer)throws IOException {
        Path target=local(a).toAbsolutePath();Path temp=Files.createTempFile(target.getParent(),".yr-download-",".tmp");
        try {try(OutputStream out=Files.newOutputStream(temp)){writer.write(out);}Files.move(temp,target);}
        finally{Files.deleteIfExists(temp);}
    }
    public Object execute(Map<String,Object> a) throws Exception {
        String protocol=s(a,"protocol");
        if(s(a,"host").trim().isEmpty())throw new IOException("Enter a server address");
        String action=s(a,"action"), source=s(a,"path").replace('\\','/').replaceAll("/+$", "");
        if((action.equals("delete")||action.equals("rename"))&&source.isEmpty())throw new IOException("The remote root cannot be removed or renamed");
        if(action.equals("copy")) {
            String destination=s(a,"destination").replace('\\','/').replaceAll("/+$", "");
            if(source.isEmpty()||destination.equals(source)||destination.startsWith(source+"/"))throw new IOException("Choose a different destination outside the source folder");
            Path workspace=Files.createTempDirectory(privateDirectory,"network-copy-");
            try {
                Map<String,Object> request=new HashMap<>(a);request.put("action","get");request.put("local",workspace.resolve("item").toString());
                Object downloaded=execute(request);if(downloaded instanceof Map<?,?>)return downloaded;
                request.put("action","put");request.put("path",s(a,"destination"));return execute(request);
            }finally{FileEngine.delete(workspace);}
        }
        return switch(protocol) { case "SFTP" -> sftp(a); case "FTP", "FTPS" -> ftp(a); case "SMB" -> smb(a); case "WebDAV" -> davDispatch(a); default -> throw new IOException("Unsupported protocol"); };
    }
    private Object sftp(Map<String,Object> a) throws Exception {
        JSch jsch=new JSch(); String[] seen={""}; String trusted=s(a,"fingerprint");
        jsch.setHostKeyRepository(new HostKeyRepository() {
            @Override public int check(String host,byte[] key) {
                try { seen[0]="SHA256:"+Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(key)); }
                catch(Exception e){return CHANGED;}
                return seen[0].equals(trusted)?OK:NOT_INCLUDED;
            }
            public void add(HostKey h,UserInfo ui){} public void remove(String h,String t){} public void remove(String h,String t,byte[] k){}
            public String getKnownHostsRepositoryID(){return "YR verified host keys";} public HostKey[] getHostKey(){return new HostKey[0];} public HostKey[] getHostKey(String h,String t){return new HostKey[0];}
        });
        int port=s(a,"port").isEmpty()?22:Integer.parseInt(s(a,"port"));
        com.jcraft.jsch.Session session=jsch.getSession(s(a,"username"),s(a,"host"),port);
        session.setPassword(s(a,"password")); session.setConfig("StrictHostKeyChecking","yes"); session.setConfig("PreferredAuthentications","password"); session.setTimeout(20000);
        ChannelSftp channel=null;
        try {
            try { session.connect(20000); }
            catch(JSchException ex) { if(!seen[0].isEmpty()&&!seen[0].equals(trusted))return Map.of("needsTrust",true,"fingerprint",seen[0],"changed",!trusted.isEmpty()); throw ex; }
            channel=(ChannelSftp)session.openChannel("sftp"); channel.connect(20000);
            if(!s(a,"encoding").isEmpty()&&!s(a,"encoding").equals("AUTO"))channel.setFilenameEncoding(s(a,"encoding"));
            String path=s(a,"path"); if(path.isEmpty())path="/";
            switch(s(a,"action")) {
                case "list": {
                    List<Map<String,Object>> rows=new ArrayList<>();
                    for(var item:channel.ls(path)) { ChannelSftp.LsEntry e=(ChannelSftp.LsEntry)item; String n=e.getFilename(); if(n.equals(".")||n.equals(".."))continue; var at=e.getAttrs(); rows.add(row(n,path.replaceAll("/$","")+"/"+n,at.isDir(),at.getSize(),at.getMTime()*1000L)); } return rows;
                }
                case "get": {
                    Path target=local(a).toAbsolutePath(),staging=target.resolveSibling(".yr-download-"+UUID.randomUUID());
                    try{downloadSftp(channel,path,staging,0);Files.move(staging,target);}finally{if(Files.exists(staging))FileEngine.delete(staging);}return null;
                }
                case "put": {
                    try { channel.lstat(path); throw new IOException("Remote file already exists"); } catch(SftpException ex) { if(ex.id!=ChannelSftp.SSH_FX_NO_SUCH_FILE)throw ex; }
                    uploadSftp(channel,Paths.get(s(a,"local")),path,0);return null;
                }
                case "mkdir": channel.mkdir(path); return null;
                case "delete": deleteSftp(channel,path,0); return null;
                case "rename": {
                    String destination=s(a,"destination");
                    try{channel.lstat(destination);throw new IOException("Remote destination already exists");}catch(SftpException ex){if(ex.id!=ChannelSftp.SSH_FX_NO_SUCH_FILE)throw ex;}
                    channel.rename(path,destination);return null;
                }
                default: throw new IOException("Unsupported SFTP operation");
            }
        } finally { if(channel!=null)channel.disconnect(); session.disconnect(); }
    }
    private Object ftp(Map<String,Object> a) throws Exception {
        FTPClient client=s(a,"protocol").equals("FTPS")?new FTPSClient(Boolean.TRUE.equals(a.get("implicit"))):new FTPClient();
        String encoding=s(a,"encoding");if(encoding.isEmpty()||encoding.equals("AUTO"))client.setAutodetectUTF8(true);else client.setControlEncoding(encoding);
        client.setConnectTimeout(20000); client.setDefaultTimeout(20000); client.setDataTimeout(java.time.Duration.ofSeconds(30));
        if(client instanceof FTPSClient tls){
            tls.setEndpointCheckingEnabled(true);
            javax.net.ssl.TrustManagerFactory factory=javax.net.ssl.TrustManagerFactory.getInstance(javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm());
            factory.init((java.security.KeyStore)null);
            for(var manager:factory.getTrustManagers())if(manager instanceof javax.net.ssl.X509TrustManager trust)tls.setTrustManager(trust);
        }
        try {
            client.connect(s(a,"host"),s(a,"port").isEmpty()?21:Integer.parseInt(s(a,"port")));
            if(!client.login(s(a,"username"),s(a,"password")))throw new IOException("FTP authentication failed");
            if(client instanceof FTPSClient tls){tls.execPBSZ(0);tls.execPROT("P");}
            if(Boolean.FALSE.equals(a.get("passive")))client.enterLocalActiveMode();else client.enterLocalPassiveMode();client.setFileType(FTP.BINARY_FILE_TYPE);
            String path=s(a,"path"),action=s(a,"action"); if(path.isEmpty())path="/";
            switch(action) {
                case "list": {
                    List<Map<String,Object>> rows=new ArrayList<>(); FTPFile[] entries=client.listFiles(path);
                    if(!FTPReply.isPositiveCompletion(client.getReplyCode()))throw new IOException(client.getReplyString());
                    for(FTPFile e:entries) { String n=e.getName(); if(n.equals(".")||n.equals(".."))continue; rows.add(row(n,path.replaceAll("/$","")+"/"+n,e.isDirectory(),e.getSize(),e.getTimestamp()==null?0:e.getTimestamp().getTimeInMillis())); } return rows;
                }
                case "get": {
                    Path target=local(a).toAbsolutePath(),staging=target.resolveSibling(".yr-download-"+UUID.randomUUID());
                    try{downloadFtp(client,path,staging,0);Files.move(staging,target);}finally{if(Files.exists(staging))FileEngine.delete(staging);}return null;
                }
                case "put": if(ftpDirectory(client,path)||client.listFiles(path).length>0)throw new IOException("Remote file already exists");uploadFtp(client,Paths.get(s(a,"local")),path,0);return null;
                case "mkdir": if(!client.makeDirectory(path))throw new IOException(client.getReplyString());return null;
                case "delete": deleteFtp(client,path,0);return null;
                case "rename": if(ftpDirectory(client,s(a,"destination"))||client.listFiles(s(a,"destination")).length>0)throw new IOException("Remote destination already exists");if(!client.rename(path,s(a,"destination")))throw new IOException(client.getReplyString());return null;
                default:throw new IOException("Unsupported FTP operation");
            }
        } finally { if(client.isConnected())client.disconnect(); }
    }
    private static void depth(int depth)throws IOException {if(depth>128)throw new IOException("Remote folder nesting exceeds 128 levels");}
    private static String child(String parent,String name)throws IOException {
        if(name.isEmpty()||name.equals(".")||name.equals("..")||name.contains("/")||name.contains("\\")||name.indexOf(0)>=0)throw new IOException("Invalid remote file name");
        return parent.replaceAll("/$","")+"/"+name;
    }
    private static boolean ftpDirectory(FTPClient ftp,String path)throws IOException {
        String previous=ftp.printWorkingDirectory();if(previous==null)throw new IOException("FTP server did not return its working directory");
        boolean dir=ftp.changeWorkingDirectory(path);if(dir&&!ftp.changeWorkingDirectory(previous))throw new IOException("Cannot restore FTP working directory");return dir;
    }
    private static void downloadFtp(FTPClient ftp,String remote,Path local,int level)throws Exception {
        depth(level);
        if(ftpDirectory(ftp,remote)){
            Files.createDirectory(local);FTPFile[] entries=ftp.listFiles(remote);if(!FTPReply.isPositiveCompletion(ftp.getReplyCode()))throw new IOException(ftp.getReplyString());
            for(FTPFile entry:entries){String name=entry.getName();if(name.equals(".")||name.equals(".."))continue;if(entry.isSymbolicLink())throw new IOException("Symbolic links are not downloaded recursively");downloadFtp(ftp,child(remote,name),FileEngine.named(local,name),level+1);}
        }else try(OutputStream out=Files.newOutputStream(local,StandardOpenOption.CREATE_NEW)){if(!ftp.retrieveFile(remote,out))throw new IOException(ftp.getReplyString());}
    }
    private static void uploadFtp(FTPClient ftp,Path local,String remote,int level)throws Exception {
        depth(level);if(Files.isSymbolicLink(local))throw new IOException("Symbolic links are not uploaded");
        if(Files.isDirectory(local)){
            if(!ftp.makeDirectory(remote))throw new IOException(ftp.getReplyString());
            try(DirectoryStream<Path> children=Files.newDirectoryStream(local)){for(Path file:children)uploadFtp(ftp,file,child(remote,file.getFileName().toString()),level+1);}
        }else try(InputStream in=Files.newInputStream(local)){if(!ftp.storeFile(remote,in))throw new IOException(ftp.getReplyString());}
    }
    private static void deleteFtp(FTPClient ftp,String remote,int level)throws Exception {
        depth(level);if(ftpDirectory(ftp,remote)){
            FTPFile[] entries=ftp.listFiles(remote);if(!FTPReply.isPositiveCompletion(ftp.getReplyCode()))throw new IOException(ftp.getReplyString());
            for(FTPFile entry:entries){String name=entry.getName();if(name.equals(".")||name.equals(".."))continue;String item=child(remote,name);if(entry.isSymbolicLink()){if(!ftp.deleteFile(item))throw new IOException(ftp.getReplyString());}else deleteFtp(ftp,item,level+1);}
            if(!ftp.removeDirectory(remote))throw new IOException(ftp.getReplyString());
        }else if(!ftp.deleteFile(remote))throw new IOException(ftp.getReplyString());
    }
    private static void downloadSftp(ChannelSftp sftp,String remote,Path local,int level)throws Exception {
        depth(level);SftpATTRS attributes=sftp.lstat(remote);if(attributes.isLink())throw new IOException("Symbolic links are not downloaded recursively");
        if(attributes.isDir()){
            Files.createDirectory(local);for(Object object:sftp.ls(remote)){ChannelSftp.LsEntry entry=(ChannelSftp.LsEntry)object;String name=entry.getFilename();if(name.equals(".")||name.equals(".."))continue;downloadSftp(sftp,child(remote,name),FileEngine.named(local,name),level+1);}
        }else try(InputStream in=sftp.get(remote);OutputStream out=Files.newOutputStream(local,StandardOpenOption.CREATE_NEW)){pump(in,out);}
    }
    private static void uploadSftp(ChannelSftp sftp,Path local,String remote,int level)throws Exception {
        depth(level);if(Files.isSymbolicLink(local))throw new IOException("Symbolic links are not uploaded");
        if(Files.isDirectory(local)){
            sftp.mkdir(remote);try(DirectoryStream<Path> children=Files.newDirectoryStream(local)){for(Path file:children)uploadSftp(sftp,file,child(remote,file.getFileName().toString()),level+1);}
        }else sftp.put(local.toString(),remote);
    }
    private static void deleteSftp(ChannelSftp sftp,String remote,int level)throws Exception {
        depth(level);SftpATTRS attributes=sftp.lstat(remote);
        if(attributes.isDir()&&!attributes.isLink()){
            for(Object object:sftp.ls(remote)){ChannelSftp.LsEntry entry=(ChannelSftp.LsEntry)object;String name=entry.getFilename();if(name.equals(".")||name.equals(".."))continue;deleteSftp(sftp,child(remote,name),level+1);}sftp.rmdir(remote);
        }else sftp.rm(remote);
    }
    private Object smb(Map<String,Object> a) throws Exception {
        SmbConfig config=SmbConfig.builder().withAuthenticators(new com.hierynomus.smbj.auth.NtlmAuthenticator.Factory()).withTimeout(30,TimeUnit.SECONDS).withSoTimeout(30000).build();
        try(SMBClient client=new SMBClient(config); var connection=client.connect(s(a,"host"),s(a,"port").isEmpty()?445:Integer.parseInt(s(a,"port")))) {
            var authentication=Boolean.TRUE.equals(a.get("anonymous"))?AuthenticationContext.anonymous():new AuthenticationContext(s(a,"username"),s(a,"password").toCharArray(),s(a,"domain"));
            var session=connection.authenticate(authentication);
            if(s(a,"share").trim().isEmpty()) {
                if(!s(a,"action").equals("list"))throw new IOException("Select a shared folder first");
                {
                    var transport=com.rapid7.client.dcerpc.transport.SMBTransportFactories.SRVSVC.getTransport(session);
                    var service=new com.rapid7.client.dcerpc.mssrvs.ServerService(transport);
                    List<Map<String,Object>> shares=new ArrayList<>();
                    for(var item:service.getShares1()) {
                        if((item.getType()&0xffff)!=0)continue;
                        Map<String,Object> entry=new HashMap<>(row(item.getNetName(),"/",true,0,0));
                        entry.put("share",item.getNetName());shares.add(entry);
                    }
                    return shares;
                }
            }
            try(DiskShare share=(DiskShare)session.connectShare(s(a,"share"))) {
                String path=s(a,"path").replace('/','\\').replaceAll("^\\\\+", "");
                switch(s(a,"action")) {
                    case "list": {
                        List<Map<String,Object>> rows=new ArrayList<>(); for(var f:share.list(path)) { String n=f.getFileName(); if(n.equals(".")||n.equals(".."))continue; rows.add(row(n,path.isEmpty()?n:path+"\\"+n,(f.getFileAttributes()&16)!=0,f.getEndOfFile(),f.getLastWriteTime().toEpochMillis())); } return rows;
                    }
                    case "get": {
                        Path target=local(a).toAbsolutePath(),staging=target.resolveSibling(".yr-download-"+UUID.randomUUID());
                        try{downloadSmb(share,path,staging,0);Files.move(staging,target);}finally{if(Files.exists(staging))FileEngine.delete(staging);}return null;
                    }
                    case "put": if(share.fileExists(path)||share.folderExists(path))throw new IOException("Remote destination already exists");uploadSmb(share,Paths.get(s(a,"local")),path,0);return null;
                    case "mkdir":share.mkdir(path);return null;
                    case "delete":deleteSmb(share,path,0);return null;
                    case "rename":{
                        String destination=s(a,"destination").replace('/','\\').replaceAll("^\\\\+", "");if(share.fileExists(destination)||share.folderExists(destination))throw new IOException("Remote destination already exists");
                        if(share.folderExists(path)){try(var directory=share.openDirectory(path,EnumSet.of(AccessMask.GENERIC_READ,AccessMask.DELETE),null,SMB2ShareAccess.ALL,SMB2CreateDisposition.FILE_OPEN,null)){directory.rename(destination,false);}}
                        else try(var file=share.openFile(path,EnumSet.of(AccessMask.GENERIC_READ,AccessMask.DELETE),null,SMB2ShareAccess.ALL,SMB2CreateDisposition.FILE_OPEN,null)){file.rename(destination,false);}return null;
                    }
                    default:throw new IOException("Unsupported SMB operation");
                }
            }
        }
    }
    private static String smbChild(String parent,String name)throws IOException{if(name.isEmpty()||name.equals(".")||name.equals("..")||name.contains("/")||name.contains("\\"))throw new IOException("Invalid SMB file name");return parent.isEmpty()?name:parent+"\\"+name;}
    private static void downloadSmb(DiskShare share,String remote,Path local,int level)throws Exception{
        depth(level);if(share.folderExists(remote)){Files.createDirectory(local);for(var child:share.list(remote)){String name=child.getFileName();if(name.equals(".")||name.equals(".."))continue;if((child.getFileAttributes()&1024)!=0)throw new IOException("SMB reparse points are not traversed");downloadSmb(share,smbChild(remote,name),FileEngine.named(local,name),level+1);}}
        else try(var file=share.openFile(remote,EnumSet.of(AccessMask.GENERIC_READ),null,SMB2ShareAccess.ALL,SMB2CreateDisposition.FILE_OPEN,null);InputStream in=file.getInputStream();OutputStream out=Files.newOutputStream(local,StandardOpenOption.CREATE_NEW)){pump(in,out);}
    }
    private static void uploadSmb(DiskShare share,Path local,String remote,int level)throws Exception{
        depth(level);if(Files.isSymbolicLink(local))throw new IOException("Symbolic links are not uploaded");if(Files.isDirectory(local)){share.mkdir(remote);try(DirectoryStream<Path> children=Files.newDirectoryStream(local)){for(Path child:children)uploadSmb(share,child,smbChild(remote,child.getFileName().toString()),level+1);}}
        else try(var file=share.openFile(remote,EnumSet.of(AccessMask.GENERIC_WRITE),null,SMB2ShareAccess.ALL,SMB2CreateDisposition.FILE_CREATE,null);OutputStream out=file.getOutputStream();InputStream in=Files.newInputStream(local)){pump(in,out);}
    }
    private static void deleteSmb(DiskShare share,String remote,int level)throws Exception{
        depth(level);if(remote.isEmpty())throw new IOException("Cannot delete SMB share root");if(share.folderExists(remote)){for(var child:share.list(remote)){String name=child.getFileName();if(name.equals(".")||name.equals(".."))continue;if((child.getFileAttributes()&1024)!=0)throw new IOException("SMB reparse points are not traversed");deleteSmb(share,smbChild(remote,name),level+1);}share.rmdir(remote,false);}else share.rm(remote);
    }
    private Object davDispatch(Map<String,Object> args)throws Exception{
        if(s(args,"action").equals("get")&&Boolean.TRUE.equals(args.get("directory"))){Path target=local(args).toAbsolutePath(),staging=target.resolveSibling(".yr-download-"+UUID.randomUUID());try{downloadDav(args,s(args,"path"),staging,0);Files.move(staging,target);}finally{if(Files.exists(staging))FileEngine.delete(staging);}return null;}
        if(s(args,"action").equals("put")&&Files.isDirectory(Paths.get(s(args,"local")))){uploadDav(args,Paths.get(s(args,"local")),s(args,"path"),0);return null;}
        return dav(args);
    }
    private void downloadDav(Map<String,Object> profile,String remote,Path local,int level)throws Exception{
        depth(level);Files.createDirectory(local);Map<String,Object> listing=new HashMap<>(profile);listing.put("action","list");listing.put("path",remote);
        @SuppressWarnings("unchecked") List<Map<String,Object>> entries=(List<Map<String,Object>>)dav(listing);
        for(Map<String,Object> item:entries){Path file=FileEngine.named(local,item.get("name").toString());String path=item.get("path").toString();if(Boolean.TRUE.equals(item.get("directory")))downloadDav(profile,path,file,level+1);else{Map<String,Object> request=new HashMap<>(profile);request.put("action","get");request.put("path",path);request.put("local",file.toString());dav(request);}}
    }
    private void uploadDav(Map<String,Object> profile,Path local,String remote,int level)throws Exception{
        depth(level);if(Files.isSymbolicLink(local))throw new IOException("Symbolic links are not uploaded");Map<String,Object> request=new HashMap<>(profile);request.put("path",remote);
        if(Files.isDirectory(local)){request.put("action","mkdir");dav(request);try(DirectoryStream<Path> entries=Files.newDirectoryStream(local)){for(Path file:entries)uploadDav(profile,file,Objects.requireNonNull(HttpUrl.parse("https://path.invalid/")).newBuilder().encodedPath(remote).addPathSegment(file.getFileName().toString()).build().encodedPath(),level+1);}}
        else{request.put("action","put");request.put("local",local.toString());dav(request);}
    }
    private Object dav(Map<String,Object> a) throws Exception {
        String base=s(a,"host");if(!base.startsWith("http://")&&!base.startsWith("https://"))base="https://"+base;
        HttpUrl origin=Objects.requireNonNull(HttpUrl.parse(base.endsWith("/")?base:base+"/"));
        String path=s(a,"path"); HttpUrl url=origin.resolve(path.isEmpty()||path.equals("/")?"./":path);
        if(url==null||!url.host().equals(origin.host())||url.port()!=origin.port()||!url.scheme().equals(origin.scheme()))throw new IOException("WebDAV path must stay on the configured server");
        String action=s(a,"action"), method=switch(action){case "list"->"PROPFIND";case "get"->"GET";case "put"->"PUT";case "mkdir"->"MKCOL";case "delete"->"DELETE";case "rename"->"MOVE";default->throw new IOException("Unsupported WebDAV operation");};
        RequestBody body=null;
        if(action.equals("list"))body=RequestBody.create("<d:propfind xmlns:d=\"DAV:\"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>",MediaType.get("application/xml"));
        if(action.equals("put"))body=RequestBody.create(Paths.get(s(a,"local")).toFile(),MediaType.get("application/octet-stream"));
        Request.Builder request=new Request.Builder().url(url).method(method,body);
        if(!s(a,"username").isEmpty())request.header("Authorization",Credentials.basic(s(a,"username"),s(a,"password"),java.nio.charset.StandardCharsets.UTF_8));
        if(action.equals("rename")){HttpUrl destination=origin.resolve(s(a,"destination"));if(destination==null||!destination.host().equals(origin.host())||destination.port()!=origin.port()||!destination.scheme().equals(origin.scheme()))throw new IOException("WebDAV destination must stay on the configured server");request.header("Destination",destination.toString());request.header("Overwrite","F");}
        if(action.equals("list"))request.header("Depth","1"); if(action.equals("put"))request.header("If-None-Match","*");
        OkHttpClient http=new OkHttpClient.Builder().connectTimeout(20,TimeUnit.SECONDS).readTimeout(60,TimeUnit.SECONDS).followRedirects(false).build();
        try(Response response=http.newCall(request.build()).execute()) {
            if(!response.isSuccessful())throw new IOException("WebDAV returned HTTP "+response.code());
            if(action.equals("get")){try(InputStream in=response.body().byteStream()){receive(a,out->pump(in,out));}return null;}
            if(!action.equals("list"))return null;
            DocumentBuilderFactory f=DocumentBuilderFactory.newInstance();f.setNamespaceAware(true);f.setFeature("http://apache.org/xml/features/disallow-doctype-decl",true);f.setExpandEntityReferences(false);
            byte[] xml=bounded(response.body().byteStream(),8*1024*1024+1);if(xml.length>8*1024*1024)throw new IOException("WebDAV listing exceeds 8 MiB");
            Document doc=f.newDocumentBuilder().parse(new ByteArrayInputStream(xml)); List<Map<String,Object>> rows=new ArrayList<>();NodeList nodes=doc.getElementsByTagNameNS("DAV:","response");
            for(int i=0;i<nodes.getLength();i++) {
                Element e=(Element)nodes.item(i);String href=text(e,"href");HttpUrl child=url.resolve(href);if(child==null||!child.host().equals(origin.host())||child.port()!=origin.port()||!child.scheme().equals(origin.scheme()))throw new IOException("WebDAV listing points outside the configured server");if(child.encodedPath().replaceAll("/$","").equals(url.encodedPath().replaceAll("/$","")))continue;
                String n=text(e,"displayname");if(n.isEmpty()){var seg=child.pathSegments();n=seg.get(seg.size()-1);if(n.isEmpty()&&seg.size()>1)n=seg.get(seg.size()-2);}
                String len=text(e,"getcontentlength"); long size=0;try{size=Long.parseLong(len);}catch(Exception ignored){}
                long modified=0;try{modified=java.time.ZonedDateTime.parse(text(e,"getlastmodified"),java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli();}catch(Exception ignored){}
                rows.add(row(n,child.encodedPath(),e.getElementsByTagNameNS("DAV:","collection").getLength()>0,size,modified));
            }
            return rows;
        } finally { http.connectionPool().evictAll(); http.dispatcher().executorService().shutdown(); }
    }
    private static String text(Element e,String name){NodeList n=e.getElementsByTagNameNS("DAV:",name);return n.getLength()==0?"":n.item(0).getTextContent();}
}
