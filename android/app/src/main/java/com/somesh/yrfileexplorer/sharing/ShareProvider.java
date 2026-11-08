package com.somesh.yrfileexplorer.sharing;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;

/** Non-exported provider. Only explicitly granted, read-only URIs can be opened. */
public class ShareProvider extends ContentProvider {
    public static Uri uri(File f) { return new Uri.Builder().scheme("content").authority("com.somesh.yrfileexplorer.files").appendPath("open").appendQueryParameter("path", f.getAbsolutePath()).build(); }
    private File file(Uri u) throws FileNotFoundException {
        String p = u.getQueryParameter("path"); if (p == null) throw new FileNotFoundException();
        try {
            File f = new File(p).getCanonicalFile();
            File app = getContext().getFilesDir().getCanonicalFile();
            String path = f.getPath();
            // Never expose preferences, databases, keys, or other internal app data.
            if (!(com.somesh.yrfileexplorer.security.PrivateSpace.mayReadPreview(getContext(),f) || path.startsWith("/storage/") || path.startsWith("/sdcard/") || path.startsWith(app.getPath() + "/exports/"))) throw new FileNotFoundException("Path is not shareable");

            return f;
        } catch (IOException ex) { throw new FileNotFoundException(ex.getMessage()); }
    }
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri u) {
        String path=u.getQueryParameter("path");
        String name=path==null?"":new File(path).getName();
        int dot=name.lastIndexOf('.');
        String ext=dot<0?"":name.substring(dot+1).toLowerCase(java.util.Locale.ROOT);
        String mime=com.somesh.yrfileexplorer.media.AudioFormats.mime(name);
        if(mime==null) mime=MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext);
        return mime==null?"application/octet-stream":mime;
    }
    @Override public ParcelFileDescriptor openFile(Uri u, String mode) throws FileNotFoundException { if (!mode.equals("r")) throw new FileNotFoundException("Read-only"); return ParcelFileDescriptor.open(file(u), ParcelFileDescriptor.MODE_READ_ONLY); }
    @Override public Cursor query(Uri u, String[] projection, String s, String[] a, String sort) {
        try { File f = file(u); MatrixCursor c = new MatrixCursor(new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}); c.addRow(new Object[]{f.getName(), f.length()}); return c; }
        catch (FileNotFoundException e) { return null; }
    }
    @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
}
