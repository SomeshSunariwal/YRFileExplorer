package com.somesh.yrfileexplorer.media;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.Dialog;
import android.content.*;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.text.TextUtils;
import android.view.*;
import android.widget.*;
import com.somesh.yrfileexplorer.R;
import com.somesh.yrfileexplorer.files.FileEngine;
import java.io.File;
import java.util.*;

/** Local music dashboard using the same surfaces, icons and spacing as Explorer. */
public class MediaViewerActivity extends Activity {
    private static final int CYAN=0xff0ba5c6;
    private int canvas=0xfff3f6fa,surface=Color.WHITE,ink=0xff1c2938,muted=0xff718092,line=0xffdce2e8,tint=0xffe6f5fa;
    private Typeface regularFont,mediumFont;
    private Typeface playerFont(boolean bold){
        if(regularFont==null){
            try{regularFont=Typeface.createFromFile("/system/fonts/Roboto-Regular.ttf");}
            catch(RuntimeException ignored){regularFont=Typeface.create("sans-serif",Typeface.NORMAL);}
            mediumFont=Typeface.create(regularFont,Typeface.BOLD);
        }
        return bold?mediumFont:regularFont;
    }
    private final Handler handler=new Handler(Looper.getMainLooper());
    private AudioPlaybackService audio;
    private boolean bound,seeking,queueVisible;
    private TextView header,title,artist,status,elapsed,duration,playingTab,playlistTab;
    private ImageButton play,shuffle,repeat;
    private int displayedRepeat=-1;
    private ImageView artwork,placeholder;
    private Bitmap displayedArtwork;
    private SeekBar seek;
    private ProgressBar loading;
    private MusicPager pages;
    private View tabIndicator;
    private FrameLayout tabTrack;
    private LinearLayout root,playing;
    private FrameLayout artFrame;
    private ListView queue;
    private QueueAdapter queueAdapter;
    private String queueState="";
    private final Runnable ticker=new Runnable(){public void run(){update();handler.postDelayed(this,400);}};
    private final ServiceConnection connection=new ServiceConnection(){
        @Override public void onServiceConnected(ComponentName name,IBinder binder){
            audio=((AudioPlaybackService.LocalBinder)binder).service();audio.listener=MediaViewerActivity.this::update;
            loadIntent();update();
        }
        @Override public void onServiceDisconnected(ComponentName name){audio=null;update();}
    };
    private int dp(float value){return ViewerUi.dp(this,value);}
    private TextView text(String value,int size,int color){
        TextView view=new TextView(this);view.setText(value);view.setTextSize(size);view.setTextColor(color);
        view.setTypeface(playerFont(false));view.setGravity(Gravity.CENTER_VERTICAL);view.setIncludeFontPadding(false);return view;
    }
    private GradientDrawable shape(int color,int radius,boolean border){
        GradientDrawable drawable=ViewerUi.rounded(this,color,radius);if(border)drawable.setStroke(dp(1),line);return drawable;
    }
    private ImageButton icon(int resource,String label,Runnable action){
        ImageButton button=ViewerUi.iconButton(this,resource,label,action);
        button.setScaleType(ImageView.ScaleType.CENTER_INSIDE);button.setColorFilter(CYAN);return button;
    }
    private LinearLayout row(){LinearLayout view=new LinearLayout(this);view.setGravity(Gravity.CENTER_VERTICAL);return view;}
    private void space(LinearLayout parent,int height){parent.addView(new View(this),new LinearLayout.LayoutParams(1,dp(height)));}
    private void bold(TextView view){view.setTypeface(playerFont(true));}

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        try{if(new org.json.JSONObject(getSharedPreferences("yr_preferences",MODE_PRIVATE).getString("settings","{}")).optBoolean("dark",false)){
            canvas=0xff292929;surface=0xff333333;ink=0xffeef3f8;muted=0xffa6b2bc;line=0xff494949;tint=0xff24454d;
        }}catch(org.json.JSONException ignored){}
        getWindow().setStatusBarColor(canvas);getWindow().setNavigationBarColor(canvas);
        getWindow().getDecorView().setSystemUiVisibility(canvas==0xff292929?0:View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(canvas);
        root.setOnApplyWindowInsetsListener((v,insets)->{Insets bars=insets.getInsets(WindowInsets.Type.systemBars());v.setPadding(bars.left,bars.top,bars.right,bars.bottom);return insets;});
        LinearLayout toolbar=row();toolbar.setPadding(dp(4),0,dp(4),0);
        toolbar.addView(icon(R.drawable.ic_viewer_back,"Back",this::finish));
        header=text("Now playing",16,ink);bold(header);header.setGravity(Gravity.CENTER);
        toolbar.addView(header,new LinearLayout.LayoutParams(0,dp(52),1));
        toolbar.addView(icon(R.drawable.ic_music_more,"More",this::menu));root.addView(toolbar,new LinearLayout.LayoutParams(-1,dp(52)));

        pages=new MusicPager();root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);scroll.setClipToPadding(false);scroll.setVerticalScrollBarEnabled(false);
        playing=new LinearLayout(this);playing.setOrientation(LinearLayout.VERTICAL);playing.setGravity(Gravity.CENTER);playing.setPadding(dp(24),dp(12),dp(24),dp(12));scroll.addView(playing);
        artFrame=new FrameLayout(this);artFrame.setBackground(shape(tint,22,false));artFrame.setClipToOutline(true);artFrame.setElevation(dp(2));
        GradientDrawable cover=new GradientDrawable(GradientDrawable.Orientation.TL_BR,new int[]{tint,canvas});cover.setCornerRadius(dp(22));artFrame.setBackground(cover);
        placeholder=new ImageView(this);placeholder.setImageResource(R.drawable.ic_music_music);placeholder.setColorFilter(CYAN);placeholder.setScaleType(ImageView.ScaleType.FIT_CENTER);placeholder.setPadding(dp(66),dp(66),dp(66),dp(66));artFrame.addView(placeholder,new FrameLayout.LayoutParams(-1,-1));
        artwork=new ImageView(this);artwork.setScaleType(ImageView.ScaleType.CENTER_CROP);artwork.setVisibility(View.GONE);artFrame.addView(artwork,new FrameLayout.LayoutParams(-1,-1));
        playing.addView(artFrame,new LinearLayout.LayoutParams(dp(240),dp(240)));space(playing,24);
        title=text(getIntent().getStringExtra("title"),18,ink);bold(title);title.setGravity(Gravity.CENTER);title.setMaxLines(2);title.setEllipsize(TextUtils.TruncateAt.END);playing.addView(title,new LinearLayout.LayoutParams(-1,-2));space(playing,8);
        artist=text("Unknown artist",13,muted);artist.setGravity(Gravity.CENTER);artist.setMaxLines(1);artist.setEllipsize(TextUtils.TruncateAt.END);playing.addView(artist,new LinearLayout.LayoutParams(-1,dp(20)));
        status=text("",12,muted);status.setGravity(Gravity.CENTER);status.setMaxLines(2);status.setVisibility(View.GONE);playing.addView(status,new LinearLayout.LayoutParams(-1,-2));space(playing,16);
        FrameLayout progress=new FrameLayout(this);seek=new SeekBar(this);seek.setProgressTintList(ColorStateList.valueOf(CYAN));seek.setThumbTintList(ColorStateList.valueOf(CYAN));seek.setProgressBackgroundTintList(ColorStateList.valueOf(line));progress.addView(seek,new FrameLayout.LayoutParams(-1,dp(32)));
        loading=new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);loading.setIndeterminate(true);loading.setIndeterminateTintList(ColorStateList.valueOf(CYAN));FrameLayout.LayoutParams loadParams=new FrameLayout.LayoutParams(-1,dp(2),Gravity.CENTER);loadParams.setMargins(dp(16),0,dp(16),0);progress.addView(loading,loadParams);playing.addView(progress,new LinearLayout.LayoutParams(-1,dp(32)));
        LinearLayout times=row();times.setPadding(dp(12),0,dp(12),0);elapsed=text("0:00",11,muted);duration=text("0:00",11,muted);duration.setGravity(Gravity.RIGHT|Gravity.CENTER_VERTICAL);times.addView(elapsed,new LinearLayout.LayoutParams(0,dp(20),1));times.addView(duration,new LinearLayout.LayoutParams(0,dp(20),1));playing.addView(times);space(playing,12);
        seek.setOnTouchListener((v,event)->{if(event.getActionMasked()==MotionEvent.ACTION_DOWN)v.getParent().requestDisallowInterceptTouchEvent(true);return false;});
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            public void onStartTrackingTouch(SeekBar bar){seeking=true;}
            public void onProgressChanged(SeekBar bar,int value,boolean user){if(user)elapsed.setText(time(value));}
            public void onStopTrackingTouch(SeekBar bar){seeking=false;if(audio!=null)audio.seek(bar.getProgress());}
        });
        LinearLayout controls=row();controls.setGravity(Gravity.CENTER);
        shuffle=icon(R.drawable.ic_music_shuffle,"Shuffle off",()->{if(audio!=null){audio.shuffle=!audio.shuffle;update();}});controls.addView(shuffle,new LinearLayout.LayoutParams(0,dp(48),1));
        controls.addView(icon(R.drawable.ic_music_previous,"Previous",()->{if(audio!=null)audio.next(-1);}),new LinearLayout.LayoutParams(0,dp(48),1));
        play=icon(R.drawable.ic_music_play,"Play",()->{if(audio!=null)audio.toggle();update();});play.setColorFilter(Color.WHITE);play.setPadding(dp(15),dp(15),dp(15),dp(15));play.setBackground(shape(CYAN,28,false));play.setElevation(dp(2));controls.addView(play,new LinearLayout.LayoutParams(dp(56),dp(56)));
        controls.addView(icon(R.drawable.ic_music_next,"Next",()->{if(audio!=null)audio.next(1);}),new LinearLayout.LayoutParams(0,dp(48),1));
        repeat=icon(R.drawable.ic_music_repeat,"Repeat off",()->{if(audio!=null){audio.repeat=(audio.repeat+1)%3;update();}});controls.addView(repeat,new LinearLayout.LayoutParams(0,dp(48),1));controls.setPadding(dp(8),dp(8),dp(8),dp(8));controls.setBackground(shape(surface,36,true));controls.setElevation(dp(4));
        LinearLayout.LayoutParams controlsParams=new LinearLayout.LayoutParams(-1,dp(72));controlsParams.setMargins(dp(16),dp(8),dp(16),dp(20));root.addView(controls,controlsParams);pages.addPage(scroll);

        queue=new ListView(this);queue.setPadding(dp(12),dp(12),dp(12),dp(12));queue.setClipToPadding(false);queue.setDivider(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));queue.setDividerHeight(dp(6));queueAdapter=new QueueAdapter();queue.setAdapter(queueAdapter);queue.setOnItemClickListener((parent,view,position,id)->{if(audio!=null){audio.select(position);showQueue(false);}});pages.addPage(queue);
        tabTrack=new FrameLayout(this);tabTrack.setBackground(shape(canvas,20,true));
        tabIndicator=new View(this);tabIndicator.setBackground(shape(surface,16,true));tabIndicator.setElevation(0);FrameLayout.LayoutParams indicatorParams=new FrameLayout.LayoutParams(dp(110),dp(28));indicatorParams.setMargins(dp(4),dp(4),0,0);tabTrack.addView(tabIndicator,indicatorParams);
        LinearLayout navigation=row();playingTab=tab("Playing",R.drawable.ic_music_music,()->showQueue(false));playlistTab=tab("Playlist",R.drawable.ic_music_queue,()->showQueue(true));navigation.addView(playingTab,new LinearLayout.LayoutParams(0,-1,1));navigation.addView(playlistTab,new LinearLayout.LayoutParams(0,-1,1));FrameLayout.LayoutParams navigationInner=new FrameLayout.LayoutParams(-1,-1);navigationInner.setMargins(dp(4),dp(4),dp(4),dp(4));tabTrack.addView(navigation,navigationInner);
        LinearLayout.LayoutParams navigationParams=new LinearLayout.LayoutParams(dp(228),dp(36));navigationParams.gravity=Gravity.CENTER_HORIZONTAL;navigationParams.setMargins(0,dp(8),0,dp(4));root.addView(tabTrack,0,navigationParams);
        tabTrack.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{int slot=(r-l-dp(8))/2;if(tabIndicator.getLayoutParams().width!=slot){tabIndicator.getLayoutParams().width=slot;tabIndicator.requestLayout();}updateTabPosition(pages.getWidth()==0?0:(float)pages.getScrollX()/pages.getWidth());});
        pages.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{int extra=playing.getPaddingTop()+playing.getPaddingBottom();for(int i=0;i<playing.getChildCount();i++){View child=playing.getChildAt(i);if(child!=artFrame&&child.getVisibility()!=View.GONE)extra+=child.getMeasuredHeight();}int size=Math.min(dp(288),Math.min(Math.max(dp(128),r-l-dp(48)),Math.max(dp(128),b-t-extra)));if(artFrame.getLayoutParams().width!=size){artFrame.setLayoutParams(new LinearLayout.LayoutParams(size,size));int padding=Math.max(dp(28),size/3);placeholder.setPadding(padding,padding,padding,padding);}});
        setContentView(root);showQueue(false);
    }

    private TextView tab(String label,int resource,Runnable action){TextView tab=text(label,12,muted);bold(tab);tab.setGravity(Gravity.CENTER);android.graphics.drawable.Drawable icon=getDrawable(resource);icon.setBounds(0,0,dp(18),dp(18));icon.setTint(CYAN);tab.setCompoundDrawablePadding(dp(6));tab.setCompoundDrawables(icon,null,null,null);tab.setPadding(dp(10),0,dp(10),0);tab.setOnClickListener(v->action.run());return tab;}
    private void showQueue(boolean show){pages.goTo(show?1:0);}
    private void updateTabPosition(float fraction){
        if(tabIndicator==null||playingTab==null)return;
        fraction=Math.max(0,Math.min(1,fraction));
        tabIndicator.setTranslationX(tabIndicator.getLayoutParams().width*fraction);
        queueVisible=fraction>=.5f;header.setText(queueVisible?"Playlist":"Now playing");
        playingTab.setTextColor(queueVisible?muted:CYAN);playlistTab.setTextColor(queueVisible?CYAN:muted);
    }
    /** Finger-linked horizontal pages; vertical scrolling remains with each page. */
    private class MusicPager extends HorizontalScrollView {
        final LinearLayout strip;
        float downX;
        int startPage;
        MusicPager(){super(MediaViewerActivity.this);setHorizontalScrollBarEnabled(false);setOverScrollMode(OVER_SCROLL_NEVER);strip=new LinearLayout(MediaViewerActivity.this);strip.setOrientation(LinearLayout.HORIZONTAL);addView(strip,new FrameLayout.LayoutParams(-2,-1));}
        void addPage(View page){strip.addView(page,new LinearLayout.LayoutParams(1,-1));}
        void goTo(int page){if(getWidth()==0){post(()->goTo(page));return;}if(ValueAnimator.areAnimatorsEnabled())smoothScrollTo(page*getWidth(),0);else scrollTo(page*getWidth(),0);}
        @Override protected void onMeasure(int widthSpec,int heightSpec){int width=MeasureSpec.getSize(widthSpec);for(int i=0;i<strip.getChildCount();i++){View page=strip.getChildAt(i);if(page.getLayoutParams().width!=width)page.getLayoutParams().width=width;}strip.getLayoutParams().width=width*strip.getChildCount();super.onMeasure(widthSpec,heightSpec);}
        @Override protected void onScrollChanged(int x,int y,int oldX,int oldY){super.onScrollChanged(x,y,oldX,oldY);if(getWidth()>0)updateTabPosition((float)x/getWidth());}
        @Override public boolean onInterceptTouchEvent(MotionEvent event){
            if(event.getActionMasked()==MotionEvent.ACTION_DOWN){downX=event.getX();startPage=Math.round((float)getScrollX()/Math.max(1,getWidth()));}
            return super.onInterceptTouchEvent(event);
        }
        @Override public void fling(int velocity){/* Release snaps to a page rather than free-scrolling. */}
        @Override public boolean onTouchEvent(MotionEvent event){
            if(event.getActionMasked()==MotionEvent.ACTION_DOWN){downX=event.getX();startPage=Math.round((float)getScrollX()/Math.max(1,getWidth()));}
            boolean handled=super.onTouchEvent(event);
            if(event.getActionMasked()==MotionEvent.ACTION_UP||event.getActionMasked()==MotionEvent.ACTION_CANCEL){float delta=downX-event.getX();int nearest=Math.round((float)getScrollX()/Math.max(1,getWidth()));int target=Math.abs(delta)>getWidth()*.15f?startPage+(delta>0?1:-1):nearest;final int page=Math.max(0,Math.min(1,target));post(()->goTo(page));}
            return handled;
        }
    }
    private void loadIntent(){if(audio==null)return;String path=getIntent().getStringExtra("sourcePath");if((path==null||path.isEmpty())&&getIntent().getData()!=null)path=getIntent().getData().toString();if(path==null||path.isEmpty())return;ArrayList<String> files=getIntent().getStringArrayListExtra("playlist");audio.load(files,path);}
    @Override protected void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);loadIntent();}
    private String time(int ms){int seconds=Math.max(0,ms/1000);return String.format(Locale.ROOT,"%d:%02d",seconds/60,seconds%60);}
    private void update(){
        if(play==null)return;boolean ready=audio!=null&&audio.prepared,active=audio!=null&&audio.playing();
        play.setImageResource(active?R.drawable.ic_music_pause:R.drawable.ic_music_play);play.setColorFilter(Color.WHITE);play.setContentDescription(active?"Pause":"Play");seek.setEnabled(ready);loading.setVisibility(audio==null||audio.loading?View.VISIBLE:View.GONE);seek.setVisibility(audio==null||audio.loading?View.INVISIBLE:View.VISIBLE);
        int length=ready?audio.duration():0;seek.setMax(Math.max(1,length));duration.setText(time(length));if(!seeking){int position=ready?audio.position():0;seek.setProgress(position);elapsed.setText(time(position));}
        if(audio==null)return;title.setText(audio.title());artist.setText(audio.artist);status.setText(audio.error==null?"":audio.error);status.setVisibility(audio.error==null?View.GONE:View.VISIBLE);status.setTextColor(0xffd64a4a);
        artwork.setVisibility(audio.artwork==null?View.GONE:View.VISIBLE);placeholder.setVisibility(audio.artwork==null?View.VISIBLE:View.GONE);if(displayedArtwork!=audio.artwork){displayedArtwork=audio.artwork;artwork.setImageBitmap(displayedArtwork);}
        shuffle.setColorFilter(audio.shuffle?CYAN:muted);shuffle.setBackground(shape(audio.shuffle?tint:Color.TRANSPARENT,24,false));shuffle.setContentDescription(audio.shuffle?"Shuffle on":"Shuffle off");
        if(displayedRepeat!=audio.repeat){
            displayedRepeat=audio.repeat;
            repeat.setImageResource(audio.repeat==2?R.drawable.ic_music_repeat_one:R.drawable.ic_music_repeat);
            repeat.setColorFilter(audio.repeat==0?muted:CYAN);
            repeat.setBackground(shape(audio.repeat==0?Color.TRANSPARENT:tint,24,false));
            repeat.setContentDescription(audio.repeat==2?"Repeat one":audio.repeat==1?"Repeat all":"Repeat off");
        }
        String state=audio.queue.toString()+"|"+audio.index+"|"+active;if(!state.equals(queueState)){queueState=state;queueAdapter.notifyDataSetChanged();}
    }
    private class QueueAdapter extends BaseAdapter {
        @Override public int getCount(){return audio==null?0:audio.queue.size();}
        @Override public Object getItem(int position){return audio.queue.get(position);}
        @Override public long getItemId(int position){return position;}
        @Override public View getView(int position,View convert,ViewGroup parent){
            boolean current=audio!=null&&position==audio.index;LinearLayout item=row();item.setPadding(dp(12),dp(8),dp(12),dp(8));item.setMinimumHeight(dp(64));item.setBackground(shape(current?tint:canvas,14,true));
            ImageView note=new ImageView(MediaViewerActivity.this);note.setImageResource(current&&audio.playing()?R.drawable.ic_music_pause:R.drawable.ic_music_music);note.setColorFilter(CYAN);note.setPadding(dp(8),dp(8),dp(8),dp(8));item.addView(note,new LinearLayout.LayoutParams(dp(40),dp(40)));
            TextView name=text(new File(audio.queue.get(position)).getName(),14,current?CYAN:ink);name.setMaxLines(2);name.setEllipsize(TextUtils.TruncateAt.END);LinearLayout.LayoutParams label=new LinearLayout.LayoutParams(0,-2,1);label.setMargins(dp(8),0,dp(8),0);item.addView(name,label);
            item.addView(text(String.valueOf(position+1),11,muted));return item;
        }
    }
    private void external(){try{startActivity(Intent.createChooser(new Intent(Intent.ACTION_VIEW).setDataAndType(getIntent().getData(),getIntent().getType()).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),"Open with"));}catch(Exception error){Toast.makeText(this,"No compatible player found",Toast.LENGTH_SHORT).show();}}
    private LinearLayout dialogBody(Dialog dialog,String heading){
        LinearLayout box=new LinearLayout(this);box.setOrientation(LinearLayout.VERTICAL);box.setBackground(shape(surface,12,false));
        FrameLayout top=new FrameLayout(this);TextView label=text(heading,16,ink);bold(label);label.setGravity(Gravity.CENTER);top.addView(label,new FrameLayout.LayoutParams(-1,dp(48)));FrameLayout.LayoutParams closeParams=new FrameLayout.LayoutParams(dp(48),dp(48),Gravity.RIGHT);top.addView(icon(R.drawable.ic_music_close,"Close",dialog::dismiss),closeParams);box.addView(top);divider(box);return box;
    }
    private void divider(LinearLayout box){View rule=new View(this);rule.setBackgroundColor(line);box.addView(rule,new LinearLayout.LayoutParams(-1,dp(1)));}
    private void showDialog(Dialog dialog,LinearLayout box){dialog.setContentView(box);Window window=dialog.getWindow();if(window!=null){window.setBackgroundDrawableResource(android.R.color.transparent);window.setLayout(Math.min(getResources().getDisplayMetrics().widthPixels-dp(32),dp(400)),-2);}dialog.show();if(window!=null)window.setLayout(Math.min(getResources().getDisplayMetrics().widthPixels-dp(32),dp(400)),-2);}
    private void menu(){
        Dialog dialog=new Dialog(this);LinearLayout box=dialogBody(dialog,"Music");String[] names={"Playlist","Save playlist","Open with","Stop"};int[] icons={R.drawable.ic_music_queue,R.drawable.ic_music_save,R.drawable.ic_music_open,R.drawable.ic_music_stop};
        for(int i=0;i<names.length;i++){final int choice=i;LinearLayout item=row();item.setPadding(dp(12),0,dp(18),0);ImageButton itemIcon=icon(icons[i],names[i],()->{});itemIcon.setClickable(false);itemIcon.setFocusable(false);item.addView(itemIcon);item.addView(text(names[i],14,ink));item.setOnClickListener(v->{dialog.dismiss();if(choice==0)showQueue(true);else if(choice==1)savePlaylist();else if(choice==2)external();else{stopService(new Intent(this,AudioPlaybackService.class));finish();}});box.addView(item,new LinearLayout.LayoutParams(-1,dp(48)));if(i<names.length-1)divider(box);}showDialog(dialog,box);
    }
    private void savePlaylist(){
        if(audio==null||audio.queue.isEmpty())return;Dialog dialog=new Dialog(this);LinearLayout box=dialogBody(dialog,"Save playlist");EditText name=new EditText(this);name.setTypeface(playerFont(false));name.setTextSize(14);name.setSingleLine(true);name.setTextColor(ink);name.setText("Playlist");name.setSelectAllOnFocus(true);name.setPadding(dp(12),0,dp(12),0);name.setBackground(shape(canvas,12,true));LinearLayout.LayoutParams input=new LinearLayout.LayoutParams(-1,dp(48));input.setMargins(dp(18),dp(16),dp(18),dp(16));box.addView(name,input);divider(box);
        LinearLayout actions=row();actions.setGravity(Gravity.CENTER);TextView cancel=text("Cancel",14,CYAN),save=text("Save",14,CYAN);cancel.setGravity(Gravity.CENTER);save.setGravity(Gravity.CENTER);cancel.setOnClickListener(v->dialog.dismiss());save.setOnClickListener(v->{try{String filename=name.getText().toString().trim();java.nio.file.Path folder=java.nio.file.Paths.get(Environment.getExternalStorageDirectory().getAbsolutePath(),"Music","Playlists");java.nio.file.Files.createDirectories(folder);java.nio.file.Path target=FileEngine.named(folder,filename.endsWith(".m3u")?filename:filename+".m3u");ArrayList<String> lines=new ArrayList<>();lines.add("#EXTM3U");for(String file:audio.queue){if(file.contains("\n")||file.contains("\r"))throw new java.io.IOException("A file name contains a line break");lines.add(file);}java.nio.file.Files.write(target,lines,java.nio.charset.StandardCharsets.UTF_8,java.nio.file.StandardOpenOption.CREATE_NEW);dialog.dismiss();Toast.makeText(this,"Playlist saved",Toast.LENGTH_SHORT).show();}catch(Exception error){name.setError(error.getMessage());}});actions.addView(cancel,new LinearLayout.LayoutParams(dp(100),dp(48)));actions.addView(save,new LinearLayout.LayoutParams(dp(100),dp(48)));box.addView(actions);showDialog(dialog,box);
    }
    private boolean backgroundPlaybackEnabled(){
        try{return new org.json.JSONObject(getSharedPreferences("yr_preferences",MODE_PRIVATE).getString("settings","{}")).optBoolean("backgroundPlayback",false);}
        catch(org.json.JSONException ignored){return false;}
    }
    @Override protected void onStart(){
        super.onStart();
        if(!bound){Intent service=new Intent(this,AudioPlaybackService.class);startForegroundService(service);bound=bindService(service,connection,BIND_AUTO_CREATE);}
    }
    @Override protected void onStop(){
        if(audio!=null)audio.listener=null;
        if(!backgroundPlaybackEnabled()&&!isChangingConfigurations())stopService(new Intent(this,AudioPlaybackService.class));
        if(bound){unbindService(connection);bound=false;}
        audio=null;
        super.onStop();
    }
    @Override protected void onResume(){super.onResume();handler.removeCallbacks(ticker);handler.post(ticker);}
    @Override protected void onPause(){handler.removeCallbacks(ticker);super.onPause();}
    @Override protected void onDestroy(){handler.removeCallbacks(ticker);if(audio!=null)audio.listener=null;if(bound)unbindService(connection);super.onDestroy();}
}
