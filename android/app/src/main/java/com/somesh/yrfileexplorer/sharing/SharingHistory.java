package com.somesh.yrfileexplorer.sharing;

import android.content.Context;
import android.util.AtomicFile;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Bounded on-device transfer log; never contains pairing codes or session keys. */
final class SharingHistory {
    private final LinkedHashMap<String,Map<String,Object>> rows=new LinkedHashMap<>();
    private final AtomicFile file;
    private long lastWrite;
    SharingHistory(Context context) {
        file=new AtomicFile(new File(context.getFilesDir(),"sharing-history.json"));
        try(InputStream in=file.openRead();ByteArrayOutputStream b=new ByteArrayOutputStream()) {
            byte[] buf=new byte[8192];int n;while((n=in.read(buf))!=-1){b.write(buf,0,n);if(b.size()>2_000_000)throw new IOException();}
            JSONArray a=new JSONArray(b.toString("UTF-8"));
            for(int i=0;i<a.length()&&i<500;i++){JSONObject j=a.getJSONObject(i);Map<String,Object> row=new HashMap<>();Iterator<String> keys=j.keys();while(keys.hasNext()){String k=keys.next();row.put(k,j.get(k));}
                if(List.of("Sending","Receiving","Queued","Verifying").contains(row.get("status")))row.put("status","Interrupted");rows.put((String)row.get("id"),row);}
        } catch(Exception ignored) { /* No history on the first launch. */ }
    }
    synchronized void update(String id,String name,String peer,String direction,long bytes,long size,String status,String path) {
        Map<String,Object> r=rows.get(id);
        if(r==null){r=new HashMap<>();r.put("id",id);r.put("time",System.currentTimeMillis());rows.put(id,r);}
        r.put("name",name);r.put("peer",peer);r.put("direction",direction);r.put("bytes",bytes);r.put("size",size);r.put("status",status);
        if(path!=null)r.put("path",path);
        while(rows.size()>500)rows.remove(rows.keySet().iterator().next());
        if(System.currentTimeMillis()-lastWrite>1000||!List.of("Sending","Receiving").contains(status))save();
    }
    synchronized List<Map<String,Object>> list(){List<Map<String,Object>> result=new ArrayList<>();for(Map<String,Object> row:rows.values())result.add(new HashMap<>(row));Collections.reverse(result);return result;}
    synchronized void clear(){rows.entrySet().removeIf(e->!List.of("Sending","Receiving","Queued","Verifying").contains(e.getValue().get("status")));save();}
    private void save(){FileOutputStream out=null;try{out=file.startWrite();out.write(new JSONArray(rows.values()).toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(out);lastWrite=System.currentTimeMillis();}catch(Exception e){if(out!=null)file.failWrite(out);}}
}
