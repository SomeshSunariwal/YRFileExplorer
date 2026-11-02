package com.somesh.yrfileexplorer.archives;

import com.somesh.yrfileexplorer.files.FileEngine;
import com.somesh.yrfileexplorer.storage.FolderAnalyzer;

import android.content.Context;
import net.lingala.zip4j.ZipFile;
import net.lingala.zip4j.model.FileHeader;
import java.io.*;
import java.nio.charset.Charset;
import java.nio.file.*;
import java.util.*;

public final class ArchiveEngine {
    private static ZipFile zip(String path,String password,String charset) {
        ZipFile zip=password.isEmpty()?new ZipFile(path):new ZipFile(path,password.toCharArray());
        if(!charset.isEmpty())zip.setCharset(Charset.forName(charset));return zip;
    }
    private static String clean(String name) throws IOException {
        String value=name.replace('\\','/');
        if(value.startsWith("/") || value.matches("^[a-zA-Z]:.*") || Arrays.asList(value.split("/")).contains(".."))throw new IOException("Archive contains an unsafe path");
        return value;
    }
    public static List<Map<String,Object>> list(String path,String prefix,String password,String charset) throws Exception {
        Map<String,Map<String,Object>> rows=new LinkedHashMap<>();
        try(ZipFile zip=zip(path,password,charset)) {
            for(FileHeader header:zip.getFileHeaders()) {
                String full=clean(header.getFileName());if(!full.startsWith(prefix) || full.equals(prefix))continue;
                String relative=full.substring(prefix.length());int slash=relative.indexOf('/');boolean dir=slash>=0 || header.isDirectory();
                String name=slash>=0?relative.substring(0,slash):relative;if(name.isEmpty())continue;
                String key=prefix+name+(dir?"/":"");
                Map<String,Object> row=rows.computeIfAbsent(key,ignored->{Map<String,Object> value=new HashMap<>();value.put("name",name);value.put("path",key);value.put("directory",dir);value.put("size",0L);value.put("category",dir?"Folders":FolderAnalyzer.category(name));value.put("modified",header.getLastModifiedTimeEpoch());value.put("encrypted",false);return value;});
                row.put("size",((Number)row.get("size")).longValue()+header.getUncompressedSize());
                row.put("encrypted",Boolean.TRUE.equals(row.get("encrypted")) || header.isEncrypted());
                if(rows.size()>100000)throw new IOException("Archive has too many entries to display");
            }
        }return new ArrayList<>(rows.values());
    }
    public static void extract(String path,String destination,List<String> entries,String password,String charset) throws Exception {
        Path root=Paths.get(destination).toAbsolutePath().normalize();Files.createDirectory(root);
        try(ZipFile zip=zip(path,password,charset)) {
            long remaining=root.toFile().getUsableSpace();
            for(FileHeader header:zip.getFileHeaders()) {
                String name=clean(header.getFileName());
                if(!entries.isEmpty() && entries.stream().noneMatch(e->name.equals(e) || (e.endsWith("/") && name.startsWith(e))))continue;
                Path output=root.resolve(name).normalize();if(!output.startsWith(root))throw new IOException("Unsafe archive path");
                if(header.isDirectory()){Files.createDirectories(output);continue;}
                if(header.getUncompressedSize()>remaining)throw new IOException("Not enough storage to extract archive");
                Files.createDirectories(output.getParent());
                try(InputStream in=zip.getInputStream(header);OutputStream out=Files.newOutputStream(output,StandardOpenOption.CREATE_NEW)) {
                    byte[] buffer=new byte[65536];int n;
                    while((n=in.read(buffer))!=-1){remaining-=n;if(remaining<0)throw new IOException("Not enough storage to extract archive");out.write(buffer,0,n);}
                }
                if(header.getLastModifiedTimeEpoch()>0)output.toFile().setLastModified(header.getLastModifiedTimeEpoch());
            }
        }catch(Exception error){FileEngine.delete(root);throw error;}
    }
    public static String open(Context context,String path,String entry,String password,String charset) throws Exception {
        String name=clean(entry);Path exports=new File(context.getFilesDir(),"exports").toPath();Files.createDirectories(exports);
        Path root=exports.resolve(UUID.randomUUID().toString());extract(path,root.toString(),List.of(name),password,charset);
        Path file=root.resolve(name).normalize();if(!Files.exists(file))throw new IOException("Archive entry no longer exists");return file.toString();
    }
}
