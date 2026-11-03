package com.somesh.yrfileexplorer.media;

import java.util.Locale;
import java.util.Map;

/** Common Android 12+ local audio containers, shared by scanning and playback. */
public final class AudioFormats {
    private AudioFormats() {}
    private static final Map<String,String> MIME=Map.ofEntries(
        Map.entry("mp3","audio/mpeg"), Map.entry("mpga","audio/mpeg"),
        Map.entry("aac","audio/aac"), Map.entry("adts","audio/aac"),
        Map.entry("m4a","audio/mp4"), Map.entry("m4b","audio/mp4"),
        Map.entry("flac","audio/flac"), Map.entry("wav","audio/wav"), Map.entry("wave","audio/wav"),
        Map.entry("ogg","audio/ogg"), Map.entry("oga","audio/ogg"), Map.entry("opus","audio/ogg"),
        Map.entry("amr","audio/amr"), Map.entry("awb","audio/amr-wb"), Map.entry("3ga","audio/3gpp"),
        Map.entry("mid","audio/midi"), Map.entry("midi","audio/midi"),
        Map.entry("xmf","audio/midi"), Map.entry("mxmf","audio/midi"),
        Map.entry("rtttl","audio/midi"), Map.entry("rtx","audio/midi"),
        Map.entry("ota","audio/midi"), Map.entry("imy","audio/imelody"));
    public static String mime(String path){
        int dot=path.lastIndexOf('.');return dot<0?null:MIME.get(path.substring(dot+1).toLowerCase(Locale.ROOT));
    }
    public static boolean isAudio(String path){return mime(path)!=null;}
}
