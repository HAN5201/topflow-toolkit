package com.topflow.toolkit;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;

public class AdbManager {
    private static final String DEFAULT_HOST = "192.168.0.1";
    private static final int DEFAULT_PORT = 5555;
    private static final int TIMEOUT_MS = 4000;

    public interface AdbCallback {
        void onSuccess(String output);
        void onError(String error);
    }

    public static void execCmd(String command, AdbCallback callback) {
        new Thread(() -> {
            Socket socket = null;
            try {
                socket = new Socket();
                socket.connect(new InetSocketAddress(DEFAULT_HOST, DEFAULT_PORT), TIMEOUT_MS);
                socket.setSoTimeout(TIMEOUT_MS);

                OutputStream out = socket.getOutputStream();
                InputStream in = socket.getInputStream();

                String packet = "shell:" + command + "\n";
                out.write(packet.getBytes(StandardCharsets.UTF_8));
                out.flush();

                byte[] buffer = new byte[2048];
                int bytesRead = in.read(buffer);

                if (bytesRead > 0) {
                    callback.onSuccess(new String(buffer, 0, bytesRead, StandardCharsets.UTF_8));
                } else {
                    callback.onSuccess("指令下发成功");
                }
            } catch (Exception e) {
                callback.onError("ADB 连接超时，请确认 5555 调试端口已开启");
            } finally {
                try {
                    if (socket != null && !socket.isClosed()) socket.close();
                } catch (Exception ignored) {}
            }
        }).start();
    }
}
