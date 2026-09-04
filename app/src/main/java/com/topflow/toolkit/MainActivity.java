package com.topflow.toolkit;

import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {

    private WebView webView;
    private static final String LOCAL_URL = "file:///android_asset/login.html";
    private static final String TARGET_URL = "http://192.168.0.1";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        webView = findViewById(R.id.webview);

        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(true);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            settings.setAllowUniversalAccessFromFileURLs(true);
            settings.setAllowFileAccessFromFileURLs(true);
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }

        webView.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void connectDevice(String password) {
                runOnUiThread(() -> webView.loadUrl(TARGET_URL));
            }
        }, "AndroidBridge");

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                // 如果资产文件读取失败或网络连接错误，直接硬编码渲染 UI
                renderFallbackUI(view);
            }
        });

        try {
            webView.loadUrl(LOCAL_URL);
        } catch (Exception e) {
            renderFallbackUI(webView);
        }
    }

    // 终极硬编码 UI 兜底（不依赖任何外部文件）
    private void renderFallbackUI(WebView view) {
        String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'>"
                + "<style>body{background:#030813;color:#00d2ff;text-align:center;padding-top:40%;font-family:sans-serif;}"
                + ".card{background:rgba(6,18,41,0.9);margin:20px;padding:30px;border-radius:16px;border:1px solid #00d2ff;box-shadow:0 0 20px #00d2ff;}"
                + "button{background:#0052d4;color:#fff;border:none;padding:12px 24px;border-radius:8px;font-size:16px;margin-top:20px;}</style></head>"
                + "<body><div class='card'><h2>TopFlow 控制台</h2><p>已成功启动控制台内核</p>"
                + "<button onclick='location.href=\"http://192.168.0.1\"'>连接 192.168.0.1</button></div></body></html>";
        view.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
