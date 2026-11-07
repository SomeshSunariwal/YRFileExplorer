package com.somesh.yrfileexplorer.media;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.graphics.RectF;
import android.graphics.pdf.PdfRenderer;
import android.graphics.pdf.PdfRendererPreV;
import android.graphics.pdf.models.PageMatchBounds;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.os.ext.SdkExtensions;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.function.BooleanSupplier;

/** Finds embedded PDF text and returns bounds relative to each page's size. */
final class PdfTextSearch {
    record Match(int page, List<RectF> bounds) {}

    static boolean isAvailable() {
        return Build.VERSION.SDK_INT >= 35
                || SdkExtensions.getExtensionVersion(Build.VERSION_CODES.S) >= 13;
    }

    static List<Match> find(File file, String query, BooleanSupplier cancelled) throws IOException {
        return Build.VERSION.SDK_INT >= 35
                ? findOnAndroid15(file, query, cancelled)
                : findWithExtension(file, query, cancelled);
    }

    @TargetApi(35)
    private static List<Match> findOnAndroid15(File file, String query, BooleanSupplier cancelled)
            throws IOException {
        List<Match> matches = new ArrayList<>();
        try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
             PdfRenderer pdf = new PdfRenderer(descriptor)) {
            for (int i = 0; i < pdf.getPageCount() && !cancelled.getAsBoolean(); i++) {
                try (PdfRenderer.Page page = pdf.openPage(i)) {
                    append(matches, i, page.searchText(query), page.getWidth(), page.getHeight());
                }
            }
        }
        return matches;
    }

    // The caller checks S Extensions 13 before dispatching to this implementation.
    @SuppressLint("NewApi")
    private static List<Match> findWithExtension(File file, String query, BooleanSupplier cancelled)
            throws IOException {
        List<Match> matches = new ArrayList<>();
        try (ParcelFileDescriptor descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
             PdfRendererPreV pdf = new PdfRendererPreV(descriptor)) {
            for (int i = 0; i < pdf.getPageCount() && !cancelled.getAsBoolean(); i++) {
                try (PdfRendererPreV.Page page = pdf.openPage(i)) {
                    append(matches, i, page.searchText(query), page.getWidth(), page.getHeight());
                }
            }
        }
        return matches;
    }

    @SuppressLint("NewApi")
    private static void append(List<Match> output, int page, List<PageMatchBounds> matches,
                               float width, float height) {
        for (PageMatchBounds match : matches) {
            List<RectF> bounds = new ArrayList<>();
            for (RectF rect : match.getBounds()) {
                bounds.add(new RectF(rect.left / width, rect.top / height,
                        rect.right / width, rect.bottom / height));
            }
            if (!bounds.isEmpty()) output.add(new Match(page, bounds));
        }
    }
}
