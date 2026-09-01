package com.topflow.toolkit;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    private WebView webView;
    private static final String TOPFLOW_IP = "192.168.0.1";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        webView = findViewById(R.id.webview);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setDatabaseEnabled(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.addJavascriptInterface(new TopflowJSBridge(), "TopflowBridge");
        webView.setWebViewClient(new WebViewClient());
        webView.loadUrl("http://" + TOPFLOW_IP);
    }

    public class TopflowJSBridge {
        @JavascriptInterface
        public void execAdb(String command) {
            AdbManager.execCmd(command, new AdbManager.AdbCallback() {
                @Override
                public void onSuccess(String output) { showToast("成功: " + output); }
                @Override
                public void onError(String error) { showToast("错误: " + error); }
            });
        }

        @JavascriptInterface
        public void loadWebSSH() {
            AdbManager.execCmd("nohup ttyd -p 7681 -c root:123456 login >/dev/null 2>&1 &", new AdbManager.AdbCallback() {
                @Override
                public void onSuccess(String output) {
                    new Handler(Looper.getMainLooper()).postDelayed(() ->
                        webView.loadUrl("http://" + TOPFLOW_IP + ":7681"), 1000
                    );
                }
                @Override
                public void onError(String error) { showToast("无法启动 WebSSH: " + error); }
            });
        }
    }

    private void showToast(String text) {
        new Handler(Looper.getMainLooper()).post(() ->
            Toast.makeText(MainActivity.this, text, Toast.LENGTH_SHORT).show()
        );
    }
}
