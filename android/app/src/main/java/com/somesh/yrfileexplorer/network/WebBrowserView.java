package com.somesh.yrfileexplorer.network;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.graphics.Bitmap;
import android.net.Uri;
import android.net.http.SslError;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.HttpAuthHandler;
import android.webkit.SslErrorHandler;
import android.webkit.URLUtil;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/** Web content requested by the user; no local-file bridge or TLS bypass. */
public final class WebBrowserView implements PlatformView {
    private final WebView web;
    private final MethodChannel channel;
    private boolean disposed;

    public static final class Factory extends PlatformViewFactory {
        private final BinaryMessenger messenger;

        public Factory(BinaryMessenger messenger) {
            super(StandardMessageCodec.INSTANCE);
            this.messenger = messenger;
        }

        @Override
        public PlatformView create(Context context, int id, Object args) {
            return new WebBrowserView(context, messenger, id, (Map<?, ?>) args);
        }
    }

    private static boolean allowed(String address) {
        Uri uri = Uri.parse(address);
        return Set.of("http", "https").contains(Objects.toString(uri.getScheme(), "")) && uri.getHost() != null
                && uri.getUserInfo() == null;
    }

    private void state() {
        if (!disposed)
            channel.invokeMethod("state", Map.of("url", Objects.toString(web.getUrl(), ""),
                    "back", web.canGoBack(), "forward", web.canGoForward()));
    }

    private WebBrowserView(Context context, BinaryMessenger messenger, int id, Map<?, ?> args) {
        channel = new MethodChannel(messenger, "yr/web/" + id);
        web = new WebView(context);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setSupportMultipleWindows(false);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        WebView.setWebContentsDebuggingEnabled(
                (context.getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!allowed(request.getUrl().toString())) {
                    if (request.isForMainFrame())
                        channel.invokeMethod("error", "Only HTTP and HTTPS addresses are supported");
                    return true;
                }
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap icon) {
                channel.invokeMethod("progress", 0);
                state();
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                channel.invokeMethod("progress", 100);
                state();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame())
                    channel.invokeMethod("error", error.getDescription().toString());
            }

            @Override
            public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
                handler.cancel();
                channel.invokeMethod("error", "The server's HTTPS certificate could not be verified");
            }

            @Override
            public void onReceivedHttpAuthRequest(WebView view, HttpAuthHandler handler, String host, String realm) {
                channel.invokeMethod("authenticate",
                        Map.of("host", Objects.toString(host, ""), "realm", Objects.toString(realm, "")),
                        new MethodChannel.Result() {
                            @Override
                            public void success(Object result) {
                                if (result instanceof Map<?, ?> credentials && !disposed)
                                    handler.proceed(Objects.toString(credentials.get("username"), ""),
                                            Objects.toString(credentials.get("password"), ""));
                                else
                                    handler.cancel();
                            }

                            @Override
                            public void error(String code, String message, Object details) {
                                handler.cancel();
                            }

                            @Override
                            public void notImplemented() {
                                handler.cancel();
                            }
                        });
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int progress) {
                if (!disposed)
                    channel.invokeMethod("progress", progress);
            }
        });
        web.setDownloadListener((url, agent, disposition, mime, length) -> channel.invokeMethod("download", Map.of(
                "url", url, "name", URLUtil.guessFileName(url, disposition, mime))));
        channel.setMethodCallHandler((call, result) -> {
            if (disposed) {
                result.error("CLOSED", "This web tab is closed", null);
                return;
            }
            switch (call.method) {
                case "navigate": {
                    String url = Objects.toString(call.arguments, "");
                    if (!allowed(url)) {
                        result.error("URL", "Enter a valid HTTP or HTTPS URL", null);
                        return;
                    }
                    web.loadUrl(url);
                    break;
                }
                case "back":
                    if (web.canGoBack())
                        web.goBack();
                    break;
                case "forward":
                    if (web.canGoForward())
                        web.goForward();
                    break;
                case "reload":
                    web.reload();
                    break;
                case "stop":
                    web.stopLoading();
                    channel.invokeMethod("progress", 100);
                    break;
                default:
                    result.notImplemented();
                    return;
            }
            state();
            result.success(null);
        });
        String address = Objects.toString(args.get("url"), "");
        if (allowed(address))
            web.loadUrl(address);
    }

    @Override
    public View getView() {
        return web;
    }

    @Override
    public void dispose() {
        disposed = true;
        channel.setMethodCallHandler(null);
        web.stopLoading();
        web.destroy();
    }
}
