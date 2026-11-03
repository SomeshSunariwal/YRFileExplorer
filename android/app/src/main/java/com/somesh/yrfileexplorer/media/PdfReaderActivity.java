package com.somesh.yrfileexplorer.media;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.pdf.PdfRenderer;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;
import android.view.Gravity;
import android.view.WindowInsets;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import com.somesh.yrfileexplorer.R;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import static com.somesh.yrfileexplorer.media.ViewerUi.*;

/** Offline paginated reader. All PDF parsing and rasterization stay off the UI thread. */
public class PdfReaderActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private PdfRenderer renderer;
    private File temporary;
    private android.widget.ListView document;
    private float[] pageRatios;
    private final java.util.Set<Integer> pendingPages = new java.util.HashSet<>();
    private final android.util.LruCache<Integer, Bitmap> pageCache = new android.util.LruCache<Integer, Bitmap>(24 * 1024 * 1024) {
        @Override protected int sizeOf(Integer key, Bitmap value) { return value.getAllocationByteCount(); }
    };
    private ProgressBar progress;
    private TextView counter;
    private android.view.View previous, next;
    private int page, count;
    private boolean loading;
    private int dialogSurface, dialogForeground;
    private volatile boolean closed;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        page = state == null ? 0 : state.getInt("page");
        boolean dark = false;
        try { dark = new org.json.JSONObject(getSharedPreferences("yr_preferences", MODE_PRIVATE)
                .getString("settings", "{}")).optBoolean("dark", false); }
        catch (org.json.JSONException ignored) {}
        int surface = dark ? 0xff333333 : Color.WHITE;
        int foreground = dark ? 0xffeef3f8 : 0xff1c2938;
        dialogSurface = surface; dialogForeground = foreground;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(dark ? 0xff292929 : 0xfff3f6fa);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return insets;
        });
        LinearLayout header = row(this);
        header.setBackgroundColor(surface);
        header.addView(pdfControl(R.drawable.ic_viewer_back, "Back", this::finish));
        ImageView pdfIcon = new ImageView(this);
        pdfIcon.setImageResource(R.drawable.ic_pdf);
        pdfIcon.setContentDescription("PDF document");
        LinearLayout.LayoutParams iconLayout = new LinearLayout.LayoutParams(dp(this, 24), dp(this, 28));
        iconLayout.setMargins(0, 0, dp(this, 10), 0);
        header.addView(pdfIcon, iconLayout);
        TextView title = text(this, getIntent().getStringExtra("title"), 15, foreground);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(this, 52), 1));
        header.addView(pdfControl(R.drawable.ic_viewer_open, "Open with", this::external));
        root.addView(header);
        FrameLayout canvas = new FrameLayout(this);
        document = new android.widget.ListView(this);
        document.setDivider(null);
        // Keep the last page readable above the floating controls without an opaque footer.
        document.setPadding(dp(this, 12), dp(this, 12), dp(this, 12), dp(this, 84));
        document.setClipToPadding(false);
        document.setOnScrollListener(new android.widget.AbsListView.OnScrollListener() {
            public void onScrollStateChanged(android.widget.AbsListView view, int state) {}
            public void onScroll(android.widget.AbsListView view, int first, int visible, int total) {
                if (visible > 0 && count > 0) { page = first; updateCounter(); }
            }
        });
        android.widget.HorizontalScrollView zoomSurface = new android.widget.HorizontalScrollView(this) {
            private float zoom = 1;
            private final android.view.ScaleGestureDetector pinch = new android.view.ScaleGestureDetector(PdfReaderActivity.this,
                    new android.view.ScaleGestureDetector.SimpleOnScaleGestureListener() {
                @Override public boolean onScale(android.view.ScaleGestureDetector detector) {
                    float previousZoom = zoom;
                    zoom = Math.max(1, Math.min(3, zoom * detector.getScaleFactor()));
                    int first = document.getFirstVisiblePosition();
                    int top = document.getChildCount() == 0 ? 0 : document.getChildAt(0).getTop();
                    document.getLayoutParams().width = Math.round(getWidth() * zoom);
                    document.requestLayout();
                    if (document.getAdapter() != null) ((PageAdapter) document.getAdapter()).notifyDataSetChanged();
                    document.setSelectionFromTop(first, Math.round(top * zoom / previousZoom));
                    return true;
                }
            });
            @Override public boolean dispatchTouchEvent(android.view.MotionEvent event) {
                pinch.onTouchEvent(event);
                if (event.getPointerCount() > 1 || pinch.isInProgress()) return true;
                return super.dispatchTouchEvent(event);
            }
        };
        zoomSurface.setFillViewport(true);
        zoomSurface.addView(document, new android.widget.HorizontalScrollView.LayoutParams(
                getResources().getDisplayMetrics().widthPixels, -1));
        canvas.addView(zoomSurface, new FrameLayout.LayoutParams(-1, -1));
        progress = new ProgressBar(this);
        progress.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(CYAN));
        canvas.addView(progress, new FrameLayout.LayoutParams(dp(this, 36), dp(this, 36), Gravity.CENTER));
        root.addView(canvas, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout navigation = row(this);
        navigation.setGravity(Gravity.CENTER);
        navigation.setBackground(rounded(this, surface, 28));
        navigation.setElevation(dp(this, 4));
        previous = pdfControl(R.drawable.ic_viewer_back, "Previous page", () -> showPage(page - 1));
        next = pdfControl(R.drawable.ic_viewer_back, "Next page", () -> showPage(page + 1));
        next.setRotation(180);
        counter = button(this, "Opening PDF…", "Go to page", this::jump);
        counter.setTextSize(13);
        navigation.addView(previous);
        navigation.addView(counter, new LinearLayout.LayoutParams(0, dp(this, 48), 1));
        navigation.addView(next);
        FrameLayout.LayoutParams bottom = new FrameLayout.LayoutParams(-1, dp(this, 48), Gravity.BOTTOM);
        bottom.setMargins(dp(this, 16), 0, dp(this, 16), dp(this, 16));
        canvas.addView(navigation, bottom);
        setContentView(root);
        setLoading(true);
        worker.execute(() -> {
            try {
                // Copy URI streams to a private seekable file; providers may return pipes.
                temporary = File.createTempFile("yr-pdf-", ".pdf", getCacheDir());
                try (InputStream input = getContentResolver().openInputStream(getIntent().getData());
                     FileOutputStream output = new FileOutputStream(temporary)) {
                    if (input == null) throw new java.io.IOException("Cannot read this PDF");
                    byte[] buffer = new byte[65536];
                    int n;
                    while ((n = input.read(buffer)) != -1) {
                        if (closed) return;
                        output.write(buffer, 0, n);
                    }
                }
                ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(temporary, ParcelFileDescriptor.MODE_READ_ONLY);
                try { renderer = new PdfRenderer(descriptor); }
                catch (Exception error) { descriptor.close(); throw error; }
                int pages = renderer.getPageCount();
                if (pages == 0) throw new java.io.IOException("This PDF contains no pages");
                float[] ratios = new float[pages];
                for (int i = 0; i < pages; i++) {
                    if (closed) return;
                    try (PdfRenderer.Page metadata = renderer.openPage(i)) {
                        ratios[i] = (float) metadata.getHeight() / Math.max(1, metadata.getWidth());
                    }
                }
                runOnUiThread(() -> {
                    if (closed) return;
                    count = pages; pageRatios = ratios;
                    int restoredPage = Math.max(0, Math.min(page, count - 1));
                    document.setAdapter(new PageAdapter());
                    setLoading(false);
                    document.setSelection(restoredPage);
                    page = restoredPage; updateCounter();
                });
            } catch (Exception error) { fail(error); }
        });
    }

    private android.widget.ImageButton pdfControl(int drawable, String label, Runnable action) {
        android.widget.ImageButton control = iconButton(this, drawable, label, action);
        control.setScaleType(ImageView.ScaleType.FIT_CENTER);
        // 22dp artwork inside the unchanged 48dp touch target.
        int padding = dp(this, 13);
        control.setPadding(padding, padding, padding, padding);
        return control;
    }

    private void setLoading(boolean value) {
        loading = value;
        progress.setVisibility(value ? android.view.View.VISIBLE : android.view.View.GONE);
        previous.setEnabled(!value && page > 0);
        next.setEnabled(!value && page + 1 < count);
        counter.setEnabled(!value && count > 0);
    }
    private void updateCounter() {
        counter.setText((page + 1) + " / " + count);
        previous.setEnabled(!loading && page > 0);
        next.setEnabled(!loading && page + 1 < count);
    }
    private void showPage(int target) {
        if (closed || loading || target < 0 || target >= count) return;
        document.setSelection(target);
        page = target; updateCounter();
    }
    private final class PageAdapter extends android.widget.BaseAdapter {
        public int getCount() { return count; }
        public Object getItem(int position) { return position; }
        public long getItemId(int position) { return position; }
        @Override public boolean hasStableIds() { return true; }
        public android.view.View getView(int position, android.view.View recycled, android.view.ViewGroup parent) {
            ImageView view = recycled instanceof ImageView ? (ImageView) recycled : new ImageView(PdfReaderActivity.this);
            int width = Math.max(1, parent.getWidth() - parent.getPaddingLeft() - parent.getPaddingRight());
            if (width <= 1) width = getResources().getDisplayMetrics().widthPixels - dp(PdfReaderActivity.this, 24);
            int height = Math.max(1, Math.round(width * pageRatios[position]));
            view.setLayoutParams(new android.widget.AbsListView.LayoutParams(-1, height + dp(PdfReaderActivity.this, 12)));
            view.setPadding(0, 0, 0, dp(PdfReaderActivity.this, 12));
            view.setScaleType(ImageView.ScaleType.FIT_CENTER);
            view.setTag(position);
            view.setContentDescription("PDF page " + (position + 1) + " of " + count);
            Bitmap cached = pageCache.get(position);
            view.setImageBitmap(cached);
            if (cached == null) requestPage(position, width);
            return view;
        }
    }
    private void requestPage(int target, int viewportWidth) {
        if (closed || !pendingPages.add(target)) return;
        worker.execute(() -> {
            if (closed) return;
            Bitmap bitmap = null;
            try (PdfRenderer.Page pdfPage = renderer.openPage(target)) {
                int width = Math.min(1400, Math.max(600, viewportWidth));
                double scale = Math.min((double) width / pdfPage.getWidth(),
                        Math.sqrt(3_000_000.0 / ((double) pdfPage.getWidth() * pdfPage.getHeight())));
                bitmap = Bitmap.createBitmap(Math.max(1, (int) (pdfPage.getWidth() * scale)),
                        Math.max(1, (int) (pdfPage.getHeight() * scale)), Bitmap.Config.ARGB_8888);
                bitmap.eraseColor(Color.WHITE);
                pdfPage.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                Bitmap ready = bitmap;
                runOnUiThread(() -> {
                    pendingPages.remove(target);
                    if (closed) { ready.recycle(); return; }
                    pageCache.put(target, ready);
                    for (int i = 0; i < document.getChildCount(); i++) {
                        android.view.View child = document.getChildAt(i);
                        if (child instanceof ImageView && Integer.valueOf(target).equals(child.getTag()))
                            ((ImageView) child).setImageBitmap(ready);
                    }
                });
            } catch (Exception error) {
                if (bitmap != null) bitmap.recycle();
                runOnUiThread(() -> pendingPages.remove(target));
                fail(error);
            }
        });
    }
    private void jump() {
        if (loading || count == 0) return;
        EditText input = new EditText(this);
        input.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        input.setText(Integer.toString(page + 1));
        input.selectAll();
        android.app.Dialog dialog = new android.app.Dialog(this);
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setBackground(rounded(this, dialogSurface, 10));
        FrameLayout heading = new FrameLayout(this);
        TextView label = text(this, "Go to page", 16, dialogForeground);
        label.setGravity(Gravity.CENTER); label.setTypeface(null, android.graphics.Typeface.BOLD);
        heading.addView(label, new FrameLayout.LayoutParams(-1, dp(this, 48)));
        TextView close = button(this, "×", "Close", dialog::dismiss);
        heading.addView(close, new FrameLayout.LayoutParams(dp(this, 48), dp(this, 48), Gravity.RIGHT));
        panel.addView(heading);
        android.view.View line = new android.view.View(this); line.setBackgroundColor(0xffcbdce5);
        panel.addView(line, new LinearLayout.LayoutParams(-1, dp(this, 1)));
        android.widget.ScrollView body = new android.widget.ScrollView(this);
        body.setFillViewport(true);
        LinearLayout fields = new LinearLayout(this); fields.setOrientation(LinearLayout.VERTICAL);
        fields.setPadding(dp(this, 18), dp(this, 16), dp(this, 18), dp(this, 16));
        TextView hint = text(this, "Page number · 1–" + count, 12, CYAN);
        fields.addView(hint);
        input.setTextColor(dialogForeground); input.setTextSize(14);
        input.setPadding(dp(this, 14), dp(this, 10), dp(this, 14), dp(this, 10));
        android.graphics.drawable.GradientDrawable field = rounded(this,
                dialogSurface == Color.WHITE ? 0xfff3f6fa : 0xff292929, 12);
        field.setStroke(dp(this, 1), 0xff8bcfdf); input.setBackground(field);
        LinearLayout.LayoutParams fieldLayout = new LinearLayout.LayoutParams(-1, dp(this, 48));
        fieldLayout.topMargin = dp(this, 8); fields.addView(input, fieldLayout);
        body.addView(fields); panel.addView(body);
        android.view.View divider = new android.view.View(this); divider.setBackgroundColor(0xffcbdce5);
        panel.addView(divider, new LinearLayout.LayoutParams(-1, dp(this, 1)));
        LinearLayout actions = row(this); actions.setGravity(Gravity.CENTER);
        actions.addView(button(this, "Cancel", "Cancel", dialog::dismiss), new LinearLayout.LayoutParams(dp(this, 96), dp(this, 48)));
        Runnable go = () -> {
            try {
                int value = Integer.parseInt(input.getText().toString().trim());
                if (value < 1 || value > count) throw new NumberFormatException();
                showPage(value - 1); dialog.dismiss();
            } catch (NumberFormatException error) { input.setError("Use 1–" + count); }
        };
        actions.addView(button(this, "Go", "Go to page", go), new LinearLayout.LayoutParams(dp(this, 96), dp(this, 48)));
        panel.addView(actions); dialog.setContentView(panel);
        input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_GO);
        input.setOnEditorActionListener((view, action, event) -> {
            if (action != android.view.inputmethod.EditorInfo.IME_ACTION_GO) return false;
            go.run(); return true;
        });
        dialog.show();
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
            int width = Math.min(dp(this, 400), getResources().getDisplayMetrics().widthPixels - dp(this, 32));
            dialog.getWindow().setLayout(width, -2);
            dialog.getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        }
    }
    private void external() {
        try { startActivity(Intent.createChooser(new Intent(Intent.ACTION_VIEW)
                .setDataAndType(getIntent().getData(), "application/pdf")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Open with")); }
        catch (android.content.ActivityNotFoundException error) {
            android.widget.Toast.makeText(this, "No other PDF reader is installed", android.widget.Toast.LENGTH_SHORT).show();
        }
    }
    private void fail(Exception error) {
        runOnUiThread(() -> {
            if (closed || isFinishing()) return;
            setLoading(false);
            new AlertDialog.Builder(this).setTitle("Cannot open PDF")
                    .setMessage(error instanceof SecurityException
                        ? "This PDF may require a password. Try another PDF reader."
                        : "The document could not be read. Try another reader or a different PDF.")
                    .setPositiveButton("Open with", (d, w) -> external())
                    .setNegativeButton("Close", (d, w) -> finish()).show();
        });
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        state.putInt("page", page); super.onSaveInstanceState(state);
    }
    @Override protected void onDestroy() {
        closed = true;
        document.setAdapter(null);
        pageCache.evictAll();
        worker.execute(() -> {
            if (renderer != null) renderer.close();
            if (temporary != null) temporary.delete();
        });
        worker.shutdown();
        super.onDestroy();
    }

}
