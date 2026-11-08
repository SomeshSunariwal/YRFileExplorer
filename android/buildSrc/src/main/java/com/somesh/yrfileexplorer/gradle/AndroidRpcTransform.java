package com.somesh.yrfileexplorer.gradle;

import org.gradle.api.GradleException;
import org.gradle.api.artifacts.transform.InputArtifact;
import org.gradle.api.artifacts.transform.TransformAction;
import org.gradle.api.artifacts.transform.TransformOutputs;
import org.gradle.api.artifacts.transform.TransformParameters;
import org.gradle.api.file.FileSystemLocation;
import org.gradle.api.provider.Provider;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/** Adapts DCERPC's JVM-only exception reference before Android compilation/R8. */
public abstract class AndroidRpcTransform implements TransformAction<TransformParameters.None> {
    private static final String JVM_EXCEPTION = "java/rmi/UnmarshalException";
    private static final String ANDROID_EXCEPTION =
            "com/somesh/yrfileexplorer/network/RpcUnmarshalException";

    @InputArtifact
    public abstract Provider<FileSystemLocation> getInputArtifact();

    @Override
    public void transform(TransformOutputs outputs) {
        File input = getInputArtifact().get().getAsFile();
        if (!input.getName().equals("dcerpc-0.12.13.jar")) {
            outputs.file(input);
            return;
        }
        File output = outputs.file("android-" + input.getName());
        try (ZipInputStream source = new ZipInputStream(new FileInputStream(input));
             ZipOutputStream target = new ZipOutputStream(new FileOutputStream(output))) {
            ZipEntry entry;
            while ((entry = source.getNextEntry()) != null) {
                String name = entry.getName();
                if (name.matches("(?i)META-INF/[^/]+\\.(SF|RSA|DSA|EC)")) continue;
                byte[] bytes = source.readAllBytes();
                ZipEntry copy = new ZipEntry(name);
                copy.setTime(0);
                target.putNextEntry(copy);
                target.write(name.endsWith(".class") ? adaptClass(bytes) : bytes);
                target.closeEntry();
            }
        } catch (IOException e) {
            throw new GradleException("Cannot adapt DCERPC for Android", e);
        }
    }

    /** Rewrite constant-pool UTF8 entries; code, resources and other types stay intact. */
    private static byte[] adaptClass(byte[] bytes) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(bytes.length);
        try (DataInputStream in = new DataInputStream(new ByteArrayInputStream(bytes));
             DataOutputStream out = new DataOutputStream(buffer)) {
            int magic = in.readInt();
            if (magic != 0xCAFEBABE) throw new IOException("Invalid class file");
            out.writeInt(magic);
            out.writeShort(in.readUnsignedShort());
            out.writeShort(in.readUnsignedShort());
            int count = in.readUnsignedShort();
            out.writeShort(count);
            for (int i = 1; i < count; i++) {
                int tag = in.readUnsignedByte();
                out.writeByte(tag);
                if (tag == 1) {
                    out.writeUTF(in.readUTF().replace(JVM_EXCEPTION, ANDROID_EXCEPTION));
                    continue;
                }
                int size = switch (tag) {
                    case 3, 4, 9, 10, 11, 12, 17, 18 -> 4;
                    case 5, 6 -> 8;
                    case 7, 8, 16, 19, 20 -> 2;
                    case 15 -> 3;
                    default -> throw new IOException("Unknown constant-pool tag " + tag);
                };
                byte[] value = in.readNBytes(size);
                if (value.length != size) throw new EOFException("Truncated constant pool");
                out.write(value);
                if (tag == 5 || tag == 6) i++;
            }
            in.transferTo(out);
        }
        return buffer.toByteArray();
    }
}
