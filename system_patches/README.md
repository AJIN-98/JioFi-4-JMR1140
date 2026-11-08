# JioFi 4 (MDM9607) System Firmware Patches

This directory contains system patches for the JioFi JMR1140 router (Qualcomm MDM9607). Depending on what you want to achieve, follow one of the three options below to build your custom firmware.

---

## 🛠️ Step 1: Unpack the Stock Firmware
Before applying any patch, extract the UBIFS root filesystem from your stock system image:

```bash
# Setup virtual environment and install ubi-reader
python3 -m venv /tmp/ubi-venv
/tmp/ubi-venv/bin/pip install ubi-reader

# Extract files (preserves permissions, ownership, and symlinks)
/tmp/ubi-venv/bin/ubireader_extract_files -o /tmp/extracted_rootfs mdm9607-sysfs.ubi
```
The root filesystem will be extracted to `/tmp/extracted_rootfs/rootfs/`. Keep this terminal window open.

---

## ⚡ Choose Your Patch Option

### Option A: I want Root ADB Shell Access only
*(Keeps the stock firmware completely original, but enables a Root ADB console over USB)*

1. **Apply the USB Composition patch:**
   ```bash
   cp -rf 1_adb_only/* /tmp/extracted_rootfs/rootfs/
   ```
2. **Create the ADB Shell symlink (required for shell capability):**
   ```bash
   mkdir -p /tmp/extracted_rootfs/rootfs/system/bin
   ln -sf /bin/sh /tmp/extracted_rootfs/rootfs/system/bin/sh
   ```
3. Proceed directly to **Step 3 (Rebuild & Flash)**.

---

### Option B: I want ADB Access + Carrier APN Unlock
*(Enables root ADB access and unlocks cellular configurations to use SIM cards from other carriers like Airtel, Vi, BSNL, etc.)*

1. **Apply the USB and MobileAP configuration patches:**
   ```bash
   cp -rf 2_adb_apn/* /tmp/extracted_rootfs/rootfs/
   ```
2. **Create the ADB Shell symlink (required for shell capability):**
   ```bash
   mkdir -p /tmp/extracted_rootfs/rootfs/system/bin
   ln -sf /bin/sh /tmp/extracted_rootfs/rootfs/system/bin/sh
   ```
3. Proceed directly to **Step 3 (Rebuild & Flash)**.

---

### Option C: I want the full Dual-WLAN Wi-Fi Repeater
*(Turns the JioFi into a standalone travel router. Connects to an upstream Wi-Fi source on `wlan0` and broadcasts a custom local hotspot on `wlan1`. Includes a Web UI dashboard at `http://192.168.224.1` and dynamic signal strength LEDs.)*

1. **Apply the Repeater firmware, module drivers, and Web UI files:**
   ```bash
   cp -rf 3_wifi_repeater/* /tmp/extracted_rootfs/rootfs/
   ```
2. **Install the BusyBox build with HTTP Basic Authentication support:**
   ```bash
   cp 5_busybox/binaries/1.31.0/busybox /tmp/extracted_rootfs/rootfs/bin/busybox
   chmod 755 /tmp/extracted_rootfs/rootfs/bin/busybox
   ln -sf /bin/busybox /tmp/extracted_rootfs/rootfs/sbin/httpd
   chmod 755 /tmp/extracted_rootfs/rootfs/www/cgi-bin/save
   chmod 755 /tmp/extracted_rootfs/rootfs/www/cgi-bin/reboot
   chmod 755 /tmp/extracted_rootfs/rootfs/www/cgi-bin/users
   chmod 755 /tmp/extracted_rootfs/rootfs/usr/lib/repeater_auth.sh
   chown 0:0 /tmp/extracted_rootfs/rootfs/www/cgi-bin/users
   chown 0:0 /tmp/extracted_rootfs/rootfs/usr/lib/repeater_auth.sh
   ```
3. **Create the ADB Shell symlink (required for shell capability):**
   ```bash
   mkdir -p /tmp/extracted_rootfs/rootfs/system/bin
   ln -sf /bin/sh /tmp/extracted_rootfs/rootfs/system/bin/sh
   ```
4. **Register the Repeater service to run automatically on system boot:**
   ```bash
   cd /tmp/extracted_rootfs/rootfs/etc
   ln -sf ../init.d/start_repeater rc2.d/S99start_repeater
   ln -sf ../init.d/start_repeater rc3.d/S99start_repeater
   ln -sf ../init.d/start_repeater rc4.d/S99start_repeater
   ln -sf ../init.d/start_repeater rc5.d/S99start_repeater
   ```
5. Proceed to **Step 3 (Rebuild & Flash)**.

The repeater UI saves validated settings before applying them. Applying a changed
network no longer unloads/reloads the Wi-Fi driver, avoiding the driver reset
that could leave the device unresponsive. The repeater startup also leaves the
OEM `uiapp` running so its hardware button handling is not disabled. Hotspot
passwords are not returned by the status endpoint.

The OpenFi UI is a self-contained, offline-friendly dashboard with separate Overview,
Internet, Hotspot Wi-Fi, Devices, and System pages. The Overview opens first and
shows battery and device telemetry. Use the sign-in button in the header; the
login form is part of the page rather than the browser's Basic Auth popup.

On first boot, the accounts are `admin` / `admin` and `user` / `user`. The
administrator can manage user accounts, change Wi-Fi and IP settings, and
restart the device. User accounts can view status and change only the hotspot
Wi-Fi password. After a configuration change, OpenFi waits 30 seconds and
restarts to apply it cleanly. Change the default passwords from the System page. HTTP
does not encrypt credentials or traffic, so use the UI only on a trusted local
Wi-Fi network.
Account password and user-list changes are saved immediately, but the repeater
must be rebooted before the updated credentials take effect. The System page
displays this reminder.
The Overview reports charging when USB input is present even if the charger
driver reports "Not charging". The power-button RGB LED shows red below 20%,
amber from 20-39%, and green at 40% or above; it blinks in the same color while
charging and stays solid on battery power.

Each firmware release has a version marker. On first boot after flashing a
different release, OpenFi resets saved upstream Wi-Fi, hotspot Wi-Fi, IP, and
account settings to that release's defaults (including `admin` / `admin` and
`user` / `user`). Normal reboots on the same release preserve settings.

The default hotspot is named `OpenFi_Repeater`. The repeater keeps the OEM network manager disabled to avoid it reconfiguring
the repeater radios. A small input-event listener handles the OEM power key
(three-second hold to power off) and WPS key (push-button WPS on the local
hotspot). Applying new Wi-Fi settings reconfigures the running services without
unloading the Wi-Fi driver. AP mode is not included.

---

## 🛠️ Step 3: Rebuild the UBI Image
Once you have applied your chosen option, follow these commands to compile the files back into a flashable UBI binary:

```bash
# 1. Compile the UBIFS rootfs image (fakeroot is required to maintain system permissions)
fakeroot -- /usr/sbin/mkfs.ubifs \
  -r /tmp/extracted_rootfs/rootfs \
  -m 2048 -e 126976 -c 2146 -F -j 8388608 -x lzo \
  -o /tmp/rootfs.ubifs
```

Create a file named `/tmp/ubinize.cfg` with the following configuration:
```ini
[rootfs]
mode=ubi
image=/tmp/rootfs.ubifs
vol_id=0
vol_size=41267200
vol_type=dynamic
vol_name=rootfs
vol_flags=autoresize
```

Build the final flashable `.ubi` image file:
```bash
/usr/sbin/ubinize \
  -o /tmp/mdm9607-sysfs-custom.ubi \
  -m 2048 -p 128KiB -s 2048 -Q 907419386 \
  /tmp/ubinize.cfg
```

---

## ⚡ Flashing Your Patched Firmware

Choose one of the two methods below to flash your custom firmware:

### Method 1: Using the Stock Firmware Upgrade Utility (Recommended for First-Time Setup)
If you are flashing your device for the first time or do not have Fastboot/ADB drivers set up, you can use the stock Windows firmware upgrade executable (`.exe`):

1. Locate the directory containing the stock firmware flashing tool (and its matching executable) on your PC.
2. Inside that directory, locate the original stock system UBI file (typically named `mdm9607-sysfs.ubi`).
3. Rename your newly built custom image (`mdm9607-sysfs-custom.ubi`) to match the exact filename of the stock image (e.g. rename it to `mdm9607-sysfs.ubi`).
4. Replace the original stock file in the utility's directory with your renamed custom file.
5. Run the firmware upgrade `.exe` utility to flash the patched firmware onto your device.

---

### Method 2: Using Fastboot Directly (For Subsequent Updates)
If you already have root ADB shell access and Fastboot tools installed on your PC:

1. **Reboot the JioFi into Fastboot mode:**
   ```bash
   adb reboot bootloader
   ```
2. **Flash the custom system image file:**
   ```bash
   fastboot flash system /tmp/mdm9607-sysfs-custom.ubi
   ```
3. **Reboot the router:**
   ```bash
   fastboot reboot
   ```