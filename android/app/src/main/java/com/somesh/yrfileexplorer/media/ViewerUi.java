package com.somesh.yrfileexplorer.media;

import android.app.Activity;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.ImageButton;
import android.widget.ImageView;

/** Small shared native viewer controls; dimensions are density independent. */
public final class ViewerUi {
    public static final int CYAN = 0xff0ba5c6;
    private ViewerUi() {}
    public static int dp(Activity activity, float value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }
    public static GradientDrawable rounded(Activity activity, int color, int radius) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(dp(activity, radius));
        return drawable;
    }
    public static TextView text(Activity activity, String value, int size, int color) {
        TextView view = new TextView(activity);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setGravity(Gravity.CENTER_VERTICAL);
        return view;
    }
    public static TextView button(Activity activity, String value, String label, Runnable action) {
        TextView view = text(activity, value, 16, CYAN);
        view.setGravity(Gravity.CENTER);
        view.setContentDescription(label);
        view.setMinWidth(dp(activity, 48));
        view.setMinHeight(dp(activity, 48));
        view.setFocusable(true);
        view.setOnClickListener(v -> action.run());
        return view;
    }
    public static LinearLayout row(Activity activity) {
        LinearLayout view = new LinearLayout(activity);
        view.setGravity(Gravity.CENTER_VERTICAL);
        return view;
    }
    public static ImageButton iconButton(Activity activity, int drawable, String label, Runnable action) {
        ImageButton view = new ImageButton(activity);
        view.setImageResource(drawable);
        view.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        view.setColorFilter(CYAN);
        view.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        int padding = dp(activity, 12);
        view.setPadding(padding, padding, padding, padding);
        view.setContentDescription(label);
        view.setLayoutParams(new LinearLayout.LayoutParams(dp(activity, 48), dp(activity, 48)));
        view.setOnClickListener(v -> action.run());
        return view;
    }
}
