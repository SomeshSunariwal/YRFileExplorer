package com.explorer.fileexplorer.media;

import com.explorer.fileexplorer.files.FileEngine;

import android.app.*;
import android.os.*;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.content.*;
import android.net.Uri;
import android.view.*;
import android.widget.*;
import java.io.File;
import java.util.*;

public class MediaViewerActivity extends Activity {
    private final int ink=Color.rgb(41,41,41),cyan=Color.rgb(0,170,202);
    private int canvas=Color.rgb(243,246,250),textInk=ink,coverColor=0xffe3f3f8;
    private final Handler handler=new Handler(Looper.getMainLooper());
    private AudioPlaybackService audio;
    private VideoView video;
    private boolean isAudio,bound,playlistVisible,seeking,videoFailed;
    private int videoPosition;
    private LinearLayout root;
    private ViewFlipper pages;
    private TextView title,artist,elapsed,total,playingTab,queueTab;
    private ImageButton play;
    private ImageView artwork;
    private TextView musicNote;
    private TextView repeat,shuffle;
    private SeekBar seek;
    private ListView queue;
    private final Runnable ticker=new Runnable(){public void run(){update();handler.postDelayed(this,400);}};
    private final ServiceConnection connection=new ServiceConnection(){
        public void onServiceConnected(ComponentName name,IBinder binder){audio=((AudioPlaybackService.LocalBinder)binder).service();audio.listener=()->update();ArrayList<String> files=getIntent().getStringArrayListExtra("playlist");String path=getIntent().getStringExtra("sourcePath");if(path==null||path.isEmpty())path=getIntent().getData().toString();audio.load(files==null?List.of(path):files,path);update();}
        public void onServiceDisconnected(ComponentName name){audio=null;}
    };
    private int dp(float value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private TextView text(String value,int size,int color){TextView t=new TextView(this);t.setText(value);t.setTextSize(size);t.setTextColor(color);t.setGravity(Gravity.CENTER_VERTICAL);return t;}
    private ImageButton icon(int resource,String label,Runnable action){ImageButton b=new ImageButton(this);b.setImageResource(resource);b.setColorFilter(cyan);b.setContentDescription(label);b.setBackgroundColor(Color.TRANSPARENT);b.setPadding(dp(12),dp(12),dp(12),dp(12));b.setOnClickListener(v->action.run());return b;}
    private GradientDrawable rounded(int color,int radius){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));return d;}
    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        try{if(new org.json.JSONObject(getSharedPreferences("yr_preferences",MODE_PRIVATE).getString("settings","{}")).optBoolean("dark",false)){canvas=0xff292929;textInk=0xffeef3f8;coverColor=0xff333333;}}catch(org.json.JSONException ignored){}
        isAudio=getIntent().getType()!=null&&getIntent().getType().startsWith("audio/");
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(ink);
        root.setOnApplyWindowInsetsListener((v,insets)->{android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars());v.setPadding(bars.left,bars.top,bars.right,bars.bottom);return insets;});
        LinearLayout tabs=new LinearLayout(this);tabs.setGravity(Gravity.CENTER);tabs.setBackgroundColor(ink);
        playingTab=text("▶ Playing",12,Color.WHITE);queueTab=text("☷ Playlist",12,Color.WHITE);playingTab.setPadding(dp(12),0,dp(12),0);queueTab.setPadding(dp(12),0,dp(12),0);tabs.addView(playingTab);if(isAudio)tabs.addView(queueTab);root.addView(tabs,new LinearLayout.LayoutParams(-1,dp(28)));
        playingTab.setOnClickListener(v->showQueue(false));queueTab.setOnClickListener(v->showQueue(true));
        LinearLayout toolbar=new LinearLayout(this);toolbar.setGravity(Gravity.CENTER_VERTICAL);toolbar.setBackgroundColor(ink);
        TextView back=text("‹",30,cyan);back.setGravity(Gravity.CENTER);back.setContentDescription("Back");back.setOnClickListener(v->finish());toolbar.addView(back,new LinearLayout.LayoutParams(dp(44),dp(56)));
        LinearLayout names=new LinearLayout(this);names.setOrientation(LinearLayout.VERTICAL);title=text(getIntent().getStringExtra("title"),16,Color.WHITE);title.setSingleLine(true);artist=text(isAudio?"Unknown artist":"Video",12,0xffb7c6d4);names.addView(title);names.addView(artist);toolbar.addView(names,new LinearLayout.LayoutParams(0,-2,1));
        ImageButton more=icon(android.R.drawable.ic_menu_more,"More",()->menu());toolbar.addView(more,new LinearLayout.LayoutParams(dp(48),dp(48)));root.addView(toolbar);
        pages=new ViewFlipper(this);pages.setBackgroundColor(canvas);
        if(isAudio){FrameLayout cover=new FrameLayout(this);musicNote=text("♫",112,cyan);musicNote.setGravity(Gravity.CENTER);musicNote.setBackground(rounded(coverColor,22));FrameLayout.LayoutParams art=new FrameLayout.LayoutParams(dp(260),dp(260),Gravity.CENTER);cover.addView(musicNote,art);artwork=new ImageView(this);artwork.setScaleType(ImageView.ScaleType.CENTER_CROP);artwork.setBackground(rounded(coverColor,22));artwork.setClipToOutline(true);artwork.setVisibility(View.GONE);cover.addView(artwork,new FrameLayout.LayoutParams(dp(260),dp(260),Gravity.CENTER));pages.addView(cover);queue=new ListView(this);queue.setDividerHeight(dp(1));queue.setOnItemClickListener((parent,view,position,id)->{if(audio!=null){audio.select(position);showQueue(false);}});pages.addView(queue);}
        else{FrameLayout frame=new FrameLayout(this);frame.setBackgroundColor(Color.BLACK);video=new VideoView(this);frame.addView(video,new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));pages.addView(frame);}
        root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout timeline=new LinearLayout(this);timeline.setBackgroundColor(canvas);timeline.setPadding(dp(12),0,dp(12),0);timeline.setGravity(Gravity.CENTER_VERTICAL);elapsed=text("00:00",12,textInk);total=text("00:00",12,textInk);timeline.addView(elapsed);seek=new SeekBar(this);seek.setProgressTintList(android.content.res.ColorStateList.valueOf(cyan));seek.setThumbTintList(android.content.res.ColorStateList.valueOf(cyan));timeline.addView(seek,new LinearLayout.LayoutParams(0,dp(48),1));timeline.addView(total);root.addView(timeline);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){public void onStartTrackingTouch(SeekBar bar){seeking=true;}public void onProgressChanged(SeekBar bar,int progress,boolean user){if(user)elapsed.setText(time(progress));}public void onStopTrackingTouch(SeekBar bar){seeking=false;if(isAudio){if(audio!=null)audio.seek(bar.getProgress());}else video.seekTo(bar.getProgress());}});
        LinearLayout controls=new LinearLayout(this);controls.setGravity(Gravity.CENTER);controls.setBackgroundColor(ink);
        controls.addView(icon(android.R.drawable.ic_media_previous,"Previous",()->{if(audio!=null)audio.next(-1);else if(video!=null)video.seekTo(Math.max(0,video.getCurrentPosition()-10000));}),new LinearLayout.LayoutParams(0,dp(56),1));
        repeat=text("↻",27,Color.WHITE);repeat.setGravity(Gravity.CENTER);repeat.setContentDescription("Repeat off");repeat.setOnClickListener(v->{if(audio!=null){audio.repeat=(audio.repeat+1)%3;update();}else if(video!=null)video.seekTo(0);});controls.addView(repeat,new LinearLayout.LayoutParams(0,dp(56),1));
        play=icon(android.R.drawable.ic_media_play,"Play",()->{if(audio!=null)audio.toggle();else if(video!=null){if(video.isPlaying())video.pause();else video.start();}update();});controls.addView(play,new LinearLayout.LayoutParams(0,dp(56),1));
        shuffle=text("⇄",25,Color.WHITE);shuffle.setGravity(Gravity.CENTER);shuffle.setContentDescription("Shuffle off");shuffle.setOnClickListener(v->{if(audio!=null){audio.shuffle=!audio.shuffle;update();}});controls.addView(shuffle,new LinearLayout.LayoutParams(0,dp(56),1));
        controls.addView(icon(android.R.drawable.ic_media_next,"Next",()->{if(audio!=null)audio.next(1);else if(video!=null)video.seekTo(Math.min(video.getDuration(),video.getCurrentPosition()+10000));}),new LinearLayout.LayoutParams(0,dp(56),1));root.addView(controls);
        setContentView(root);showQueue(false);
        if(isAudio){Intent service=new Intent(this,AudioPlaybackService.class);startForegroundService(service);bound=bindService(service,connection,BIND_AUTO_CREATE);}
        else{videoPosition=state==null?0:state.getInt("position");video.setVideoURI(getIntent().getData());video.setOnPreparedListener(mp->{video.seekTo(videoPosition);video.start();});video.setOnErrorListener((mp,what,extra)->{if(videoFailed||isFinishing())return true;videoFailed=true;video.stopPlayback();play.setEnabled(false);seek.setEnabled(false);new AlertDialog.Builder(this).setTitle("Playback unavailable").setMessage("Open this format with another player.").setPositiveButton("Open with",(d,w)->external()).setNegativeButton("Close",(d,w)->finish()).show();return true;});}
        handler.post(ticker);
    }
    private void showQueue(boolean show){playlistVisible=show;pages.setDisplayedChild(show?1:0);playingTab.setBackground(rounded(show?ink:cyan,6));queueTab.setBackground(rounded(show?cyan:ink,6));update();}
    private String time(int ms){int seconds=Math.max(0,ms/1000);return String.format(Locale.ROOT,"%02d:%02d",seconds/60,seconds%60);}
    private void update(){
        if(play==null)return;int duration=isAudio?(audio==null?0:audio.duration()):video==null||videoFailed?0:Math.max(0,video.getDuration()),position=isAudio?(audio==null?0:audio.position()):video==null||videoFailed?0:video.getCurrentPosition();boolean active=isAudio?audio!=null&&audio.playing():video!=null&&!videoFailed&&video.isPlaying();
        play.setImageResource(active?android.R.drawable.ic_media_pause:android.R.drawable.ic_media_play);play.setContentDescription(active?"Pause":"Play");seek.setMax(Math.max(1,duration));if(!seeking){seek.setProgress(position);elapsed.setText(time(position));}total.setText(time(duration));
        if(audio!=null){title.setText(audio.title());artist.setText(audio.error==null?audio.artist:audio.error);if(artwork!=null){artwork.setVisibility(audio.artwork==null?View.GONE:View.VISIBLE);artwork.setImageBitmap(audio.artwork);}repeat.setText(audio.repeat==2?"↻1":"↻");repeat.setTextColor(audio.repeat==0?Color.WHITE:cyan);repeat.setContentDescription(audio.repeat==0?"Repeat off":audio.repeat==1?"Repeat all":"Repeat one");shuffle.setTextColor(audio.shuffle?cyan:Color.WHITE);shuffle.setContentDescription(audio.shuffle?"Shuffle on":"Shuffle off");
            if(playlistVisible){ArrayList<String> names=new ArrayList<>();for(int i=0;i<audio.queue.size();i++)names.add((i==audio.index?"▶ ":"")+(i+1)+". "+new File(audio.queue.get(i)).getName());if(queue.getTag()==null||!queue.getTag().equals(names.toString())){queue.setAdapter(new ArrayAdapter<String>(this,android.R.layout.simple_list_item_1,names){@Override public View getView(int position,View convert,android.view.ViewGroup parent){TextView row=(TextView)super.getView(position,convert,parent);row.setTextColor(position==(audio==null?-1:audio.index)?cyan:textInk);row.setTextSize(14);row.setMaxLines(2);row.setEllipsize(android.text.TextUtils.TruncateAt.END);return row;}});queue.setTag(names.toString());}}
        }
    }
    private void external(){startActivity(Intent.createChooser(new Intent(Intent.ACTION_VIEW).setDataAndType(getIntent().getData(),getIntent().getType()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"Open with"));}
    private void savePlaylist(){
        if(audio==null||audio.queue.isEmpty())return;
        EditText name=new EditText(this);name.setSingleLine(true);name.setText("Playlist");name.setSelectAllOnFocus(true);
        new AlertDialog.Builder(this).setTitle("Save playlist").setMessage("Music/Playlists").setView(name).setNegativeButton("Cancel",null).setPositiveButton("Save",(d,w)->{
            try{
                String filename=name.getText().toString().trim();java.nio.file.Path folder=java.nio.file.Paths.get(android.os.Environment.getExternalStorageDirectory().getAbsolutePath(),"Music","Playlists");java.nio.file.Files.createDirectories(folder);
                java.nio.file.Path target=FileEngine.named(folder,filename.endsWith(".m3u")?filename:filename+".m3u");ArrayList<String> lines=new ArrayList<>();lines.add("#EXTM3U");for(String file:audio.queue){if(file.contains("\n")||file.contains("\r"))throw new java.io.IOException("A file name contains a line break");lines.add(file);}
                java.nio.file.Files.write(target,lines,java.nio.charset.StandardCharsets.UTF_8,java.nio.file.StandardOpenOption.CREATE_NEW);Toast.makeText(this,"Saved "+target,Toast.LENGTH_LONG).show();
            }catch(Exception error){Toast.makeText(this,error.getMessage(),Toast.LENGTH_LONG).show();}
        }).show();
    }
    private void menu(){new AlertDialog.Builder(this).setItems(isAudio?new String[]{"Playlist","Save playlist","Open with","Stop"}:new String[]{"Open with","Stop"},(dialog,which)->{
        if(isAudio){if(which==0)showQueue(true);if(which==1)savePlaylist();if(which==2)external();if(which==3){stopService(new Intent(this,AudioPlaybackService.class));finish();}}
        else if(which==0)external();else finish();
    }).show();}
    @Override protected void onPause(){if(video!=null){videoPosition=video.getCurrentPosition();video.pause();}super.onPause();}
    @Override protected void onSaveInstanceState(Bundle state){if(video!=null)state.putInt("position",video.getCurrentPosition());super.onSaveInstanceState(state);}
    @Override protected void onDestroy(){handler.removeCallbacks(ticker);if(audio!=null)audio.listener=null;if(bound)unbindService(connection);if(video!=null)video.stopPlayback();super.onDestroy();}
}
