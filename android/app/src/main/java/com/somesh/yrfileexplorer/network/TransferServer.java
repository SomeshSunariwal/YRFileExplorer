package com.somesh.yrfileexplorer.network;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Foreground-only Wi-Fi transfer. An unguessable session URL grants access to one chosen folder. */
public final class TransferServer implements AutoCloseable {
    private final Path root;
    private final String token=Base64.getUrlEncoder().withoutPadding().encodeToString(new SecureRandom().generateSeed(24));
    private final ThreadPoolExecutor pool=new ThreadPoolExecutor(2,4,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(8));
    private ServerSocket server;
    public TransferServer(Path root) throws IOException { this.root=root.toRealPath();if(!Files.isDirectory(this.root))throw new IOException("Select a folder to share"); }
    public Map<String,Object> start() throws IOException {
        server=new ServerSocket(0);Thread accept=new Thread(()->{while(!server.isClosed()){try{Socket socket=server.accept();try{pool.execute(()->serve(socket));}catch(RejectedExecutionException e){socket.close();}}catch(IOException e){break;}}},"yr-transfer");accept.setDaemon(true);accept.start();
        List<String> urls=new ArrayList<>();
        for(NetworkInterface ni:Collections.list(NetworkInterface.getNetworkInterfaces()))if(ni.isUp()&&!ni.isLoopback())for(InetAddress a:Collections.list(ni.getInetAddresses()))if(a instanceof Inet4Address && a.isSiteLocalAddress())urls.add("http://"+a.getHostAddress()+":"+server.getLocalPort()+"/"+token+"/");
        return Map.of("urls",urls,"port",server.getLocalPort(),"folder",root.toString(),"localUrl","http://127.0.0.1:"+server.getLocalPort()+"/"+token+"/");
    }
    private static String line(InputStream in) throws IOException {
        ByteArrayOutputStream b=new ByteArrayOutputStream();int c;while((c=in.read())!=-1){if(c=='\n')break;if(c!='\r')b.write(c);if(b.size()>8192)throw new IOException("Header too long");}return new String(b.toByteArray(),StandardCharsets.UTF_8);
    }
    private void serve(Socket socket) {
        try(socket){socket.setSoTimeout(30000);InputStream in=new BufferedInputStream(socket.getInputStream());OutputStream out=socket.getOutputStream();String[] request=line(in).split(" ");if(request.length<2)return;
            long length=0;int headerCount=0;String h;while(!(h=line(in)).isEmpty()){if(++headerCount>64)throw new IOException("Too many headers");if(h.toLowerCase(Locale.ROOT).startsWith("content-length:"))length=Long.parseLong(h.substring(15).trim());}
            String prefix="/"+token+"/";if(!request[1].startsWith(prefix)){send(out,403,"text/plain","Invalid session URL".getBytes());return;}
            String suffix=URLDecoder.decode(request[1].substring(prefix.length()).split("\\?",2)[0].replace("+","%2B"),"UTF-8");
            Path target=root.resolve(suffix).normalize();if(!target.startsWith(root)){send(out,403,"text/plain",new byte[0]);return;}
            Path realParent=Files.exists(target)?target.toRealPath():target.getParent().toRealPath();if(!realParent.startsWith(root)){send(out,403,"text/plain",new byte[0]);return;}
            if(request[0].equals("PUT")){
                if(length<0||length>root.toFile().getUsableSpace()){send(out,413,"text/plain","Insufficient space".getBytes());return;}
                if(Files.exists(target)){send(out,409,"text/plain","File already exists".getBytes());return;}
                Path temp=Files.createTempFile(target.getParent(),".yr-upload-",".tmp");
                try {try(OutputStream file=Files.newOutputStream(temp)){byte[] b=new byte[131072];long remaining=length;while(remaining>0){int n=in.read(b,0,(int)Math.min(b.length,remaining));if(n<0)throw new EOFException();file.write(b,0,n);remaining-=n;}}Files.move(temp,target);}
                finally{Files.deleteIfExists(temp);}send(out,201,"text/plain","Uploaded".getBytes());return;
            }
            if(!request[0].equals("GET")){send(out,405,"text/plain",new byte[0]);return;}
            if(Files.isDirectory(target)){
                StringBuilder html=new StringBuilder("<!doctype html><meta name='viewport' content='width=device-width'><title>YR File Explorer</title><style>body{font:16px system-ui;max-width:760px;margin:40px auto;padding:20px;background:#f4f7fc}a{display:block;padding:14px;background:white;color:#1689e8;margin:4px;text-decoration:none}button{padding:12px;background:#1689e8;color:white;border:0}</style><h1>YR File Explorer</h1><p>Wi-Fi file transfer · "+escape(target.getFileName().toString())+"</p>");
                if(!target.equals(root))html.append("<a href='../'>↑ Parent folder</a>");
                try(var files=Files.list(target)){for(Path p:files.sorted().collect(java.util.stream.Collectors.toList())){if(Files.isSymbolicLink(p))continue;String name=p.getFileName().toString();html.append("<a href='").append(URLEncoder.encode(name,"UTF-8").replace("+","%20")).append(Files.isDirectory(p)?"/":"").append("'>").append(escape(name)).append(Files.isDirectory(p)?" /":" · "+Files.size(p)+" bytes").append("</a>");}}
                html.append("<p><input type='file' id='file'><button onclick='upload()'>Upload here</button></p><p id='status'></p><script>async function upload(){let f=document.getElementById('file').files[0];if(!f)return;let r=await fetch(location.pathname+encodeURIComponent(f.name),{method:'PUT',body:f});document.getElementById('status').textContent=await r.text();if(r.ok)location.reload()}</script>");
                send(out,200,"text/html; charset=utf-8",html.toString().getBytes(StandardCharsets.UTF_8));
            }else if(Files.isRegularFile(target)){
                out.write(("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: "+Files.size(target)+"\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));Files.copy(target,out);
            }else send(out,404,"text/plain","Not found".getBytes());
        }catch(Exception ignored){/* Session clients can disconnect at any point. */}
    }
    private static String escape(String s){return s.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");}
    private static void send(OutputStream out,int status,String mime,byte[] body)throws IOException{out.write(("HTTP/1.1 "+status+" Result\r\nContent-Type: "+mime+"\r\nContent-Length: "+body.length+"\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII));out.write(body);}
    @Override public void close(){try{if(server!=null)server.close();}catch(IOException ignored){}pool.shutdownNow();}
}
