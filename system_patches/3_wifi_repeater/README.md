# OpenFi Repeater Firmware

This patch configures the JioFi JMR1140 as an OpenFi Wi-Fi repeater. It uses
`wlan0` for the upstream Wi-Fi connection and `wlan1` for the local hotspot.
The local hotspot uses a separate subnet and DHCP service.

## Features

- Offline-friendly web interface with Overview, Devices, Internet, Hotspot
  Wi-Fi, and System pages.
- HTTP Basic Authentication with an in-page sign-in form.
- `admin` accounts can configure upstream Wi-Fi, hotspot Wi-Fi, IP settings,
  user accounts, and restart the device.
- `user` accounts can view status and change only the hotspot Wi-Fi password.
- Administrators can add, remove, and update user passwords, and change the
  administrator password.
- Wi-Fi settings are saved and applied after a 30-second restart delay.
- Administrators can set the DNS server used by OpenFi and devices connected to
  the hotspot.
- Administrators can turn the Power/Battery, Wi-Fi, and RSSI LED groups on or
  off independently.
- Optional power-saving mode reduces LED/watchdog polling and UI refreshes. It
  leaves Wi-Fi driver power management unchanged and reduces CPU wakeups; it
  does not increase free memory.
- The UI offers a persistent dark theme.
- Account changes are saved immediately; reboot the device to activate updated
  credentials.
- Power button: hold for three seconds to power off. WPS button: press to start
  WPS push-button setup.
- Power-button RGB LED shows the estimated battery state: red below 20%, amber
  from 20% through 39%, and green at 40% or above. It blinks in the same color
  while charging and stays solid on battery power.
- Battery voltage and charging state are read from the JMR1140 VADC and
  SY6923 charger sysfs interfaces. The displayed percentage is an estimate
  derived from voltage, not a calibrated fuel-gauge reading.

## Default access

On a fresh v7 installation, the initial accounts are:

| Role | Username | Password |
|---|---|---|
| Administrator | `admin` | `admin` |
| User | `user` | `user` |

Change these credentials from **System & accounts**. The first boot after
flashing a different OpenFi release resets saved upstream Wi-Fi, hotspot,
IP, and account settings to that release's defaults. Reboots on the same
release preserve the saved settings.

## Network and security notes

- The default hotspot SSID is `OpenFi_Repeater`; its initial Wi-Fi password is
  `12345678`. Change it before normal use.
- User accounts cannot scan for or change upstream networks, change the
  hotspot SSID, modify IP settings, manage accounts, or restart the device.
- HTTP does not encrypt credentials or traffic. Use the interface only over a
  trusted local connection; do not expose it to the public Internet.
- AP-only mode is not included.
- USB Ethernet is not available in the current image. Inspection of the image
  found no USB Ethernet kernel modules, and this firmware cannot drive a USB
  Ethernet adapter without a compatible kernel driver.

## Battery runtime

Battery life is not yet optimized or characterized. The repeater currently
loads the Wi-Fi driver with `rtw_power_mgnt=0` and `rtw_ips_mode=0` to avoid
wireless power-saving behavior that previously interfered with stable
operation. Disabling those driver power-management features can increase
power consumption. Do not enable them without testing Wi-Fi stability,
reconnection, and suspend/resume behavior on the device.

## Firmware image

The latest image is
[`mdm9607-sysfs-repeater-openfi-v7.ubi`](../../patched/mdm9607-sysfs-repeater-openfi-v7.ubi).
It includes the LED, DNS, dark-mode, and power-saving settings. The image was
rebuilt and extracted to verify its contents; these new options still need
device testing. USB Ethernet is not supported by the included kernel.

The repeater overlay's UBI build geometry is documented in
[`system_patches/README.md`](../README.md).

SHA-256 of v7:

```text
68e703da2fd27ca14a63ff2fe5c245d9dd6798b2831d20f92e360202fa9ee0d5
```

The image was built from the repeater base UBI with the overlay in this
directory, then extracted to verify the included files. The first boot after
upgrading from v6 resets saved Wi-Fi, IP, and account settings once; reconfigure
the device after flashing. Device-specific behavior should still be confirmed.
