package com.somesh.yrfileexplorer.media;

import android.content.Context;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.widget.BaseAdapter;
import android.widget.HorizontalScrollView;
import android.widget.ListView;

/** Gives the continuous page list a real scaled width and keeps the pinch point stable. */
final class PdfZoomView extends HorizontalScrollView {
    private static final float MAX_ZOOM = 4;
    final ListView document;
    private final ScaleGestureDetector pinch;
    private final Runnable onZoomSettled;
    private float zoom = 1;
    private int contentWidth;
    private int pendingScroll = -1;
    private boolean pinching;

    PdfZoomView(Context context, Runnable onZoomSettled) {
        super(context);
        this.onZoomSettled = onZoomSettled;
        document = new ListView(context) {
            @Override protected void onMeasure(int width, int height) {
                super.onMeasure(MeasureSpec.makeMeasureSpec(contentWidth, MeasureSpec.EXACTLY), height);
            }
        };
        addView(document, new LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.MATCH_PARENT));
        setHorizontalScrollBarEnabled(false);
        setOverScrollMode(OVER_SCROLL_NEVER);
        pinch = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override public boolean onScale(ScaleGestureDetector detector) {
                scaleAt(detector.getScaleFactor(), detector.getFocusX(), detector.getFocusY());
                return true;
            }
        });
        pinch.setQuickScaleEnabled(false);
        pinch.setStylusScaleEnabled(false);
    }

    int pageWidth() {
        return Math.max(1, contentWidth - document.getPaddingLeft() - document.getPaddingRight());
    }

    boolean isPinching() {
        return pinching;
    }

    @Override protected void onMeasure(int width, int height) {
        contentWidth = Math.max(1, Math.round(MeasureSpec.getSize(width) * zoom));
        super.onMeasure(width, height);
    }

    @Override protected void onLayout(boolean changed, int left, int top, int right, int bottom) {
        super.onLayout(changed, left, top, right, bottom);
        if (pendingScroll >= 0) {
            scrollTo(pendingScroll, 0);
            pendingScroll = -1;
        }
    }

    @Override public boolean dispatchTouchEvent(MotionEvent event) {
        int action = event.getActionMasked();
        if (!pinching && event.getPointerCount() > 1) {
            // End the one-finger scroll cleanly when a second finger takes over.
            MotionEvent cancel = MotionEvent.obtain(event);
            cancel.setAction(MotionEvent.ACTION_CANCEL);
            super.dispatchTouchEvent(cancel);
            cancel.recycle();
            pinching = true;
            getParent().requestDisallowInterceptTouchEvent(true);
        }
        pinch.onTouchEvent(event);
        if (!pinching) return super.dispatchTouchEvent(event);
        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            pinching = false;
            getParent().requestDisallowInterceptTouchEvent(false);
            post(onZoomSettled);
        }
        return true;
    }

    private void scaleAt(float factor, float x, float y) {
        if (getWidth() == 0 || document.getChildCount() == 0) return;
        float next = Math.max(1, Math.min(MAX_ZOOM, zoom * factor));
        if (next == zoom) return;

        int first = document.getFirstVisiblePosition();
        int index = first;
        View anchor = document.getChildAt(0);
        for (int i = 1; i < document.getChildCount(); i++) {
            if (anchor.getBottom() >= y) break;
            anchor = document.getChildAt(i);
            index = first + i;
        }
        int padding = document.getPaddingLeft() + document.getPaddingRight();
        int previousWidth = Math.max(1, document.getWidth() - padding);
        int targetWidth = Math.max(1, Math.round(getWidth() * next) - padding);
        float ratio = (float) targetWidth / previousWidth;
        int anchorTop = Math.round(y - (y - anchor.getTop()) * ratio);
        int leftPadding = document.getPaddingLeft();
        pendingScroll = Math.max(0, Math.round((getScrollX() + x - leftPadding) * ratio + leftPadding - x));
        zoom = next;
        requestLayout();
        if (document.getAdapter() instanceof BaseAdapter adapter) adapter.notifyDataSetChanged();
        document.setSelectionFromTop(index, anchorTop - document.getPaddingTop());
    }
}
