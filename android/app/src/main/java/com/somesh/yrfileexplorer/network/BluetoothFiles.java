package com.somesh.yrfileexplorer.network;

import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;

import android.bluetooth.*;
import android.content.Context;
import android.util.Xml;
import org.xmlpull.v1.XmlPullParser;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.concurrent.*;

/** Independent OBEX File Transfer client. Peer support and Android pairing are required. */
public final class BluetoothFiles implements AutoCloseable {
    private static final UUID SERVICE=UUID.fromString("00001106-0000-1000-8000-00805f9b34fb");
    private static final UUID TARGET=UUID.fromString("f9ec7bc4-953c-11d2-984e-525400dc9e09");
    private BluetoothSocket socket;private DataInputStream input;private OutputStream output;private byte[] connection=new byte[0];private int packetSize=8192;
    private final ScheduledExecutorService timeout=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"Bluetooth transfer timeout");t.setDaemon(true);return t;});
    private record Packet(int code,byte[] data){}
    private static class AuthenticationRequired extends IOException {}
    private static String value(Map<String,Object> args,String key){return Objects.toString(args.get(key),"");}
    public static Object execute(Context context,Map<String,Object> args)throws Exception {
        try(BluetoothFiles client=new BluetoothFiles(context,value(args,"host"),value(args,"username"),value(args,"password"))){
            String path=normalize(value(args,"path"));
            switch(value(args,"action")){
                case "list":return client.list(path);
                case "get":{Path target=Paths.get(value(args,"local")).toAbsolutePath();if(Files.exists(target))throw new FileAlreadyExistsException(target.toString());Path temporary=target.resolveSibling(".yr-bluetooth-"+UUID.randomUUID());try{client.download(path,temporary,0);Files.move(temporary,target);}finally{if(Files.exists(temporary))FileEngine.delete(temporary);}return null;}
                case "put":client.upload(Paths.get(value(args,"local")),path,0);return null;
                case "mkdir":client.go(parent(path));success(client.exchange(0x85,concat(new byte[]{0,0},client.connection,name(base(path)))),false);return null;
                case "delete":client.delete(path,0);return null;
                case "rename":{String destination=normalize(value(args,"destination"));if(!parent(path).equals(parent(destination)))throw new IOException("Rename within the current folder");client.go(parent(path));if(client.list(parent(path)).stream().anyMatch(e->e.get("name").equals(base(destination))))throw new IOException("Destination already exists");success(client.exchange(0x86,concat(client.connection,new byte[]{(byte)0x94,1},name(base(path)),header(0x15,(base(destination)+"\0").getBytes(StandardCharsets.UTF_16BE)))),false);return null;}
                default:throw new IOException("Unsupported Bluetooth file operation");
            }
        }catch(AuthenticationRequired auth){return Map.of("needsPassword",true);}
    }
    private BluetoothFiles(Context context,String address,String username,String password)throws Exception {
        try{
            if(!NetworkEnvironment.bluetoothAllowed(context))throw new IOException("Allow Nearby devices access first");BluetoothAdapter adapter=NetworkEnvironment.adapter(context);if(adapter==null||!adapter.isEnabled())throw new IOException("Turn on Bluetooth first");
            if(context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN)==android.content.pm.PackageManager.PERMISSION_GRANTED)adapter.cancelDiscovery();
            socket=adapter.getRemoteDevice(address).createRfcommSocketToServiceRecord(SERVICE);
            ScheduledFuture<?> timer=timeout.schedule(()->{try{socket.close();}catch(Exception ignored){}},20,TimeUnit.SECONDS);try{socket.connect();}finally{timer.cancel(false);}
            input=new DataInputStream(socket.getInputStream());output=socket.getOutputStream();
            byte[] target=ByteBuffer.allocate(16).putLong(TARGET.getMostSignificantBits()).putLong(TARGET.getLeastSignificantBits()).array();byte[] connect=concat(new byte[]{0x10,0,0x20,0},header(0x46,target));Packet reply=exchange(0x80,connect);
            if(reply.code==0xc1){byte[] challenge=find(reply.data,4,0x4d);if(password.isEmpty())throw new AuthenticationRequired();if(challenge==null)throw new IOException("Bluetooth authentication failed");byte[] nonce=null;for(int i=0;i+2<=challenge.length;){int tag=challenge[i++]&255,len=challenge[i++]&255;if(i+len>challenge.length)throw new IOException("Invalid authentication challenge");if(tag==0)nonce=Arrays.copyOfRange(challenge,i,i+len);i+=len;}if(nonce==null)throw new IOException("No Bluetooth authentication nonce");MessageDigest digest=MessageDigest.getInstance("MD5");digest.update(nonce);digest.update((byte)':');digest.update(password.getBytes(StandardCharsets.ISO_8859_1));byte[] response=concat(new byte[]{0,16},digest.digest());if(!username.isEmpty()){byte[] user=username.getBytes(StandardCharsets.ISO_8859_1);if(user.length>20)throw new IOException("Bluetooth user ID exceeds 20 bytes");response=concat(response,new byte[]{1,(byte)user.length},user);}reply=exchange(0x80,concat(connect,header(0x4e,response)));}
            success(reply,false);if(reply.data.length<4)throw new IOException("Invalid Bluetooth connection response");packetSize=Math.min(8192,((reply.data[2]&255)<<8)|(reply.data[3]&255));if(packetSize<255)throw new IOException("Invalid Bluetooth packet size");byte[] id=find(reply.data,4,0xcb);if(id!=null)connection=concat(new byte[]{(byte)0xcb},id);
        }catch(Exception error){close();throw error;}
    }
    private Packet exchange(int opcode,byte[] data)throws IOException {
        if(data.length+3>65535)throw new IOException("Bluetooth packet too large");ScheduledFuture<?> timer=timeout.schedule(()->{try{socket.close();}catch(Exception ignored){}},30,TimeUnit.SECONDS);
        try{output.write(opcode);output.write((data.length+3)>>8);output.write(data.length+3);output.write(data);output.flush();int code=input.readUnsignedByte(),length=input.readUnsignedShort();if(length<3)throw new IOException("Invalid Bluetooth response");byte[] body=new byte[length-3];input.readFully(body);return new Packet(code,body);}finally{timer.cancel(false);}
    }
    private static void success(Packet packet,boolean continuation)throws IOException {if(packet.code!=0xa0&&!(continuation&&packet.code==0x90))throw new IOException(packet.code==0xd1?"The Bluetooth device does not support this file operation":packet.code==0xc1?"Bluetooth authentication failed":"Bluetooth device returned 0x"+Integer.toHexString(packet.code));}
    private static byte[] concat(byte[]... arrays)throws IOException {ByteArrayOutputStream bytes=new ByteArrayOutputStream();for(byte[] array:arrays)bytes.write(array);return bytes.toByteArray();}
    private static byte[] header(int id,byte[] bytes)throws IOException {int length=bytes.length+3;if(length>65535)throw new IOException("Bluetooth header too large");return concat(new byte[]{(byte)id,(byte)(length>>8),(byte)length},bytes);}
    private static byte[] name(String text)throws IOException{return header(1,(text+"\0").getBytes(StandardCharsets.UTF_16BE));}
    private static byte[] find(byte[] data,int offset,int wanted)throws IOException {
        for(int i=offset;i<data.length;){int id=data[i]&255,type=id>>6,length=type<2?(i+2<data.length?((data[i+1]&255)<<8)|(data[i+2]&255):0):type==2?2:5;if(length<(type<2?3:2)||i+length>data.length)throw new IOException("Invalid Bluetooth header");if(id==wanted)return Arrays.copyOfRange(data,i+(type<2?3:1),i+length);i+=length;}return null;
    }
    private static String normalize(String path)throws IOException {String value=path.replace('\\','/');for(String part:value.split("/"))if(part.equals(".."))throw new IOException("Invalid Bluetooth path");return "/"+String.join("/",Arrays.stream(value.split("/")).filter(p->!p.isEmpty()&&!p.equals(".")).collect(java.util.stream.Collectors.toList()));}
    private static String base(String path){int slash=path.lastIndexOf('/');return path.substring(slash+1);}
    private static String parent(String path){int slash=path.lastIndexOf('/');return slash<=0?"/":path.substring(0,slash);}
    private void go(String path)throws IOException {success(exchange(0x85,concat(new byte[]{2,0},connection,name(""))),false);for(String part:normalize(path).substring(1).split("/"))if(!part.isEmpty())success(exchange(0x85,concat(new byte[]{2,0},connection,name(part))),false);}
    private void get(byte[] headers,OutputStream destination)throws IOException {
        Packet packet=exchange(0x83,concat(connection,headers));
        while(true){success(packet,true);byte[] body=find(packet.data,0,0x48),end=find(packet.data,0,0x49);if(body!=null)destination.write(body);if(end!=null)destination.write(end);if(packet.code==0xa0)break;packet=exchange(0x83,connection);}
    }
    private List<Map<String,Object>> list(String path)throws Exception {
        go(path);ByteArrayOutputStream bytes=new ByteArrayOutputStream();get(header(0x42,"x-obex/folder-listing\0".getBytes(StandardCharsets.US_ASCII)),new OutputStream(){public void write(int b)throws IOException{if(bytes.size()>=8*1024*1024)throw new IOException("Bluetooth directory listing is too large");bytes.write(b);}public void write(byte[] b,int off,int len)throws IOException{if(bytes.size()+len>8*1024*1024)throw new IOException("Bluetooth directory listing is too large");bytes.write(b,off,len);}});
        XmlPullParser parser=Xml.newPullParser();parser.setInput(new StringReader(new String(bytes.toByteArray(),StandardCharsets.UTF_8)));List<Map<String,Object>> rows=new ArrayList<>();
        while(parser.next()!=XmlPullParser.END_DOCUMENT){if(parser.getEventType()!=XmlPullParser.START_TAG||!Set.of("file","folder").contains(parser.getName()))continue;String name=parser.getAttributeValue(null,"name");if(name==null||name.isEmpty()||name.equals(".")||name.equals("..")||name.contains("/")||name.contains("\\"))continue;long size=0;try{size=Long.parseLong(Objects.toString(parser.getAttributeValue(null,"size"),"0"));}catch(NumberFormatException ignored){}boolean folder=parser.getName().equals("folder");rows.add(Map.of("name",name,"path",normalize(path+"/"+name),"directory",folder,"size",size,"modified",0L,"category",folder?"Folders":FolderAnalyzer.category(name)));}return rows;
    }
    private void download(String path,Path local,int level)throws Exception {if(level>128)throw new IOException("Bluetooth folder nesting exceeds 128 levels");Map<String,Object> item=list(parent(path)).stream().filter(e->e.get("name").equals(base(path))).findFirst().orElseThrow(()->new IOException("Bluetooth file no longer exists"));if(Boolean.TRUE.equals(item.get("directory"))){Files.createDirectory(local);for(Map<String,Object> child:list(path))download(child.get("path").toString(),FileEngine.named(local,child.get("name").toString()),level+1);}else{go(parent(path));try(OutputStream out=Files.newOutputStream(local,StandardOpenOption.CREATE_NEW)){get(name(base(path)),out);}}}
    private void upload(Path local,String path,int level)throws Exception {
        if(level>128)throw new IOException("Bluetooth folder nesting exceeds 128 levels");if(Files.isSymbolicLink(local))throw new IOException("Symbolic links are not uploaded");if(list(parent(path)).stream().anyMatch(e->e.get("name").equals(base(path))))throw new IOException("Remote destination already exists");go(parent(path));
        if(Files.isDirectory(local)){success(exchange(0x85,concat(new byte[]{0,0},connection,name(base(path)))),false);try(DirectoryStream<Path> files=Files.newDirectoryStream(local)){for(Path file:files)upload(file,normalize(path+"/"+file.getFileName()),level+1);}return;}
        long remaining=Files.size(local);if(remaining>0xffffffffL)throw new IOException("Bluetooth file exceeds OBEX size limit");byte[] meta=concat(name(base(path)),ByteBuffer.allocate(5).put((byte)0xc3).putInt((int)remaining).array());int chunk=packetSize-connection.length-meta.length-6;if(chunk<1)throw new IOException("File name is too long for the Bluetooth device");
        try(InputStream in=Files.newInputStream(local)){boolean first=true;do{int count=(int)Math.min(chunk,remaining);byte[] data=new byte[count];int read=0;while(read<count){int n=in.read(data,read,count-read);if(n<0)throw new IOException("Local file changed during upload");read+=n;}remaining-=count;boolean last=remaining==0;Packet response=exchange(last?0x82:0x02,concat(connection,first?meta:new byte[0],header(last?0x49:0x48,data)));success(response,!last);first=false;}while(remaining>0);}
    }
    private void delete(String path,int level)throws Exception {if(path.equals("/"))throw new IOException("Cannot delete Bluetooth root");if(level>128)throw new IOException("Bluetooth folder nesting exceeds 128 levels");Map<String,Object> item=list(parent(path)).stream().filter(e->e.get("name").equals(base(path))).findFirst().orElseThrow(()->new IOException("Bluetooth file no longer exists"));if(Boolean.TRUE.equals(item.get("directory")))for(Map<String,Object> child:list(path))delete(child.get("path").toString(),level+1);go(parent(path));success(exchange(0x82,concat(connection,name(base(path)))),false);}
    @Override public void close(){timeout.shutdownNow();if(socket!=null)try{socket.close();}catch(IOException ignored){}}
}
