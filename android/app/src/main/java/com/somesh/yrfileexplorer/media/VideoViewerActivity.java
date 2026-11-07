package com.somesh.yrfileexplorer.media;

import android.app.Activity;
import com.somesh.yrfileexplorer.R;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.Configuration;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.VideoView;
import java.util.Locale;
import static com.somesh.yrfileexplorer.media.ViewerUi.CYAN;
import static com.somesh.yrfileexplorer.media.ViewerUi.button;
import static com.somesh.yrfileexplorer.media.ViewerUi.dp;
import static com.somesh.yrfileexplorer.media.ViewerUi.iconButton;
import static com.somesh.yrfileexplorer.media.ViewerUi.rounded;
import static com.somesh.yrfileexplorer.media.ViewerUi.row;
import static com.somesh.yrfileexplorer.media.ViewerUi.text;

/** Local video viewer with floating controls; the video viewport never resizes. */
public class VideoViewerActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private VideoView video;
    private FrameLayout stage;
    private LinearLayout header, panel;
    private ImageButton play;
    private SeekBar seek;
    private TextView elapsed, duration;
    private ProgressBar loading;
    private boolean ready, seeking, controls = true, fill, playingBeforePause;
    private int position, width, height;
    private final Runnable hide = () -> showControls(false);
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (ready) {
                int current = video.getCurrentPosition();
                if (!seeking) { seek.setProgress(current); elapsed.setText(time(current)); }
                play.setImageResource(video.isPlaying() ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play);
                play.setContentDescription(video.isPlaying() ? "Pause" : "Play");
            }
            handler.postDelayed(this, 300);
        }
    };
    private ImageButton icon(int resource, String label, Runnable action) {
        ImageButton button = new ImageButton(this);
        button.setImageResource(resource);
        button.setColorFilter(CYAN);
        button.setContentDescription(label);
        button.setBackgroundColor(Color.TRANSPARENT);
        button.setPadding(dp(this, 12), dp(this, 12), dp(this, 12), dp(this, 12));
        button.setOnClickListener(v -> { action.run(); scheduleHide(); });
        return button;
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        boolean dark = ViewerUi.isDark(this);
        position = state == null ? 0 : state.getInt("position");
        playingBeforePause = state == null || state.getBoolean("playing", true);
        fill = state != null && state.getBoolean("fill");
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.BLACK));
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom); return insets;
        });
        stage = new FrameLayout(this);
        stage.setBackgroundColor(Color.BLACK);
        stage.setClipChildren(true);
        stage.setOnClickListener(v -> showControls(!controls));
        stage.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            if (r - l != or - ol || b - t != ob - ot) sizeVideo();
        });
        video = new VideoView(this);
        video.setOnTouchListener((v, event) -> {
            if (event.getAction() == android.view.MotionEvent.ACTION_UP) { showControls(!controls); return true; }
            return true;
        });
        stage.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
        root.addView(stage, new FrameLayout.LayoutParams(-1, -1));
        loading = new ProgressBar(this);
        loading.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(CYAN));
        root.addView(loading, new FrameLayout.LayoutParams(dp(this, 36), dp(this, 36), Gravity.CENTER));

        header = row(this);
        header.setBackground(rounded(this, 0xee333333, 20));
        header.setElevation(dark ? 0 : dp(this, 4));
        ImageButton back = iconButton(this, R.drawable.ic_viewer_back, "Back", this::finish);
        back.setScaleType(android.widget.ImageView.ScaleType.FIT_CENTER);
        back.setPadding(dp(this, 10), dp(this, 10), dp(this, 10), dp(this, 10));
        header.addView(back);
        TextView title = text(this, getIntent().getStringExtra("title"), 14, Color.WHITE);
        title.setSingleLine(true); title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        title.setPadding(0, 0, dp(this, 12), 0);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(this, 52), 1));
        FrameLayout.LayoutParams top = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
        top.setMargins(dp(this, 12), dp(this, 12), dp(this, 12), 0);
        root.addView(header, top);

        panel = new LinearLayout(this); panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(this, 12), dp(this, 4), dp(this, 12), dp(this, 4));
        panel.setBackground(rounded(this, 0xee333333, 24));
        panel.setElevation(dark ? 0 : dp(this, 6));
        LinearLayout timeline = row(this);
        elapsed = text(this, "00:00", 11, Color.WHITE);
        duration = text(this, "00:00", 11, Color.WHITE);
        timeline.addView(elapsed);
        seek = new SeekBar(this); seek.setEnabled(false);
        seek.setProgressTintList(android.content.res.ColorStateList.valueOf(CYAN));
        seek.setThumbTintList(android.content.res.ColorStateList.valueOf(CYAN));
        timeline.addView(seek, new LinearLayout.LayoutParams(0, dp(this, 44), 1));
        timeline.addView(duration); panel.addView(timeline);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onStartTrackingTouch(SeekBar bar) { seeking = true; handler.removeCallbacks(hide); }
            public void onProgressChanged(SeekBar bar, int value, boolean user) { if (user) elapsed.setText(time(value)); }
            public void onStopTrackingTouch(SeekBar bar) { if (ready) video.seekTo(bar.getProgress()); seeking = false; scheduleHide(); }
        });
        LinearLayout actions = row(this); actions.setGravity(Gravity.CENTER);
        actions.addView(button(this, "−10", "Back ten seconds", () -> skip(-10000)), new LinearLayout.LayoutParams(0, dp(this, 48), 1));
        play = icon(android.R.drawable.ic_media_play, "Play", () -> {
            if (!ready) return;
            if (video.isPlaying()) video.pause(); else video.start();
            play.setImageResource(video.isPlaying() ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play);
        });
        play.setEnabled(false); actions.addView(play, new LinearLayout.LayoutParams(dp(this, 56), dp(this, 48)));
        actions.addView(button(this, "+10", "Forward ten seconds", () -> skip(10000)), new LinearLayout.LayoutParams(0, dp(this, 48), 1));
        actions.addView(icon(android.R.drawable.ic_menu_crop, "Fit or fill", () -> { fill = !fill; sizeVideo(); }));
        actions.addView(icon(android.R.drawable.ic_menu_always_landscape_portrait, "Rotate screen", () -> {
            setRequestedOrientation(getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE
                    ? ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT : ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
        }));
        panel.addView(actions);
        FrameLayout.LayoutParams bottom = new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM);
        bottom.setMargins(dp(this, 12), 0, dp(this, 12), dp(this, 16)); root.addView(panel, bottom);
        setContentView(root);
        video.setVideoURI(getIntent().getData());
        video.setOnPreparedListener(player -> {
            ready = true; width = player.getVideoWidth(); height = player.getVideoHeight();
            player.setOnVideoSizeChangedListener((p, w, h) -> { width = w; height = h; sizeVideo(); });
            player.setOnInfoListener((p, what, extra) -> {
                if (what == android.media.MediaPlayer.MEDIA_INFO_BUFFERING_START) loading.setVisibility(View.VISIBLE);
                if (what == android.media.MediaPlayer.MEDIA_INFO_BUFFERING_END) loading.setVisibility(View.GONE);
                return false;
            });
            loading.setVisibility(View.GONE); seek.setEnabled(true); play.setEnabled(true);
            seek.setMax(Math.max(1, video.getDuration())); duration.setText(time(video.getDuration()));
            video.seekTo(position); sizeVideo(); if (playingBeforePause) video.start(); scheduleHide();
        });
        video.setOnCompletionListener(player -> { showControls(true); handler.removeCallbacks(hide); });
        video.setOnErrorListener((player, what, extra) -> {
            ready = false; loading.setVisibility(View.GONE); play.setEnabled(false); seek.setEnabled(false);
            AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Playback unavailable")
                .setMessage("This video could not be played. Try another player.")
                .setPositiveButton("Open with", (d, w) -> external())
                .setNegativeButton("Close", (d, w) -> finish()).create();
            ViewerUi.showDialog(dialog, dark);
            return true;
        });
        handler.post(tick);
    }
    private void skip(int amount) { if (ready) video.seekTo(Math.max(0, Math.min(video.getDuration(), video.getCurrentPosition() + amount))); scheduleHide(); }
    private void sizeVideo() {
        if (width <= 0 || height <= 0 || stage.getWidth() == 0 || stage.getHeight() == 0) return;
        float x = (float) stage.getWidth() / width, y = (float) stage.getHeight() / height;
        float scale = fill ? Math.max(x, y) : Math.min(x, y);
        video.setLayoutParams(new FrameLayout.LayoutParams(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)), Gravity.CENTER));
    }
    private void scheduleHide() { handler.removeCallbacks(hide); if (ready && video.isPlaying()) handler.postDelayed(hide, 3500); }
    private void showControls(boolean show) {
        controls = show;
        for (View view : new View[]{header, panel}) {
            view.animate().cancel();
            if (show) view.setVisibility(View.VISIBLE);
            view.animate().alpha(show ? 1 : 0).setDuration(180).withEndAction(() -> {
                if (!controls) view.setVisibility(View.INVISIBLE);
            }).start();
        }
        if (show) scheduleHide();
    }
    private String time(int ms) {
        int seconds = Math.max(0, ms / 1000);
        return seconds >= 3600 ? String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60);
    }
    private void external() {
        try { startActivity(Intent.createChooser(new Intent(Intent.ACTION_VIEW).setDataAndType(getIntent().getData(), getIntent().getType())
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Open with")); }
        catch (android.content.ActivityNotFoundException error) { android.widget.Toast.makeText(this, "No other video player is installed", android.widget.Toast.LENGTH_SHORT).show(); }
    }
    @Override public void onConfigurationChanged(Configuration config) { super.onConfigurationChanged(config); stage.post(this::sizeVideo); }
    @Override protected void onPause() {
        if (ready) { position = video.getCurrentPosition(); playingBeforePause = video.isPlaying(); video.pause(); }
        handler.removeCallbacks(tick); handler.removeCallbacks(hide); super.onPause();
    }
    @Override protected void onResume() {
        super.onResume(); handler.removeCallbacks(tick); handler.post(tick);
        if (ready && playingBeforePause) { video.start(); scheduleHide(); }
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        state.putInt("position", ready ? video.getCurrentPosition() : position);
        state.putBoolean("playing", ready ? video.isPlaying() : playingBeforePause);
        state.putBoolean("fill", fill); super.onSaveInstanceState(state);
    }
    @Override protected void onDestroy() { handler.removeCallbacksAndMessages(null); video.stopPlayback(); super.onDestroy(); }
}
