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

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public class MainActivity extends AppCompatActivity {

    private WebView webView;
    private static final String MU5252_IP = "192.168.0.1";
    private static final int ADB_PORT = 5555;

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

        // 注入桥梁供网页端调用
        webView.addJavascriptInterface(new MU5252Bridge(), "TopflowBridge");
        webView.setWebViewClient(new WebViewClient());
        
        // 载入 Topflow MU5252 控制后台
        webView.loadUrl("http://" + MU5252_IP);
    }

    public class MU5252Bridge {
        // 执行 ADB 指令
        @JavascriptInterface
        public void execAdb(String command) {
            runSocketAdb(command);
        }

        // 自动调起 WebSSH 终端
        @JavascriptInterface
        public void openWebSSH() {
            runSocketAdb("nohup ttyd -p 7681 -c root:123456 login >/dev/null 2>&1 &");
            new Handler(Looper.getMainLooper()).postDelayed(() ->
                webView.loadUrl("http://" + MU5252_IP + ":7681"), 1000
            );
        }
    }

    private void runSocketAdb(String command) {
        new Thread(() -> {
            Socket socket = null;
            try {
                socket = new Socket();
                socket.connect(new InetSocketAddress(MU5252_IP, ADB_PORT), 3000);
                
                OutputStream out = socket.getOutputStream();
                InputStream in = socket.getInputStream();

                String packet = "shell:" + command + "\n";
                out.write(packet.getBytes(StandardCharsets.UTF_8));
                out.flush();

                byte[] buf = new byte[2048];
                int len = in.read(buf);
                String resp = len > 0 ? new String(buf, 0, len) : "执行成功";

                socket.close();
                showToast("MU5252 返回: " + resp);
            } catch (Exception e) {
                showToast("ADB 连接失败，请检查 5555 调试端口");
            }
        }).start();
    }

    private void showToast(String text) {
        new Handler(Looper.getMainLooper()).post(() ->
            Toast.makeText(MainActivity.this, text, Toast.LENGTH_SHORT).show()
        );
    }

    @Override
    public void onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
