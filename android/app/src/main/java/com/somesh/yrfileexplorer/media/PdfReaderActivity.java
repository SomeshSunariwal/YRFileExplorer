package com.somesh.yrfileexplorer.media;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.drawable.Drawable;
import android.graphics.pdf.PdfRenderer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.print.PrintManager;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.PopupWindow;
import android.widget.ProgressBar;
import android.widget.TextView;
import com.somesh.yrfileexplorer.R;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import static com.somesh.yrfileexplorer.media.ViewerUi.CYAN;
import static com.somesh.yrfileexplorer.media.ViewerUi.button;
import static com.somesh.yrfileexplorer.media.ViewerUi.dp;
import static com.somesh.yrfileexplorer.media.ViewerUi.iconButton;
import static com.somesh.yrfileexplorer.media.ViewerUi.rounded;
import static com.somesh.yrfileexplorer.media.ViewerUi.row;
import static com.somesh.yrfileexplorer.media.ViewerUi.text;

/**
 * Offline paginated reader. All PDF parsing and rasterization stay off the UI
 * thread.
 */
public class PdfReaderActivity extends Activity {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final ExecutorService searchWorker = Executors.newSingleThreadExecutor();
    private final Handler searchHandler = new Handler(Looper.getMainLooper());
    private PdfRenderer renderer;
    private File temporary;
    private PdfZoomView zoomSurface;
    private android.widget.ListView document;
    private float[] pageRatios;
    private final java.util.Set<Integer> pendingPages = new java.util.HashSet<>();

    private record RenderedPage(Bitmap bitmap, int requestedWidth) {
    }

    private final android.util.LruCache<Integer, RenderedPage> pageCache = new android.util.LruCache<>(
            36 * 1024 * 1024) {
        @Override
        protected int sizeOf(Integer key, RenderedPage value) {
            return value.bitmap().getAllocationByteCount();
        }
    };
    private ProgressBar progress;
    private TextView counter;
    private LinearLayout findBar;
    private EditText findInput;
    private TextView findStatus;
    private View previousMatch, nextMatch;
    private List<PdfTextSearch.Match> matches = List.of();
    private final Map<Integer, List<PdfTextSearch.Match>> matchesByPage = new HashMap<>();
    private int matchIndex = -1;
    private volatile int searchGeneration;
    private int page, count;
    private boolean loading, privateDocument, dark;
    private String documentTitle;
    private int dialogSurface, dialogForeground, pageBackground;
    private volatile boolean closed;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        page = state == null ? 0 : state.getInt("page");
        privateDocument = getIntent().getBooleanExtra("privateSpace", false);
        if (privateDocument)
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        documentTitle = getIntent().getStringExtra("title");
        if (documentTitle == null || documentTitle.isBlank())
            documentTitle = "PDF document";
        dark = ViewerUi.isDark(this);
        int surface = dark ? 0xff333333 : Color.WHITE;
        int foreground = dark ? 0xffeef3f8 : 0xff1c2938;
        dialogSurface = surface;
        dialogForeground = foreground;
        pageBackground = dark ? 0xff292929 : 0xfff3f6fa;
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(pageBackground);
        int lightBars = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
        root.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override
            public void onViewAttachedToWindow(View view) {
                WindowInsetsController controller = view.getWindowInsetsController();
                if (controller != null) {
                    controller.setSystemBarsAppearance(pageBackground == 0xff292929 ? 0 : lightBars, lightBars);
                }
            }

            @Override
            public void onViewDetachedFromWindow(View view) {
            }
        });
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
        TextView title = text(this, documentTitle, 15, foreground);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        header.addView(title, new LinearLayout.LayoutParams(0, dp(this, 52), 1));
        android.widget.ImageButton more = pdfControl(R.drawable.ic_viewer_more, "PDF options", () -> {
        });
        more.setOnClickListener(this::showOptions);
        header.addView(more);
        root.addView(header);
        findBar = buildFindBar();
        root.addView(findBar);
        FrameLayout canvas = new FrameLayout(this);
        zoomSurface = new PdfZoomView(this, this::refreshVisiblePages);
        document = zoomSurface.document;
        document.setDivider(null);
        document.setPadding(dp(this, 12), dp(this, 12), dp(this, 12), dp(this, 64));
        document.setClipToPadding(false);
        document.setOnScrollListener(new android.widget.AbsListView.OnScrollListener() {
            public void onScrollStateChanged(android.widget.AbsListView view, int state) {
            }

            public void onScroll(android.widget.AbsListView view, int first, int visible, int total) {
                if (visible > 0 && count > 0) {
                    page = first;
                    updateCounter();
                }
            }
        });
        canvas.addView(zoomSurface, new FrameLayout.LayoutParams(-1, -1));
        progress = new ProgressBar(this);
        progress.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(CYAN));
        canvas.addView(progress, new FrameLayout.LayoutParams(dp(this, 36), dp(this, 36), Gravity.CENTER));
        root.addView(canvas, new LinearLayout.LayoutParams(-1, 0, 1));
        counter = button(this, "", "Go to page", this::jump);
        counter.setTextSize(13);
        counter.setMinHeight(dp(this, 36));
        counter.setPadding(dp(this, 18), 0, dp(this, 18), 0);
        counter.setBackground(rounded(this, surface, 20));
        counter.setElevation(dark ? 0 : dp(this, 3));
        FrameLayout.LayoutParams bottom = new FrameLayout.LayoutParams(-2, dp(this, 36),
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        bottom.bottomMargin = dp(this, 16);
        canvas.addView(counter, bottom);
        setContentView(root);
        setLoading(true);
        worker.execute(() -> {
            try {
                // Copy URI streams to a private seekable file; providers may return pipes.
                temporary = File.createTempFile("yr-pdf-", ".pdf", getCacheDir());
                try (InputStream input = getContentResolver().openInputStream(getIntent().getData());
                        FileOutputStream output = new FileOutputStream(temporary)) {
                    if (input == null)
                        throw new java.io.IOException("Cannot read this PDF");
                    byte[] buffer = new byte[65536];
                    int n;
                    while ((n = input.read(buffer)) != -1) {
                        if (closed)
                            return;
                        output.write(buffer, 0, n);
                    }
                }
                ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(temporary,
                        ParcelFileDescriptor.MODE_READ_ONLY);
                try {
                    renderer = new PdfRenderer(descriptor);
                } catch (Exception error) {
                    descriptor.close();
                    throw error;
                }
                int pages = renderer.getPageCount();
                if (pages == 0)
                    throw new java.io.IOException("This PDF contains no pages");
                float[] ratios = new float[pages];
                for (int i = 0; i < pages; i++) {
                    if (closed)
                        return;
                    try (PdfRenderer.Page metadata = renderer.openPage(i)) {
                        ratios[i] = (float) metadata.getHeight() / Math.max(1, metadata.getWidth());
                    }
                }
                runOnUiThread(() -> {
                    if (closed)
                        return;
                    count = pages;
                    pageRatios = ratios;
                    int restoredPage = Math.max(0, Math.min(page, count - 1));
                    document.setAdapter(new PageAdapter());
                    setLoading(false);
                    document.setSelection(restoredPage);
                    page = restoredPage;
                    updateCounter();
                });
            } catch (Exception error) {
                fail(error);
            }
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

    private void showOptions(View anchor) {
        LinearLayout menu = new LinearLayout(this);
        menu.setOrientation(LinearLayout.VERTICAL);
        // Match the Explorer action menu's corners, spacing, and light-mode elevation.
        menu.setPadding(0, dp(this, 8), 0, dp(this, 8));
        int margin = dp(this, 12);
        int availableWidth = anchor.getRootView().getWidth() - 2 * margin;
        int width = Math.min(dp(this, 224), Math.max(1, availableWidth));
        PopupWindow popup = new PopupWindow(menu, width, -2, true);
        popup.setBackgroundDrawable(rounded(this, dialogSurface, 12));
        popup.setElevation(dark ? 0 : dp(this, 3));
        popup.setOutsideTouchable(true);
        addOption(menu, popup, R.drawable.ic_pdf_find, "Find in page", this::showFind);
        if (!privateDocument) {
            addOption(menu, popup, R.drawable.ic_pdf_share, "Share", this::share);
            addOption(menu, popup, R.drawable.ic_pdf_print, "Print", this::print);
        }
        int offset = anchor.getLayoutDirection() == View.LAYOUT_DIRECTION_RTL ? margin : -margin;
        popup.showAsDropDown(anchor, offset, dp(this, 6), Gravity.END);
    }

    private void addOption(LinearLayout menu, PopupWindow popup, int icon, String label, Runnable action) {
        TextView item = text(this, label, 14, dialogForeground);
        item.setPaddingRelative(dp(this, 16), dp(this, 8), dp(this, 16), dp(this, 8));
        item.setMinimumHeight(dp(this, 44));
        Drawable glyph = getDrawable(icon).mutate();
        glyph.setTint(CYAN);
        glyph.setBounds(0, 0, dp(this, 20), dp(this, 20));
        item.setCompoundDrawablesRelative(glyph, null, null, null);
        item.setCompoundDrawablePadding(dp(this, 16));
        item.setBackground(new android.graphics.drawable.RippleDrawable(
                android.content.res.ColorStateList.valueOf(0x220ba5c6), null,
                new android.graphics.drawable.ColorDrawable(Color.WHITE)));
        item.setOnClickListener(view -> {
            popup.dismiss();
            action.run();
        });
        menu.addView(item, new LinearLayout.LayoutParams(-1, -2));
    }

    private LinearLayout buildFindBar() {
        LinearLayout bar = row(this);
        bar.setPadding(dp(this, 12), dp(this, 4), dp(this, 6), dp(this, 6));
        bar.setBackgroundColor(dialogSurface);
        bar.setVisibility(View.GONE);
        findInput = new EditText(this);
        findInput.setSingleLine(true);
        findInput.setHint("Find in PDF");
        findInput.setTextSize(14);
        findInput.setTextColor(dialogForeground);
        findInput.setHintTextColor(dialogSurface == Color.WHITE ? 0xff607184 : 0xffa9b5c2);
        findInput.setPadding(dp(this, 12), 0, dp(this, 10), 0);
        findInput.setBackground(rounded(this, pageBackground, 12));
        findInput.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        findInput.setOnEditorActionListener((view, action, event) -> {
            if (action != EditorInfo.IME_ACTION_SEARCH)
                return false;
            hideKeyboard();
            if (matchIndex < 0)
                scheduleFind(0);
            else
                selectMatch(matchIndex + 1);
            return true;
        });
        findInput.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                scheduleFind(200);
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
        bar.addView(findInput, new LinearLayout.LayoutParams(0, dp(this, 42), 1));
        findStatus = text(this, "", 11, dialogForeground);
        findStatus.setGravity(Gravity.CENTER);
        findStatus.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        bar.addView(findStatus, new LinearLayout.LayoutParams(dp(this, 60), dp(this, 42)));
        previousMatch = findControl(R.drawable.ic_viewer_back, "Previous match", () -> selectMatch(matchIndex - 1));
        nextMatch = findControl(R.drawable.ic_viewer_back, "Next match", () -> selectMatch(matchIndex + 1));
        nextMatch.setRotation(180);
        bar.addView(previousMatch);
        bar.addView(nextMatch);
        bar.addView(findControl(R.drawable.ic_music_close, "Close search", this::closeFind));
        return bar;
    }

    private View findControl(int drawable, String label, Runnable action) {
        android.widget.ImageButton control = iconButton(this, drawable, label, action);
        int padding = dp(this, 10);
        control.setPadding(padding, padding, padding, padding);
        control.setLayoutParams(new LinearLayout.LayoutParams(dp(this, 38), dp(this, 44)));
        return control;
    }

    private void showFind() {
        if (!PdfTextSearch.isAvailable()) {
            notice("Update Android to search text inside PDFs.");
            return;
        }
        if (loading || count == 0)
            return;
        findBar.setVisibility(View.VISIBLE);
        if (findInput.getText().length() == 0)
            updateFindStatus("");
        findInput.requestFocus();
        findInput.post(() -> getSystemService(InputMethodManager.class)
                .showSoftInput(findInput, InputMethodManager.SHOW_IMPLICIT));
    }

    private void hideKeyboard() {
        getSystemService(InputMethodManager.class).hideSoftInputFromWindow(findInput.getWindowToken(), 0);
    }

    private void closeFind() {
        hideKeyboard();
        findBar.setVisibility(View.GONE);
        findInput.setText("");
    }

    private void scheduleFind(long delay) {
        searchHandler.removeCallbacksAndMessages(null);
        int generation = ++searchGeneration;
        matches = List.of();
        matchesByPage.clear();
        matchIndex = -1;
        invalidateVisiblePages();
        String query = findInput.getText().toString().trim();
        updateFindStatus(query.isEmpty() ? "" : "Finding…");
        if (query.isEmpty() || closed || loading || count == 0)
            return;

        File source = temporary;
        searchHandler.postDelayed(() -> searchWorker.execute(() -> {
            if (closed || generation != searchGeneration)
                return;
            try {
                List<PdfTextSearch.Match> found = PdfTextSearch.find(source, query,
                        () -> closed || generation != searchGeneration);
                runOnUiThread(() -> {
                    if (closed || generation != searchGeneration)
                        return;
                    matches = found;
                    for (PdfTextSearch.Match match : matches) {
                        matchesByPage.computeIfAbsent(match.page(), ignored -> new java.util.ArrayList<>()).add(match);
                    }
                    if (matches.isEmpty()) {
                        updateFindStatus("No matches");
                    } else {
                        int first = 0;
                        while (first < matches.size() && matches.get(first).page() < page)
                            first++;
                        selectMatch(first);
                    }
                });
            } catch (Exception | LinkageError error) {
                runOnUiThread(() -> {
                    if (!closed && generation == searchGeneration)
                        updateFindStatus("Search unavailable");
                });
            }
        }), delay);
    }

    private void updateFindStatus(String status) {
        findStatus.setText(status);
        previousMatch.setEnabled(!matches.isEmpty());
        nextMatch.setEnabled(!matches.isEmpty());
        previousMatch.setAlpha(matches.isEmpty() ? .4f : 1);
        nextMatch.setAlpha(matches.isEmpty() ? .4f : 1);
    }

    private void selectMatch(int index) {
        if (matches.isEmpty())
            return;
        matchIndex = Math.floorMod(index, matches.size());
        PdfTextSearch.Match match = matches.get(matchIndex);
        RectF line = match.bounds().get(0);
        int width = zoomSurface.pageWidth();
        int top = Math.min(0, Math.round(document.getHeight() / 3f - line.top * width * pageRatios[match.page()]));
        document.setSelectionFromTop(match.page(), top);
        zoomSurface.scrollTo(Math.round(document.getPaddingLeft() + line.centerX() * width
                - zoomSurface.getWidth() / 2f), 0);
        updateFindStatus((matchIndex + 1) + " / " + matches.size());
        invalidateVisiblePages();
    }

    private void invalidateVisiblePages() {
        for (int i = 0; i < document.getChildCount(); i++)
            document.getChildAt(i).invalidate();
    }

    private void share() {
        if (privateDocument || getIntent().getData() == null)
            return;
        android.net.Uri uri = getIntent().getData();
        Intent send = new Intent(Intent.ACTION_SEND)
                .setType("application/pdf")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        send.setClipData(ClipData.newRawUri(documentTitle, uri));
        try {
            startActivity(Intent.createChooser(send, "Share PDF"));
        } catch (RuntimeException error) {
            notice("Could not open sharing.");
        }
    }

    private void print() {
        if (privateDocument || loading || count == 0)
            return;
        PrintManager manager = getSystemService(PrintManager.class);
        if (manager == null) {
            notice("Printing is unavailable on this device.");
            return;
        }
        try {
            manager.print(documentTitle, new PdfPrintAdapter(
                    getContentResolver(), getIntent().getData(), documentTitle, count), null);
        } catch (RuntimeException error) {
            notice("Could not open printing.");
        }
    }

    private void notice(String message) {
        android.widget.Toast.makeText(this, message, android.widget.Toast.LENGTH_SHORT).show();
    }

    private void setLoading(boolean value) {
        loading = value;
        progress.setVisibility(value ? android.view.View.VISIBLE : android.view.View.GONE);
        counter.setVisibility(!value && count > 0 ? View.VISIBLE : View.GONE);
        counter.setEnabled(!value && count > 0);
    }

    private void updateCounter() {
        counter.setText((page + 1) + " / " + count);
        counter.setContentDescription("Page " + (page + 1) + " of " + count + ". Go to page");
    }

    private void showPage(int target) {
        if (closed || loading || target < 0 || target >= count)
            return;
        document.setSelection(target);
        page = target;
        updateCounter();
    }

    private final class PageAdapter extends android.widget.BaseAdapter {
        public int getCount() {
            return count;
        }

        public Object getItem(int position) {
            return position;
        }

        public long getItemId(int position) {
            return position;
        }

        @Override
        public boolean hasStableIds() {
            return true;
        }

        public android.view.View getView(int position, android.view.View recycled, android.view.ViewGroup parent) {
            PageImage view = recycled instanceof PageImage image ? image : new PageImage();
            int width = zoomSurface.pageWidth();
            int height = Math.max(1, Math.round(width * pageRatios[position]));
            view.setLayoutParams(
                    new android.widget.AbsListView.LayoutParams(-1, height + dp(PdfReaderActivity.this, 12)));
            view.setPadding(0, 0, 0, dp(PdfReaderActivity.this, 12));
            view.setScaleType(ImageView.ScaleType.FIT_CENTER);
            view.setTag(position);
            view.setContentDescription("PDF page " + (position + 1) + " of " + count);
            RenderedPage cached = pageCache.get(position);
            view.setImageBitmap(cached == null ? null : cached.bitmap());
            int tier = renderWidth(width);
            if (cached == null || (!zoomSurface.isPinching() && cached.requestedWidth() < tier)) {
                requestPage(position, tier);
            }
            return view;
        }
    }

    private final class PageImage extends ImageView {
        private final Paint highlight = new Paint(Paint.ANTI_ALIAS_FLAG);

        PageImage() {
            super(PdfReaderActivity.this);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (!(getTag() instanceof Integer index) || getDrawable() == null)
                return;
            List<PdfTextSearch.Match> highlights = matchesByPage.get(index);
            if (highlights == null)
                return;
            PdfTextSearch.Match active = matchIndex < 0 ? null : matches.get(matchIndex);
            RectF image = new RectF(getDrawable().getBounds());
            getImageMatrix().mapRect(image);
            image.offset(getPaddingLeft(), getPaddingTop());
            for (PdfTextSearch.Match match : highlights) {
                highlight.setColor(match == active ? 0x99ffb22f : 0x66ffe172);
                for (RectF line : match.bounds()) {
                    canvas.drawRect(image.left + line.left * image.width(),
                            image.top + line.top * image.height(),
                            image.left + line.right * image.width(),
                            image.top + line.bottom * image.height(), highlight);
                }
            }
        }
    }

    private int renderWidth(int width) {
        return Math.min(2200, Math.max(600, (width + 255) / 256 * 256));
    }

    private void refreshVisiblePages() {
        if (closed || loading)
            return;
        int width = renderWidth(zoomSurface.pageWidth());
        for (int i = 0; i < document.getChildCount(); i++) {
            if (!(document.getChildAt(i).getTag() instanceof Integer target))
                continue;
            RenderedPage cached = pageCache.get(target);
            if (cached == null || cached.requestedWidth() < width)
                requestPage(target, width);
        }
    }

    private void requestPage(int target, int width) {
        if (closed || !pendingPages.add(target))
            return;
        worker.execute(() -> {
            if (closed)
                return;
            Bitmap bitmap = null;
            try (PdfRenderer.Page pdfPage = renderer.openPage(target)) {
                double scale = Math.min((double) width / pdfPage.getWidth(),
                        Math.sqrt(4_000_000.0 / ((double) pdfPage.getWidth() * pdfPage.getHeight())));
                bitmap = Bitmap.createBitmap(Math.max(1, (int) (pdfPage.getWidth() * scale)),
                        Math.max(1, (int) (pdfPage.getHeight() * scale)), Bitmap.Config.ARGB_8888);
                bitmap.eraseColor(Color.WHITE);
                pdfPage.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
                Bitmap ready = bitmap;
                runOnUiThread(() -> {
                    pendingPages.remove(target);
                    if (closed) {
                        ready.recycle();
                        return;
                    }
                    pageCache.put(target, new RenderedPage(ready, width));
                    for (int i = 0; i < document.getChildCount(); i++) {
                        android.view.View child = document.getChildAt(i);
                        if (child instanceof ImageView && Integer.valueOf(target).equals(child.getTag())) {
                            ((ImageView) child).setImageBitmap(ready);
                            int desired = renderWidth(zoomSurface.pageWidth());
                            if (!zoomSurface.isPinching() && desired > width)
                                requestPage(target, desired);
                        }
                    }
                });
            } catch (Exception error) {
                if (bitmap != null)
                    bitmap.recycle();
                runOnUiThread(() -> pendingPages.remove(target));
                fail(error);
            }
        });
    }

    private void jump() {
        if (loading || count == 0)
            return;
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
        label.setGravity(Gravity.CENTER);
        label.setTypeface(null, android.graphics.Typeface.BOLD);
        heading.addView(label, new FrameLayout.LayoutParams(-1, dp(this, 48)));
        TextView close = button(this, "×", "Close", dialog::dismiss);
        heading.addView(close, new FrameLayout.LayoutParams(dp(this, 48), dp(this, 48), Gravity.RIGHT));
        panel.addView(heading);
        android.view.View line = new android.view.View(this);
        line.setBackgroundColor(0xffcbdce5);
        panel.addView(line, new LinearLayout.LayoutParams(-1, dp(this, 1)));
        android.widget.ScrollView body = new android.widget.ScrollView(this);
        body.setFillViewport(true);
        LinearLayout fields = new LinearLayout(this);
        fields.setOrientation(LinearLayout.VERTICAL);
        fields.setPadding(dp(this, 18), dp(this, 16), dp(this, 18), dp(this, 16));
        TextView hint = text(this, "Page number · 1–" + count, 12, CYAN);
        fields.addView(hint);
        input.setTextColor(dialogForeground);
        input.setTextSize(14);
        input.setPadding(dp(this, 14), dp(this, 10), dp(this, 14), dp(this, 10));
        android.graphics.drawable.GradientDrawable field = rounded(this,
                dialogSurface == Color.WHITE ? 0xfff3f6fa : 0xff292929, 12);
        field.setStroke(dp(this, 1), 0xff8bcfdf);
        input.setBackground(field);
        LinearLayout.LayoutParams fieldLayout = new LinearLayout.LayoutParams(-1, dp(this, 48));
        fieldLayout.topMargin = dp(this, 8);
        fields.addView(input, fieldLayout);
        body.addView(fields);
        panel.addView(body);
        android.view.View divider = new android.view.View(this);
        divider.setBackgroundColor(0xffcbdce5);
        panel.addView(divider, new LinearLayout.LayoutParams(-1, dp(this, 1)));
        LinearLayout actions = row(this);
        actions.setGravity(Gravity.CENTER);
        actions.addView(button(this, "Cancel", "Cancel", dialog::dismiss),
                new LinearLayout.LayoutParams(dp(this, 96), dp(this, 48)));
        Runnable go = () -> {
            try {
                int value = Integer.parseInt(input.getText().toString().trim());
                if (value < 1 || value > count)
                    throw new NumberFormatException();
                showPage(value - 1);
                dialog.dismiss();
            } catch (NumberFormatException error) {
                input.setError("Use 1–" + count);
            }
        };
        actions.addView(button(this, "Go", "Go to page", go),
                new LinearLayout.LayoutParams(dp(this, 96), dp(this, 48)));
        panel.addView(actions);
        dialog.setContentView(panel);
        input.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_GO);
        input.setOnEditorActionListener((view, action, event) -> {
            if (action != android.view.inputmethod.EditorInfo.IME_ACTION_GO)
                return false;
            go.run();
            return true;
        });
        ViewerUi.showDialog(dialog, dark);
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
            int width = Math.min(dp(this, 400), getResources().getDisplayMetrics().widthPixels - dp(this, 32));
            dialog.getWindow().setLayout(width, -2);
            dialog.getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        }
    }

    private void external() {
        if (privateDocument)
            return;
        try {
            startActivity(Intent.createChooser(new Intent(Intent.ACTION_VIEW)
                    .setDataAndType(getIntent().getData(), "application/pdf")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), "Open with"));
        } catch (android.content.ActivityNotFoundException error) {
            android.widget.Toast.makeText(this, "No other PDF reader is installed", android.widget.Toast.LENGTH_SHORT)
                    .show();
        }
    }

    private void fail(Exception error) {
        runOnUiThread(() -> {
            if (closed || isFinishing())
                return;
            setLoading(false);
            AlertDialog.Builder dialog = new AlertDialog.Builder(this).setTitle("Cannot open PDF")
                    .setMessage(error instanceof SecurityException
                            ? "This PDF may require a password. Try another PDF reader."
                            : "The document could not be read. Try another reader or a different PDF.")
                    .setNegativeButton("Close", (d, w) -> finish());
            if (!privateDocument)
                dialog.setPositiveButton("Open with", (d, w) -> external());
            ViewerUi.showDialog(dialog.create(), dark);
        });
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putInt("page", page);
        super.onSaveInstanceState(state);
    }

    @Override
    protected void onDestroy() {
        closed = true;
        searchHandler.removeCallbacksAndMessages(null);
        searchWorker.shutdownNow();
        document.setAdapter(null);
        pageCache.evictAll();
        worker.execute(() -> {
            if (renderer != null)
                renderer.close();
            if (temporary != null)
                temporary.delete();
        });
        worker.shutdown();
        super.onDestroy();
    }

}
