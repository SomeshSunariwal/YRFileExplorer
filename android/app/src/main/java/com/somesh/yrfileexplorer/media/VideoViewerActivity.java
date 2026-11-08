package com.somesh.yrfileexplorer.media;

import android.animation.ValueAnimator;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.VideoView;
import com.somesh.yrfileexplorer.R;

import java.util.Locale;

import static com.somesh.yrfileexplorer.media.ViewerUi.CYAN;
import static com.somesh.yrfileexplorer.media.ViewerUi.dp;
import static com.somesh.yrfileexplorer.media.ViewerUi.iconButton;
import static com.somesh.yrfileexplorer.media.ViewerUi.row;
import static com.somesh.yrfileexplorer.media.ViewerUi.rounded;
import static com.somesh.yrfileexplorer.media.ViewerUi.text;

/**
 * Local video viewer with edge-to-edge playback and independently fading
 * controls.
 */
public class VideoViewerActivity extends Activity {
    private enum DisplayMode {
        FULL_SCREEN("Full Screen"), STRETCH("Stretch"), FIT("Fit");

        final String label;

        DisplayMode(String label) {
            this.label = label;
        }
    }

    private final Handler handler = new Handler(Looper.getMainLooper());
    private VideoView video;
    private FrameLayout stage;
    private LinearLayout header, panel;
    private ImageButton play, displayButton;
    private SeekBar seek;
    private TextView elapsed, duration;
    private ProgressBar loading;
    private boolean ready, seeking, controls = true, playingBeforePause, showingPause;
    private DisplayMode displayMode = DisplayMode.FIT;
    private PopupWindow displayMenu;
    private int position, width, height;
    private final Runnable hide = () -> showControls(false);
    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            if (ready) {
                int current = video.getCurrentPosition();
                if (!seeking) {
                    seek.setProgress(current);
                    elapsed.setText(time(current));
                }
                updatePlayButton();
            }
            handler.postDelayed(this, 300);
        }
    };

    private ImageButton control(int resource, String label, Runnable action) {
        ImageButton button = iconButton(this, resource, label, () -> {
            action.run();
            scheduleHide();
        });
        button.setColorFilter(Color.WHITE);
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x33ffffff),
                null, new ColorDrawable(Color.WHITE)));
        return button;
    }

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        boolean dark = ViewerUi.isDark(this);
        position = state == null ? 0 : state.getInt("position");
        playingBeforePause = state == null || state.getBoolean("playing", true);
        if (state != null) {
            int savedMode = state.getInt("displayMode", state.getBoolean("fill")
                    ? DisplayMode.FULL_SCREEN.ordinal() : DisplayMode.FIT.ordinal());
            displayMode = DisplayMode.values()[savedMode];
        }
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        Window window = getWindow();
        window.setBackgroundDrawable(new ColorDrawable(Color.BLACK));
        window.setDecorFitsSystemWindows(false);
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        window.setStatusBarContrastEnforced(false);
        window.setNavigationBarContrastEnforced(false);
        stage = new FrameLayout(this);
        stage.setBackgroundColor(Color.BLACK);
        stage.setClipChildren(true);
        stage.setOnClickListener(v -> showControls(!controls));
        stage.addOnLayoutChangeListener((v, l, t, r, b, ol, ot, or, ob) -> {
            if (r - l != or - ol || b - t != ob - ot)
                sizeVideo();
        });
        video = new VideoView(this) {
            @Override
            protected void onMeasure(int widthSpec, int heightSpec) {
                if (displayMode == DisplayMode.STRETCH
                        && MeasureSpec.getMode(widthSpec) == MeasureSpec.EXACTLY
                        && MeasureSpec.getMode(heightSpec) == MeasureSpec.EXACTLY) {
                    setMeasuredDimension(MeasureSpec.getSize(widthSpec), MeasureSpec.getSize(heightSpec));
                } else {
                    super.onMeasure(widthSpec, heightSpec);
                }
            }
        };
        video.setOnTouchListener((v, event) -> {
            if (event.getAction() == android.view.MotionEvent.ACTION_UP) {
                showControls(!controls);
                return true;
            }
            return true;
        });
        stage.addView(video, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));
        root.addView(stage, new FrameLayout.LayoutParams(-1, -1));
        loading = new ProgressBar(this);
        loading.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(CYAN));
        root.addView(loading, new FrameLayout.LayoutParams(dp(this, 36), dp(this, 36), Gravity.CENTER));

        header = buildHeader();
        panel = buildControls();
        root.addView(header, new FrameLayout.LayoutParams(-1, -2, Gravity.TOP));
        root.addView(panel, new FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM));
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            header.setPadding(safe.left + dp(this, 6), safe.top, safe.right + dp(this, 16), dp(this, 8));
            panel.setPadding(safe.left + dp(this, 16), dp(this, 22),
                    safe.right + dp(this, 16), safe.bottom + dp(this, 4));
            return insets;
        });
        setContentView(root);
        // Installing the content view initializes the window's decor and insets controller.
        WindowInsetsController systemBars = window.getInsetsController();
        if (systemBars != null) {
            systemBars.setSystemBarsAppearance(0, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        }
        video.setOnPreparedListener(player -> {
            ready = true;
            width = player.getVideoWidth();
            height = player.getVideoHeight();
            player.setOnVideoSizeChangedListener((p, w, h) -> {
                width = w;
                height = h;
                sizeVideo();
            });
            player.setOnInfoListener((p, what, extra) -> {
                if (what == android.media.MediaPlayer.MEDIA_INFO_BUFFERING_START)
                    loading.setVisibility(View.VISIBLE);
                if (what == android.media.MediaPlayer.MEDIA_INFO_BUFFERING_END)
                    loading.setVisibility(View.GONE);
                return false;
            });
            loading.setVisibility(View.GONE);
            seek.setEnabled(true);
            play.setEnabled(true);
            seek.setMax(Math.max(1, video.getDuration()));
            duration.setText(time(video.getDuration()));
            video.seekTo(position);
            sizeVideo();
            if (playingBeforePause)
                video.start();
            updatePlayButton();
            scheduleHide();
        });
        video.setOnCompletionListener(player -> {
            updatePlayButton();
            showControls(true);
        });
        video.setOnErrorListener((player, what, extra) -> {
            ready = false;
            loading.setVisibility(View.GONE);
            play.setEnabled(false);
            seek.setEnabled(false);
            updatePlayButton();
            showControls(true);
            AlertDialog dialog = new AlertDialog.Builder(this).setTitle("Playback unavailable")
                    .setMessage("This video could not be played. Try another player.")
                    .setPositiveButton("Open with", (d, w) -> external())
                    .setNegativeButton("Close", (d, w) -> finish()).create();
            ViewerUi.showDialog(dialog, dark);
            return true;
        });
        video.setVideoURI(getIntent().getData());
    }

    private LinearLayout buildHeader() {
        LinearLayout bar = row(this);
        bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[] { 0xc9000000, 0x99000000, Color.TRANSPARENT }));
        bar.addView(control(R.drawable.ic_viewer_back, "Back", this::finish));
        TextView title = text(this, getIntent().getStringExtra("title"), 14, Color.WHITE);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        bar.addView(title, new LinearLayout.LayoutParams(0, dp(this, 48), 1));
        return bar;
    }

    private LinearLayout buildControls() {
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.VERTICAL);
        bar.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[] { Color.TRANSPARENT, 0xb8000000, 0xe6000000 }));
        LinearLayout timeline = row(this);
        elapsed = text(this, "00:00", 11, Color.WHITE);
        duration = text(this, "00:00", 11, Color.WHITE);
        elapsed.setSingleLine(true);
        duration.setSingleLine(true);
        timeline.addView(elapsed);
        seek = new SeekBar(this);
        seek.setEnabled(false);
        seek.setContentDescription("Playback position");
        seek.setProgressTintList(ColorStateList.valueOf(CYAN));
        seek.setProgressBackgroundTintList(ColorStateList.valueOf(0x6bffffff));
        seek.setThumbTintList(ColorStateList.valueOf(Color.WHITE));
        seek.setPadding(dp(this, 10), 0, dp(this, 10), 0);
        timeline.addView(seek, new LinearLayout.LayoutParams(0, dp(this, 40), 1));
        timeline.addView(duration);
        bar.addView(timeline);
        seek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            public void onStartTrackingTouch(SeekBar bar) {
                seeking = true;
                handler.removeCallbacks(hide);
            }

            public void onProgressChanged(SeekBar bar, int value, boolean user) {
                if (user)
                    elapsed.setText(time(value));
            }

            public void onStopTrackingTouch(SeekBar bar) {
                if (ready)
                    video.seekTo(bar.getProgress());
                seeking = false;
                scheduleHide();
            }
        });
        LinearLayout actions = row(this);
        actions.addView(control(R.drawable.ic_video_rotate, "Rotate screen", this::rotate), controlSlot());
        actions.addView(control(R.drawable.ic_video_replay_10, "Back ten seconds", () -> skip(-10000)), controlSlot());
        play = control(R.drawable.ic_music_play, "Play", () -> {
            if (!ready)
                return;
            if (video.isPlaying())
                video.pause();
            else
                video.start();
            updatePlayButton();
        });
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(0x30000000);
        circle.setStroke(dp(this, 1.5f), Color.WHITE);
        play.setBackground(new RippleDrawable(ColorStateList.valueOf(0x40ffffff), circle, null));
        play.setEnabled(false);
        FrameLayout center = new FrameLayout(this);
        center.addView(play, new FrameLayout.LayoutParams(dp(this, 48), dp(this, 48), Gravity.CENTER));
        actions.addView(center, controlSlot());
        actions.addView(control(R.drawable.ic_video_forward_10, "Forward ten seconds", () -> skip(10000)),
                controlSlot());
        displayButton = control(R.drawable.ic_video_display, "Video display mode", this::showDisplayModes);
        updateDisplayButton();
        actions.addView(displayButton, controlSlot());
        bar.addView(actions);
        return bar;
    }

    private LinearLayout.LayoutParams controlSlot() {
        return new LinearLayout.LayoutParams(0, dp(this, 52), 1);
    }

    private void rotate() {
        setRequestedOrientation(getResources().getConfiguration().orientation == Configuration.ORIENTATION_LANDSCAPE
                ? ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                : ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }

    private void updateDisplayButton() {
        displayButton.setColorFilter(displayMode == DisplayMode.FIT ? Color.WHITE : CYAN);
        displayButton.setContentDescription("Video display mode, " + displayMode.label);
    }

    private void showDisplayModes() {
        if (displayMenu != null) return;
        boolean dark = ViewerUi.isDark(this);
        LinearLayout options = new LinearLayout(this);
        options.setOrientation(LinearLayout.VERTICAL);
        options.setPadding(0, dp(this, 6), 0, dp(this, 6));
        int rowHeight = dp(this, 48);
        DisplayMode[] modes = DisplayMode.values();
        int popupHeight = modes.length * rowHeight + options.getPaddingTop() + options.getPaddingBottom();
        PopupWindow popup = new PopupWindow(options, dp(this, 164), popupHeight, true);
        popup.setBackgroundDrawable(rounded(this, dark ? 0xff333333 : Color.WHITE, 12));
        popup.setElevation(dark ? 0 : dp(this, 4));
        popup.setOutsideTouchable(true);
        for (DisplayMode mode : modes) {
            boolean selected = displayMode == mode;
            TextView option = text(this, mode.label, 14, selected ? CYAN : dark ? 0xffeef3f8 : 0xff1c2938);
            option.setSelected(selected);
            option.setPaddingRelative(dp(this, 16), 0, dp(this, 16), 0);
            option.setBackground(new RippleDrawable(ColorStateList.valueOf(0x220ba5c6), null,
                    new ColorDrawable(Color.WHITE)));
            option.setOnClickListener(view -> {
                displayMode = mode;
                updateDisplayButton();
                sizeVideo();
                popup.dismiss();
            });
            options.addView(option, new LinearLayout.LayoutParams(-1, rowHeight));
        }
        popup.setOnDismissListener(() -> {
            displayMenu = null;
            scheduleHide();
        });
        displayMenu = popup;
        int gap = dp(this, 6);
        popup.showAsDropDown(displayButton, 0, -displayButton.getHeight() - popupHeight - gap, Gravity.END);
    }

    private void updatePlayButton() {
        boolean playing = ready && video.isPlaying();
        if (playing == showingPause)
            return;
        showingPause = playing;
        play.setImageResource(playing ? R.drawable.ic_music_pause : R.drawable.ic_music_play);
        play.setContentDescription(playing ? "Pause" : "Play");
    }

    private void skip(int amount) {
        if (ready) {
            int target = Math.max(0, Math.min(video.getDuration(), video.getCurrentPosition() + amount));
            video.seekTo(target);
        }
    }

    private void sizeVideo() {
        if (width <= 0 || height <= 0 || stage.getWidth() == 0 || stage.getHeight() == 0)
            return;
        int targetWidth = stage.getWidth();
        int targetHeight = stage.getHeight();
        if (displayMode != DisplayMode.STRETCH) {
            float x = (float) targetWidth / width, y = (float) targetHeight / height;
            float scale = displayMode == DisplayMode.FULL_SCREEN ? Math.max(x, y) : Math.min(x, y);
            targetWidth = Math.max(1, Math.round(width * scale));
            targetHeight = Math.max(1, Math.round(height * scale));
        }
        video.setLayoutParams(new FrameLayout.LayoutParams(targetWidth, targetHeight, Gravity.CENTER));
    }

    private void scheduleHide() {
        handler.removeCallbacks(hide);
        if (displayMenu == null && ready && controls && !seeking && video.isPlaying())
            handler.postDelayed(hide, 3500);
    }

    private void showControls(boolean show) {
        controls = show;
        for (View view : new View[] { header, panel }) {
            view.animate().cancel();
            if (show)
                view.setVisibility(View.VISIBLE);
            view.animate().alpha(show ? 1 : 0).setDuration(ValueAnimator.areAnimatorsEnabled() ? 180 : 0)
                    .withEndAction(() -> {
                        if (!controls)
                            view.setVisibility(View.INVISIBLE);
                    }).start();
        }
        scheduleHide();
    }

    private String time(int ms) {
        int seconds = Math.max(0, ms / 1000);
        return seconds >= 3600
                ? String.format(Locale.ROOT, "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60);
    }

    private void external() {
        try {
            startActivity(Intent.createChooser(
                    new Intent(Intent.ACTION_VIEW).setDataAndType(getIntent().getData(), getIntent().getType())
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    "Open with"));
        } catch (android.content.ActivityNotFoundException error) {
            android.widget.Toast.makeText(this, "No other video player is installed", android.widget.Toast.LENGTH_SHORT)
                    .show();
        }
    }

    @Override
    public void onConfigurationChanged(Configuration config) {
        super.onConfigurationChanged(config);
        stage.post(this::sizeVideo);
    }

    @Override
    protected void onPause() {
        if (displayMenu != null) displayMenu.dismiss();
        if (ready) {
            position = video.getCurrentPosition();
            playingBeforePause = video.isPlaying();
            video.pause();
        }
        handler.removeCallbacks(tick);
        handler.removeCallbacks(hide);
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.removeCallbacks(tick);
        handler.post(tick);
        if (ready && playingBeforePause) {
            video.start();
            scheduleHide();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putInt("position", ready ? video.getCurrentPosition() : position);
        state.putBoolean("playing", ready ? video.isPlaying() : playingBeforePause);
        state.putInt("displayMode", displayMode.ordinal());
        super.onSaveInstanceState(state);
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        video.stopPlayback();
        super.onDestroy();
    }
}
