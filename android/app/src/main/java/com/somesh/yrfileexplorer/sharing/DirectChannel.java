package com.somesh.yrfileexplorer.sharing;

import org.bouncycastle.crypto.agreement.jpake.JPAKEParticipant;
import org.bouncycastle.crypto.agreement.jpake.JPAKEPrimeOrderGroups;
import org.bouncycastle.crypto.agreement.jpake.JPAKERound1Payload;
import org.bouncycastle.crypto.agreement.jpake.JPAKERound2Payload;
import org.bouncycastle.crypto.agreement.jpake.JPAKERound3Payload;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.Closeable;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.math.BigInteger;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Password-authenticated session. The six-digit secret is never sent over the socket. */
final class DirectChannel implements Closeable {
    final Socket socket;
    final String id = UUID.randomUUID().toString();
    final Object batchLock = new Object();
    private final DataInputStream in;
    private final DataOutputStream out;
    private final byte[] sendKey, receiveKey;
    private long sent, received;
    private static final int MAX_FRAME = 196608;

    DirectChannel(Socket socket, String code, boolean host) throws Exception {
        this.socket = socket;
        socket.setSoTimeout(30000);
        socket.setTcpNoDelay(true);
        in = new DataInputStream(new BufferedInputStream(socket.getInputStream()));
        out = new DataOutputStream(new BufferedOutputStream(socket.getOutputStream()));
        JPAKEParticipant p = new JPAKEParticipant(id, code.toCharArray(), JPAKEPrimeOrderGroups.NIST_3072);
        JPAKERound1Payload r1 = p.createRound1PayloadToSend();
        writePlain(new JSONObject().put("id",id).put("x",r1.getGx1().toString()).put("y",r1.getGx2().toString())
            .put("px",numbers(r1.getKnowledgeProofForX1())).put("py",numbers(r1.getKnowledgeProofForX2())));
        JSONObject peer = readPlain();
        String peerId = peer.getString("id");
        if (peerId.length() > 64) throw new IOException("Invalid pairing message");
        p.validateRound1PayloadReceived(new JPAKERound1Payload(peerId,number(peer,"x"),number(peer,"y"),proof(peer,"px"),proof(peer,"py")));
        JPAKERound2Payload r2 = p.createRound2PayloadToSend();
        writePlain(new JSONObject().put("id",id).put("a",r2.getA().toString()).put("p",numbers(r2.getKnowledgeProofForX2s())));
        peer = readPlain();
        p.validateRound2PayloadReceived(new JPAKERound2Payload(peer.getString("id"),number(peer,"a"),proof(peer,"p")));
        BigInteger material = p.calculateKeyingMaterial();
        JPAKERound3Payload r3 = p.createRound3PayloadToSend(material);
        writePlain(new JSONObject().put("id",id).put("mac",r3.getMacTag().toString()));
        peer = readPlain();
        p.validateRound3PayloadReceived(new JPAKERound3Payload(peer.getString("id"),number(peer,"mac")),material);
        // Bind fresh participant identities and direction to separate traffic keys.
        String context = host ? id+":"+peerId : peerId+":"+id;
        byte[] secret = material.toByteArray();
        sendKey = derive(secret,context+(host ? ":host" : ":guest"));
        receiveKey = derive(secret,context+(host ? ":guest" : ":host"));
        Arrays.fill(secret,(byte)0);
        socket.setSoTimeout(120000);
    }
    private static byte[] derive(byte[] key,String label) throws Exception {
        Mac mac=Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(key,"HmacSHA256"));
        return mac.doFinal(("YR-Sharing-v1:"+label).getBytes(StandardCharsets.UTF_8));
    }
    private static JSONArray numbers(BigInteger[] values) { JSONArray a=new JSONArray(); for(BigInteger v:values)a.put(v.toString());return a; }
    private static BigInteger number(JSONObject o,String key)throws Exception { return parse(o.getString(key)); }
    private static BigInteger parse(String s)throws IOException { if(s.length()>1100)throw new IOException("Invalid pairing proof");return new BigInteger(s); }
    private static BigInteger[] proof(JSONObject o,String key)throws Exception { JSONArray a=o.getJSONArray(key);if(a.length()!=2)throw new IOException("Invalid pairing proof");return new BigInteger[]{parse(a.getString(0)),parse(a.getString(1))}; }
    private void writePlain(JSONObject o)throws Exception { byte[] b=o.toString().getBytes(StandardCharsets.UTF_8);out.writeInt(b.length);out.write(b);out.flush(); }
    private JSONObject readPlain()throws Exception { return new JSONObject(new String(readFrame(16384),StandardCharsets.UTF_8)); }
    private byte[] readFrame(int max)throws IOException { int n=in.readInt();if(n<1||n>max)throw new IOException("Invalid sharing frame");byte[] b=new byte[n];in.readFully(b);return b; }
    private static Cipher cipher(int mode,byte[] key,long sequence)throws Exception {
        byte[] nonce=ByteBuffer.allocate(12).putInt(0).putLong(sequence).array();
        Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(mode,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce));
        c.updateAAD("YR-Sharing-v1".getBytes(StandardCharsets.UTF_8));return c;
    }
    synchronized void send(JSONObject message)throws Exception {
        byte[] clear=message.toString().getBytes(StandardCharsets.UTF_8);
        if(clear.length>MAX_FRAME-16||sent==Long.MAX_VALUE)throw new IOException("Sharing frame too large");
        byte[] encrypted=cipher(Cipher.ENCRYPT_MODE,sendKey,sent++).doFinal(clear);
        out.writeInt(encrypted.length);out.write(encrypted);out.flush();
    }
    JSONObject receive()throws Exception {
        if(received==Long.MAX_VALUE)throw new IOException("Sharing session expired");
        return new JSONObject(new String(cipher(Cipher.DECRYPT_MODE,receiveKey,received++).doFinal(readFrame(MAX_FRAME)),StandardCharsets.UTF_8));
    }
    @Override public void close() { try{socket.close();}catch(IOException ignored){} Arrays.fill(sendKey,(byte)0);Arrays.fill(receiveKey,(byte)0); }
}
