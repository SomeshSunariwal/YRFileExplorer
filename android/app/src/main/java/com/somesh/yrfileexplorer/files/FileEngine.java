package com.somesh.yrfileexplorer.files;

import com.somesh.yrfileexplorer.storage.FolderAnalyzer;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.io.OutputStream;
import java.nio.file.DirectoryStream;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.FileVisitOption;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.security.SecureRandom;
import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import net.lingala.zip4j.ZipFile;
import net.lingala.zip4j.model.ZipParameters;
import net.lingala.zip4j.model.enums.AesKeyStrength;
import net.lingala.zip4j.model.enums.EncryptionMethod;

public final class FileEngine {
    private FileEngine() {}
    public static List<Map<String, Object>> list(String path, boolean hidden) throws IOException {
        List<Map<String, Object>> rows = new ArrayList<>();
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(Paths.get(path))) {
            for (Path p : stream) {
                if (!hidden && p.getFileName().toString().startsWith(".")) continue;
                try {
                    var a = Files.readAttributes(p, BasicFileAttributes.class, LinkOption.NOFOLLOW_LINKS);
                    var row = FolderAnalyzer.entry(p, a);
                    row.put("symlink", a.isSymbolicLink());
                    if (a.isDirectory()) {
                        try (DirectoryStream<Path> kids = Files.newDirectoryStream(p)) {
                            int count = 0; for (Path ignored : kids) count++;
                            row.put("items", count);
                        } catch (IOException | SecurityException ex) { row.put("items", -1); }
                    }
                    rows.add(row);
                } catch (IOException | SecurityException ignored) { /* vanished while listing */ }
            }
        }
        return rows;
    }
    public static Path named(Path parent, String name) throws IOException {
        if (name == null || name.trim().isEmpty() || name.equals(".") || name.equals("..") || name.contains("/") || name.contains("\\") || name.indexOf('\0') >= 0) throw new IOException("Invalid file name");
        return parent.resolve(name);
    }
    public static void copy(Path source, Path target) throws IOException {
        copy(source, target, null);
    }
    public static void copy(Path source, Path target, java.util.function.Consumer<Path> progress) throws IOException {
        Path src = source.toRealPath(), dst = target.toAbsolutePath().normalize();
        if (dst.startsWith(src) || dst.equals(src)) throw new IOException("Cannot copy a folder into itself");
        if (Files.exists(dst, LinkOption.NOFOLLOW_LINKS)) throw new FileAlreadyExistsException(dst.toString());
        Path staging=dst.resolveSibling(".yr-copy-"+UUID.randomUUID());
        try { Files.walkFileTree(src, new SimpleFileVisitor<Path>() {
            @Override public FileVisitResult preVisitDirectory(Path p, BasicFileAttributes a) throws IOException {
                Files.createDirectory(staging.resolve(src.relativize(p))); return FileVisitResult.CONTINUE;
            }
            @Override public FileVisitResult visitFile(Path p, BasicFileAttributes a) throws IOException {
                if (a.isSymbolicLink()) throw new IOException("Symbolic links are not copied");
                Files.copy(p, staging.resolve(src.relativize(p)), StandardCopyOption.COPY_ATTRIBUTES); if(progress!=null)progress.accept(p); return FileVisitResult.CONTINUE;
            }
        }); Files.move(staging,dst); }
        finally { if(Files.exists(staging,LinkOption.NOFOLLOW_LINKS))delete(staging); }
    }
    public static void delete(Path p) throws IOException {
        delete(p, null);
    }
    public static void delete(Path p, java.util.function.Consumer<Path> progress) throws IOException {
        Files.walkFileTree(p, new SimpleFileVisitor<Path>() {
            @Override public FileVisitResult visitFile(Path f, BasicFileAttributes a) throws IOException { Files.delete(f); if(progress!=null)progress.accept(f); return FileVisitResult.CONTINUE; }
            @Override public FileVisitResult postVisitDirectory(Path d, IOException ex) throws IOException { if (ex != null) throw ex; Files.delete(d); return FileVisitResult.CONTINUE; }
        });
    }
    public static void zip(List<String> paths, String destination, String password) throws IOException {
        if (Files.exists(Paths.get(destination))) throw new FileAlreadyExistsException(destination);
        Path dest=Paths.get(destination).toAbsolutePath().normalize();
        for(String path:paths)if(Files.isDirectory(Paths.get(path))&&dest.startsWith(Paths.get(path).toRealPath()))throw new IOException("Create the ZIP outside the folder being compressed");
        ZipParameters parameters = new ZipParameters();
        if (!password.isEmpty()) {
            parameters.setEncryptFiles(true); parameters.setEncryptionMethod(EncryptionMethod.AES); parameters.setAesKeyStrength(AesKeyStrength.KEY_STRENGTH_256);
        }
        try (ZipFile zip = password.isEmpty() ? new ZipFile(destination) : new ZipFile(destination, password.toCharArray())) {
            for (String path : paths) { File f = new File(path); if (f.isDirectory()) zip.addFolder(f, parameters); else zip.addFile(f, parameters); }
        } catch(IOException ex){Files.deleteIfExists(dest);throw ex;}
    }
    public static void unzip(String path, String destination, String password) throws IOException {
        Path root = Paths.get(destination).toAbsolutePath().normalize();
        Files.createDirectory(root); // extract into a new folder, never silently replace data
        try (ZipFile zip = password.isEmpty() ? new ZipFile(path) : new ZipFile(path, password.toCharArray())) {
            long total = 0;
            for (var header : zip.getFileHeaders()) {
                Path output = root.resolve(header.getFileName().replace('\\', '/')).normalize();
                if (!output.startsWith(root)) throw new IOException("Archive contains an unsafe path");
                total = Math.addExact(total, header.getUncompressedSize());
                if (total > root.toFile().getUsableSpace()) throw new IOException("Not enough storage to extract archive");
            }
            zip.extractAll(root.toString());
        } catch(Exception ex){delete(root);if(ex instanceof IOException io)throw io;throw new IOException(ex.getMessage(),ex);}
    }
    /** YRV1: 4 byte magic, 16 byte salt, 12 byte IV, authenticated AES-256-GCM. */
    public static String crypt(String source, String password, boolean decrypt) throws Exception {
        return crypt(source,password,decrypt,"");
    }
    public static String crypt(String source, String password, boolean decrypt,String destinationName) throws Exception {
        if (password.length() < 8) throw new IOException("Use a password with at least 8 characters");
        Path input = Paths.get(source);
        if (!Files.isRegularFile(input)) throw new IOException("Encrypt files individually, or ZIP a folder first");
        Path output = destinationName.isEmpty() ? Paths.get(decrypt ? (source.endsWith(".yrvault") ? source.substring(0, source.length()-8) : source + ".decrypted") : source + ".yrvault") : named(input.getParent(),destinationName);
        if (Files.exists(output)) throw new FileAlreadyExistsException(output.toString());
        Path temp = Files.createTempFile(input.getParent(), ".yr-crypt-", ".tmp");
        byte[] salt = new byte[16], iv = new byte[12];
        try (DataInputStream in = new DataInputStream(Files.newInputStream(input)); OutputStream out = Files.newOutputStream(temp)) {
            if (decrypt) {
                if (in.readInt() != 0x59525631) throw new IOException("Not a YR encrypted file");
                in.readFully(salt); in.readFully(iv);
            } else { new SecureRandom().nextBytes(salt); new SecureRandom().nextBytes(iv); }
            var spec = new PBEKeySpec(password.toCharArray(), salt, 210000, 256);
            byte[] key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded(); spec.clearPassword();
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(decrypt ? Cipher.DECRYPT_MODE : Cipher.ENCRYPT_MODE, new SecretKeySpec(key, "AES"), new GCMParameterSpec(128, iv)); Arrays.fill(key, (byte)0);
            if (!decrypt) { DataOutputStream header = new DataOutputStream(out); header.writeInt(0x59525631); header.write(salt); header.write(iv); }
            byte[] buffer = new byte[128*1024]; int n;
            while ((n = in.read(buffer)) != -1) { byte[] chunk = cipher.update(buffer, 0, n); if (chunk != null) out.write(chunk); }
            out.write(cipher.doFinal());
        } catch (Exception ex) { Files.deleteIfExists(temp); throw ex; }
        Files.move(temp, output); return output.toString();
    }
    public static List<Map<String,Object>> search(String root,String query,String category,int limit)throws IOException {
        return search(root,query,category,limit,true,true,new java.util.concurrent.atomic.AtomicBoolean());
    }
    public static List<Map<String,Object>> search(String root,String query,String category,int limit,boolean recursive,boolean hidden,java.util.concurrent.atomic.AtomicBoolean cancel)throws IOException {
        List<Map<String,Object>> found=new ArrayList<>();String term=query.toLowerCase(Locale.ROOT);Path start=Paths.get(root);
        Files.walkFileTree(start,EnumSet.noneOf(FileVisitOption.class),recursive?Integer.MAX_VALUE:1,new SimpleFileVisitor<Path>(){
            private FileVisitResult add(Path p,BasicFileAttributes attrs)throws IOException {
                if(cancel.get()||Thread.currentThread().isInterrupted())throw new InterruptedIOException("Search cancelled");
                if(p.equals(start))return FileVisitResult.CONTINUE;
                String name=p.getFileName().toString();if(name.startsWith(".yr-")||(!hidden&&name.startsWith(".")))return FileVisitResult.SKIP_SUBTREE;
                boolean type=category.isEmpty()||category.equals("Folders")&&attrs.isDirectory()||!attrs.isDirectory()&&FolderAnalyzer.category(p.toString()).equals(category);
                if(name.toLowerCase(Locale.ROOT).contains(term)&&type)found.add(FolderAnalyzer.entry(p,attrs));
                return found.size()>=limit?FileVisitResult.TERMINATE:FileVisitResult.CONTINUE;
            }
            @Override public FileVisitResult preVisitDirectory(Path p,BasicFileAttributes a)throws IOException{return add(p,a);}
            @Override public FileVisitResult visitFile(Path p,BasicFileAttributes a)throws IOException{return a.isRegularFile()||a.isDirectory()?add(p,a):FileVisitResult.CONTINUE;}
            @Override public FileVisitResult visitFileFailed(Path p,IOException e){return FileVisitResult.CONTINUE;}
        });return found;
    }
}
