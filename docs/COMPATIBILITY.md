# Compatibility boundary

The project is validated only on ZTE TOPFLOW MU5252 hardware revision `MU5252_HW1.0` with firmware `BD_ENCNMU5252V1.0.0B20`.

The following details are firmware-specific:

- WebUI directory layout and `requireLogin` routing;
- UBus object and method names;
- `br-lan`, cellular and Mihomo network interface names;
- availability and behavior of `iptables`, `ebtables`, `ip netns`, UCI and procd;
- the non-PIE touchscreen process, LVGL ABI and in-process asset addresses;
- startup ordering and the use of `/etc/rc.local` as a persistence fallback.

Do not add another firmware hash to an allowlist until installation, normal operation, stop, uninstall, failed-start recovery and reboot persistence have all been tested on that firmware.
