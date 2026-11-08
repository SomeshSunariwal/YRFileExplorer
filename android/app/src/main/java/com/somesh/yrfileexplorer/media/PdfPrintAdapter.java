package com.somesh.yrfileexplorer.media;

import android.content.ContentResolver;
import android.net.Uri;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintDocumentInfo;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Passes the original PDF to the spooler to preserve text and vector artwork.
 */
final class PdfPrintAdapter extends PrintDocumentAdapter {
    private final ContentResolver resolver;
    private final Uri source;
    private final PrintDocumentInfo info;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    PdfPrintAdapter(ContentResolver resolver, Uri source, String name, int pages) {
        this.resolver = resolver;
        this.source = source;
        info = new PrintDocumentInfo.Builder(name)
                .setContentType(PrintDocumentInfo.CONTENT_TYPE_DOCUMENT)
                .setPageCount(pages)
                .build();
    }

    @Override
    public void onLayout(PrintAttributes oldAttributes, PrintAttributes newAttributes,
            CancellationSignal cancellation, LayoutResultCallback callback,
            Bundle extras) {
        if (cancellation.isCanceled()) {
            callback.onLayoutCancelled();
        } else {
            callback.onLayoutFinished(info, false);
        }
    }

    @Override
    public void onWrite(PageRange[] pages, ParcelFileDescriptor destination,
            CancellationSignal cancellation, WriteResultCallback callback) {
        worker.execute(() -> {
            try (OutputStream out = new ParcelFileDescriptor.AutoCloseOutputStream(destination);
                    InputStream in = resolver.openInputStream(source)) {
                if (in == null)
                    throw new IOException("Missing PDF");
                byte[] buffer = new byte[64 * 1024];
                int read;
                while (!cancellation.isCanceled() && (read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            } catch (IOException | SecurityException error) {
                if (cancellation.isCanceled())
                    callback.onWriteCancelled();
                else
                    callback.onWriteFailed("Could not read the PDF");
                return;
            }
            if (cancellation.isCanceled()) {
                callback.onWriteCancelled();
            } else {
                // Describe the pages actually supplied so the spooler can select the requested
                // range.
                callback.onWriteFinished(new PageRange[] { new PageRange(0, info.getPageCount() - 1) });
            }
        });
    }

    @Override
    public void onFinish() {
        worker.shutdown();
    }
}
