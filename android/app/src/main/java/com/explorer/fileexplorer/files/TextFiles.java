package com.explorer.fileexplorer.files;

import java.io.*;
import java.nio.*;
import java.nio.charset.*;
import java.nio.file.*;
import java.util.*;

public final class TextFiles {
    public static Map<String,Object> read(String path,String requested) throws Exception {
        Path file=Paths.get(path);if(Files.size(file)>2*1024*1024)throw new IOException("Text editor limit is 2 MiB");
        byte[] bytes=Files.readAllBytes(file);String encoding=requested.isEmpty()?"UTF-8":requested;int offset=0;boolean bom=false;
        if(requested.isEmpty()) {
            if(bytes.length>=3 && (bytes[0]&255)==239 && (bytes[1]&255)==187 && (bytes[2]&255)==191){offset=3;bom=true;}
            else if(bytes.length>=2 && (bytes[0]&255)==255 && (bytes[1]&255)==254){encoding="UTF-16LE";offset=2;bom=true;}
            else if(bytes.length>=2 && (bytes[0]&255)==254 && (bytes[1]&255)==255){encoding="UTF-16BE";offset=2;bom=true;}
        }
        String text=Charset.forName(encoding).newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes,offset,bytes.length-offset)).toString();
        String ending=text.contains("\r\n")?"CRLF":text.contains("\r")?"CR":"LF";
        return Map.of("text",text.replace("\r\n","\n").replace('\r','\n'),"encoding",encoding,"lineEnding",ending,"bom",bom);
    }
    public static void write(String path,String text,String encoding,String ending,boolean bom,boolean create) throws Exception {
        String normalized=text.replace("\r\n","\n").replace('\r','\n');
        if(ending.equals("CRLF"))normalized=normalized.replace("\n","\r\n");else if(ending.equals("CR"))normalized=normalized.replace('\n','\r');
        byte[] bytes=normalized.getBytes(Charset.forName(encoding.isEmpty()?"UTF-8":encoding));
        if(bytes.length>2*1024*1024)throw new IOException("Text editor limit is 2 MiB");
        Path file=Paths.get(path);if(create && Files.exists(file))throw new FileAlreadyExistsException(path);
        Path temp=Files.createTempFile(file.getParent(),".yr-edit-",".tmp");
        try(OutputStream out=Files.newOutputStream(temp)) {
            if(bom)switch(encoding){case "UTF-8":out.write(new byte[]{(byte)239,(byte)187,(byte)191});break;case "UTF-16LE":out.write(new byte[]{(byte)255,(byte)254});break;case "UTF-16BE":out.write(new byte[]{(byte)254,(byte)255});break;}
            out.write(bytes);
        }catch(Exception error){Files.deleteIfExists(temp);throw error;}
        try { if(create)Files.move(temp,file);else Files.move(temp,file,StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE); }
        finally {Files.deleteIfExists(temp);}
    }
}
