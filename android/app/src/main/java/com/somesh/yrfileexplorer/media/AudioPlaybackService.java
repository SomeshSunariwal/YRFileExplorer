package com.somesh.yrfileexplorer.media;

import com.somesh.yrfileexplorer.sharing.ShareProvider;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaMetadata;
import android.media.MediaMetadataRetriever;
import android.media.MediaPlayer;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.net.Uri;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/** Local playback with system transport controls and explicit user-started foreground lifetime. */
public class AudioPlaybackService extends Service {
    public final ArrayList<String> queue=new ArrayList<>();
    public int index,repeat;
    public boolean shuffle,prepared,loading;
    public String error;
    public String trackTitle="",artist="Unknown artist";
    public android.graphics.Bitmap artwork;
    private final java.util.concurrent.ExecutorService metadataWorker=java.util.concurrent.Executors.newSingleThreadExecutor();
    public Runnable listener;
    private MediaPlayer player;
    private AudioManager audioManager;
    private AudioFocusRequest focus;
    private MediaSession session;
    private boolean resumeOnFocus;
    private final Random random=new Random();
    public class LocalBinder extends Binder {AudioPlaybackService service(){return AudioPlaybackService.this;}}
    private final BroadcastReceiver noisy=new BroadcastReceiver(){@Override public void onReceive(Context c,Intent i){pause();}};
    @Override public void onCreate(){
        super.onCreate();audioManager=getSystemService(AudioManager.class);
        getSystemService(NotificationManager.class).createNotificationChannel(new NotificationChannel("local_playback","Music playback",NotificationManager.IMPORTANCE_LOW));
        session=new MediaSession(this,"YR local player");session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS|MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);session.setCallback(new MediaSession.Callback(){
            @Override public void onPlay(){play();}@Override public void onPause(){pause();}@Override public void onSkipToNext(){next(1);}@Override public void onSkipToPrevious(){next(-1);}@Override public void onSeekTo(long p){seek((int)p);}@Override public void onStop(){stopSelf();}
        });session.setActive(true);
        focus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()).setOnAudioFocusChangeListener(change->{
            if(change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK){if(prepared)player.setVolume(.2f,.2f);}
            else if(change==AudioManager.AUDIOFOCUS_GAIN){if(prepared){player.setVolume(1,1);if(resumeOnFocus){resumeOnFocus=false;play();}}}
            else{resumeOnFocus=change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT&&playing();pause();}
        }).build();
        if(Build.VERSION.SDK_INT>=33)registerReceiver(noisy,new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),Context.RECEIVER_NOT_EXPORTED);else registerReceiver(noisy,new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
        publish();
    }
    public String current(){return queue.isEmpty()?"":queue.get(index);}
    public String title(){return queue.isEmpty()?"Music":trackTitle.isEmpty()?new File(current()).getName():trackTitle;}
    private Uri uri(){return current().startsWith("content:")?Uri.parse(current()):ShareProvider.uri(new File(current()));}
    public void load(List<String> files,String path){
        if(path == null || path.isEmpty()) return;
        if(path.equals(current()) && player != null) {
            if(error != null) startTrack(); else play();
            return;
        }
        queue.clear();
        if(files != null) for(String file : files) if(file != null && !file.isEmpty() && !queue.contains(file)) queue.add(file);
        if(!queue.contains(path)) queue.add(0,path);
        index=queue.indexOf(path);startTrack();
    }
    public boolean playing(){try{return prepared&&player!=null&&player.isPlaying();}catch(IllegalStateException ignored){return false;}}
    public int position(){try{return prepared?player.getCurrentPosition():0;}catch(IllegalStateException ignored){return 0;}}
    public int duration(){try{return prepared?player.getDuration():0;}catch(IllegalStateException ignored){return 0;}}
    public void seek(int value){if(prepared){player.seekTo(Math.max(0,Math.min(value,duration())));publish();}}
    public void play(){
        if(!prepared || player == null) return;
        try {
            if(audioManager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                error=null; player.start();
            } else error="Audio is in use. Tap Play to try again.";
        } catch(IllegalStateException ex) { error="Playback stopped. Tap Play to retry."; prepared=false; }
        publish();
    }
    public void pause(){if(playing())player.pause();publish();}
    public void toggle(){if(playing())pause();else if(error!=null&&!prepared)startTrack();else play();}
    public void select(int target) {
        if (target < 0 || target >= queue.size()) return;
        if (target == index) {
            if (error != null) startTrack();
            else if (prepared && !playing()) play();
            return;
        }
        index = target;
        startTrack();
    }

    public void next(int delta){if(queue.isEmpty())return;if(delta<0&&position()>3000){seek(0);return;}index=shuffle&&queue.size()>1?(index+1+random.nextInt(queue.size()-1))%queue.size():Math.floorMod(index+delta,queue.size());startTrack();}
    private void startTrack(){
        if(player!=null)player.release();prepared=false;loading=true;error=null;trackTitle="";artist="Unknown artist";artwork=null;player=new MediaPlayer();
        final String track=current();final Uri source=uri();
        metadataWorker.submit(()->{
            try(MediaMetadataRetriever data=new MediaMetadataRetriever()){
                data.setDataSource(this,source);String name=data.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),performer=data.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST);byte[] image=data.getEmbeddedPicture();android.graphics.Bitmap cover=null;
                if(image!=null){android.graphics.BitmapFactory.Options options=new android.graphics.BitmapFactory.Options();options.inJustDecodeBounds=true;android.graphics.BitmapFactory.decodeByteArray(image,0,image.length,options);options.inJustDecodeBounds=false;options.inSampleSize=Math.max(1,Math.max(options.outWidth,options.outHeight)/512);cover=android.graphics.BitmapFactory.decodeByteArray(image,0,image.length,options);}
                final android.graphics.Bitmap bitmap=cover;new Handler(Looper.getMainLooper()).post(()->{if(!track.equals(current())||player==null)return;trackTitle=name==null?"":name;artist=performer==null?"Unknown artist":performer;artwork=bitmap;session.setMetadata(new MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE,title()).putString(MediaMetadata.METADATA_KEY_ARTIST,artist).putLong(MediaMetadata.METADATA_KEY_DURATION,duration()).putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART,artwork).build());publish();});
            }catch(Exception ignored){}
        });
        player.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());player.setWakeMode(this,PowerManager.PARTIAL_WAKE_LOCK);
        player.setOnPreparedListener(mp->{if(mp!=player)return;prepared=true;loading=false;session.setMetadata(new MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE,title()).putLong(MediaMetadata.METADATA_KEY_DURATION,duration()).build());play();});
        player.setOnCompletionListener(mp->{if(repeat==2){seek(0);play();}else if(index+1<queue.size()||repeat==1||shuffle){next(1);}else{seek(0);publish();}});
        player.setOnErrorListener((mp,what,extra)->{error="This media format cannot be played on your device.";prepared=false;loading=false;publish();return true;});
        try{player.setDataSource(this,uri());player.prepareAsync();}catch(Exception ex){loading=false;error=ex.getMessage()==null?"Cannot open this track. Tap Play to retry.":ex.getMessage();publish();}
        publish();
    }
    private PendingIntent action(String name){return PendingIntent.getService(this,name.hashCode(),new Intent(this,AudioPlaybackService.class).setAction(name),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);}
    private void publish(){
        boolean playing=playing();
        session.setPlaybackState(new PlaybackState.Builder().setActions(PlaybackState.ACTION_PLAY|PlaybackState.ACTION_PAUSE|PlaybackState.ACTION_PLAY_PAUSE|PlaybackState.ACTION_SKIP_TO_NEXT|PlaybackState.ACTION_SKIP_TO_PREVIOUS|PlaybackState.ACTION_SEEK_TO|PlaybackState.ACTION_STOP).setState(playing?PlaybackState.STATE_PLAYING:PlaybackState.STATE_PAUSED,position(),playing?1:0).build());
        Intent open=new Intent(this,MediaViewerActivity.class).setDataAndType(queue.isEmpty()?null:uri(),"audio/*").putExtra("sourcePath",current()).putStringArrayListExtra("playlist",new ArrayList<>(queue)).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        Notification notification=new Notification.Builder(this,"local_playback").setSmallIcon(android.R.drawable.ic_media_play).setContentTitle(title()).setContentText(error!=null?error:artist).setOnlyAlertOnce(true).setOngoing(playing).setContentIntent(PendingIntent.getActivity(this,0,open,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT)).setDeleteIntent(action("STOP"))
            .addAction(new Notification.Action.Builder(android.R.drawable.ic_media_previous,"Previous",action("PREVIOUS")).build())
            .addAction(new Notification.Action.Builder(playing?android.R.drawable.ic_media_pause:android.R.drawable.ic_media_play,playing?"Pause":"Play",action("TOGGLE")).build())
            .addAction(new Notification.Action.Builder(android.R.drawable.ic_media_next,"Next",action("NEXT")).build())
            .addAction(new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel,"Stop",action("STOP")).build())
            .setStyle(new Notification.MediaStyle().setMediaSession(session.getSessionToken()).setShowActionsInCompactView(0,1,2)).build();
        startForeground(41,notification);if(listener!=null)listener.run();
    }
    @Override public IBinder onBind(Intent intent){return new LocalBinder();}
    @Override public int onStartCommand(Intent intent,int flags,int startId){if(intent!=null&&intent.getAction()!=null)switch(intent.getAction()){case "TOGGLE":toggle();break;case "NEXT":next(1);break;case "PREVIOUS":next(-1);break;case "STOP":pause();stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();break;}return START_NOT_STICKY;}
    @Override public void onDestroy(){listener=null;metadataWorker.shutdownNow();if(player!=null){player.release();player=null;}audioManager.abandonAudioFocusRequest(focus);session.release();unregisterReceiver(noisy);stopForeground(STOP_FOREGROUND_REMOVE);super.onDestroy();}
}
