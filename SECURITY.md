# Security

## Supported scope

This repository targets one firmware family and currently has no long-term support guarantee. Security fixes should be tested against the exact device and firmware build named in the root README.

## Reporting

Please use GitHub's private vulnerability reporting feature for vulnerabilities that could expose credentials, bypass the WebUI login boundary, execute arbitrary commands, or disrupt network recovery. Do not open a public issue containing device credentials, subscriptions, controller secrets, configuration backups, logs with proxy URLs, or identifying device values.

## Operator responsibilities

- Keep Mihomo configuration and provider files outside Git.
- Set a strong controller `secret` before exposing the controller to LAN clients.
- Review all fixed addresses, interfaces and firmware hashes before installation.
- Keep a tested rollback path. A misconfigured DHCP gateway can disconnect every LAN client.
- Treat WebUI configuration and logs as sensitive even though the page requires an authenticated device session.
