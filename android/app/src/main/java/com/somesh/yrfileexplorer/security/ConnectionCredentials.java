package com.somesh.yrfileexplorer.security;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Optional saved passwords; only encrypted values enter private preferences. */
public final class ConnectionCredentials {
    private static final String ALIAS="yr_connection_credentials";
    private static SecretKey key() throws Exception {
        KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
        if(store.containsAlias(ALIAS))return (SecretKey)store.getKey(ALIAS,null);
        KeyGenerator generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).setKeySize(256).build());return generator.generateKey();
    }
    public static String read(Context context,String id) throws Exception {
        String value=context.getSharedPreferences("connection_credentials",Context.MODE_PRIVATE).getString(id,"");if(value.isEmpty())return "";
        String[] parts=value.split(":",2);if(parts.length!=2)return "";
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)));
        cipher.updateAAD(id.getBytes(StandardCharsets.UTF_8));return new String(cipher.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),StandardCharsets.UTF_8);
    }
    public static void save(Context context,String id,String password) throws Exception {
        var editor=context.getSharedPreferences("connection_credentials",Context.MODE_PRIVATE).edit();
        if(password.isEmpty()){editor.remove(id).commit();return;}
        Cipher cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key());cipher.updateAAD(id.getBytes(StandardCharsets.UTF_8));
        String value=Base64.encodeToString(cipher.getIV(),Base64.NO_WRAP)+":"+Base64.encodeToString(cipher.doFinal(password.getBytes(StandardCharsets.UTF_8)),Base64.NO_WRAP);editor.putString(id,value).commit();
    }
}
