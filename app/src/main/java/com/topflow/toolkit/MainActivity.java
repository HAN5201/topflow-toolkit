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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }

        // 注入原生 JS 桥接通道，方便点击一键连接跳转
        webView.addJavascriptInterface(new Object() {
            @JavascriptInterface
            public void connectDevice(String password) {
                runOnUiThread(() -> webView.loadUrl(TARGET_URL));
            }
        }, "AndroidBridge");

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame() && !view.getUrl().startsWith("file:///")) {
                    // 当 192.168.0.1 无法连接时，自动切回本地 HTML 模板界面，保证界面不空白
                    view.loadUrl(LOCAL_URL);
                }
            }
        });

        // 优先尝试加载 192.168.0.1，失败则渲染本地 login.html
        webView.loadUrl(TARGET_URL);
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
