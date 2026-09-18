# Master Guide: JioFi Web Firmware Update Architecture & Custom ZIP Packaging

## 1. Overview & Hardware Architecture

This guide explains the inner workings of the **JioFi Web Firmware Update Engine** for devices running the **Qualcomm MDM9607 platform** (AMTelecom **AR5800RJ** / JioFi 4 JMR1140 hardware revision). 

The JioFi update engine validates packages through **Model Matching (`AR5800RJ`)**, **`build.prop` Inspection**, and **Qualcomm Android Recovery (`update-binary`)**.

---

## 2. End-to-End Execution Pipeline

```
[ 1. Web Panel Upload ]
   ├── User selects ZIP file in Web UI (Firmware Update)
   ├── Web server saves upload payload to: /data/upgrade/update.zip
   └── Web CGI / daemon sets recovery command:
       echo --update_package=/data/upgrade/update.zip > /cache/recovery/command

[ 2. Reboot & Recovery Handshake ]
   ├── Web daemon executes: sys_reboot recovery
   ├── Qualcomm Bootloader (appsboot.mbn) detects recovery command
   └── Boots into Recovery Kernel & RAMDISK

[ 3. Recovery Validation & Extraction (/usr/bin/recovery) ]
   ├── Recovery opens /data/upgrade/update.zip
   ├── Unzips system/build.prop to temporary directory
   ├── Reads ro.product.model property
   ├── Compares ro.product.model ("AR5800RJ") against hardware model ("AR5800RJ")
   └── If match succeeds -> Runs /META-INF/com/google/android/update-binary

[ 4. Low-Level Flashing (updater-script) ]
   ├── Mounts physical UBIFS NAND flash volume (/dev/ubi2_0 -> /system)
   ├── Extracts system files to /system/bin/ (busybox) and /system/usr/bin/ (jiofetch)
   ├── Sets executable permissions (chmod 0755)
   ├── Unmounts /system safely
   └── Clears recovery command & reboots router into normal operating system
```

---

---

## 3. The 7 Golden Rules for Custom JioFi Update ZIPs

To ensure a custom update ZIP installs successfully via the JioFi Web Panel without bricking, aborting, or throwing 404 errors, it **must** strictly adhere to these 7 principles:

### Rule 1: Correct Hardware Model (`ro.product.model=AR5800RJ`)
* The JioFi recovery binary (`/usr/bin/recovery`) unzips `system/build.prop` from the package and compares `ro.product.model` against hardware NVRAM.
* `system/build.prop` **must** contain:
  ```ini
  ro.product.model=AR5800RJ
  ro.build.version.incremental=907419386
  ```
* ❌ *If omitted or set to `JMR1140`*, recovery aborts before executing `update-binary`:
  `I:model name missmatch (JMR1140) : (AR5800RJ) -> Installation aborted.`

---

### Rule 2: Explicit UBIFS Flash Partition Mounting
* In recovery mode, the physical `/system` NAND partition (`/dev/ubi2_0`) is **NOT mounted** by default.
* Your `updater-script` **must explicitly mount `/dev/ubi2_0`** using `run_program` before writing files:
  ```edify
  ui_print("Mounting physical system partition...");
  mount("ubifs", "UBI", "system", "/system");
  run_program("/bin/mount", "-t", "ubifs", "/dev/ubi2_0", "/system");
  ```
* ❌ *If omitted*, files extract into the volatile RAMDISK and vanish permanently upon reboot!

---

### Rule 3: DEFLATE Compression Only (Type 8)
* Qualcomm's embedded `minzip` library used by `update-binary` **fails silently or corrupts** if files are packaged using `STORE` (compression type 0) or non-standard compression methods.
* All files in the ZIP archive must be compressed with standard **DEFLATE (`type 8`)**.
* Use Python's `zipfile.ZIP_DEFLATED` or standard `zip -r` (avoid 7z non-standard deflate).

---

### Rule 4: Dual Webserver Path Deployment (Prevents 404 Not Found)
* The embedded lighttpd web server can mount document roots to either `/system/WEBSERVER/www/` or `/system/www/` depending on the boot configuration.
* If deploying web pages or CGI backends (e.g. `terminal.html`, `console.cgi`, `OkPage.html`), you **MUST** provide identical copies in **both** directory trees:
  ```text
  WEBSERVER/www/terminal.html  <──>  www/terminal.html
  WEBSERVER/www/cgi-bin/console.cgi <──> www/cgi-bin/console.cgi
  WEBSERVER/www/OkPage.html    <──>  www/OkPage.html
  ```
* ❌ *If deployed to only one path*, the router will return **404 Not Found** when accessing `/terminal.html`.

---

### Rule 5: Pre-Create Destination Directories
* Qualcomm's `package_extract_dir()` does not reliably create deep intermediate directory paths on UBIFS.
* Pre-create all target directories in `updater-script` using `run_program`:
  ```edify
  ui_print("Creating target directories...");
  run_program("/bin/mkdir", "-p", "/system/WEBSERVER/www/cgi-bin");
  run_program("/bin/mkdir", "-p", "/system/www/cgi-bin");
  run_program("/bin/mkdir", "-p", "/system/usr/bin");
  run_program("/bin/mkdir", "-p", "/system/usr/lib");
  ```

---

### Rule 6: Executable Permissions & Unix Line Endings
* CGI scripts (`console.cgi`), shell utilities (`battery_info`, `jiofetch`), shared libraries (`libqcmap_cm.so.1`), and binaries (`busybox`, `02e1`) must have `0755` permissions assigned in **two** places:
  1. In the ZIP archive header: external attribute `0o100755 << 16`.
  2. In `updater-script` after extraction:
     ```edify
     set_perm(0, 0, 0755, "/system/bin/busybox");
     set_perm(0, 0, 0755, "/system/usr/bin/jiofetch");
     set_perm(0, 0, 0755, "/system/usr/bin/battery_info");
     set_perm(0, 0, 0755, "/system/usr/lib/libqcmap_cm.so.1");
     set_perm(0, 0, 0755, "/system/sbin/usb/compositions/02e1");
     set_perm(0, 0, 0755, "/system/WEBSERVER/www/cgi-bin/console.cgi");
     set_perm(0, 0, 0755, "/system/www/cgi-bin/console.cgi");
     set_perm(0, 0, 0644, "/system/WEBSERVER/www/terminal.html");
     set_perm(0, 0, 0644, "/system/www/terminal.html");
     ```
* **Unix Line Endings (`\n`)**: Shell and CGI scripts must never contain Windows `\r\n` line endings. Windows carriage returns will cause BusyBox `ash` to throw `sh: console.cgi: not found` or `500 Internal Server Error`.
* **CGI Response Headers**: CGI scripts must always print HTTP response headers before any output:
  ```sh
  printf "Content-Type: text/plain; charset=utf-8\r\n\r\n"
  ```
  Failure to emit headers causes `Network / CGI Execution Error: Failed to fetch`.

---

### Rule 7: ARM 32-bit `update-binary` & Standard Root Layout
* The installer requires the genuine Qualcomm ARM 32-bit `update-binary` at `META-INF/com/google/android/update-binary`.
* The package must adhere to this exact root structure:
  ```text
  update.zip
  ├── bin/
  │   └── busybox
  ├── usr/
  │   ├── bin/
  │   │   ├── battery_info
  │   │   └── jiofetch
  │   └── lib/
  │       └── libqcmap_cm.so.1
  ├── sbin/
  │   └── usb/compositions/02e1
  ├── WEBSERVER/
  │   └── www/
  │       ├── OkPage.html
  │       ├── terminal.html
  │       └── cgi-bin/console.cgi
  ├── www/
  │   ├── OkPage.html
  │   ├── terminal.html
  │   └── cgi-bin/console.cgi
  ├── system/
  │   └── build.prop                  # Model declaration (ro.product.model=AR5800RJ)
  ├── compatibility.txt               # AR5800RJ:0:00000000
  └── META-INF/
      └── com/
          └── google/
              └── android/
                  ├── update-binary    # Qualcomm ARM 32-bit recovery installer
                  └── updater-script   # Edify installation script
  ```

---

## 4. Automated Packaging Tool (`pack_update_zip.py`)

To prevent packaging errors, use the turnkey packaging tool located at [`zip_update/pack_update_zip.py`](file:///home/gaurav/jiofi/zip_update/pack_update_zip.py).

Whenever an AI agent or human developer updates any web file, script, or binary in `scratch/web_console/`, **run this single command**:

```bash
python3 zip_update/pack_update_zip.py
```

### What `pack_update_zip.py` Does Automatically:
1. **Pre-flight Validation**: Checks for `ro.product.model=AR5800RJ`, UBIFS `/dev/ubi2_0` mount in `updater-script`, and dual `WEBSERVER/www` + `www` mirror consistency.
2. **Line-Ending Normalization**: Strips Windows `\r\n` from shell scripts and CGI files automatically.
3. **Deterministic DEFLATE Compression**: Forces compression type 8 (`zipfile.ZIP_DEFLATED`).
4. **Permissions Enforcement**: Injects correct Unix octal file modes (`0o100755` for executables, `0o100644` for web assets).
5. **Bit-for-Bit Self-Test**: Automatically extracts the output zip into a temporary directory and verifies CRC32 checksums against the staging source.
6. **Syncs Output**: Generates both [`zip_update/jiofi_web_terminal_update.zip`](file:///home/gaurav/jiofi/zip_update/jiofi_web_terminal_update.zip) and [`zip_update/update.zip`](file:///home/gaurav/jiofi/zip_update/update.zip).

---

## 5. Failure Modes & Troubleshooting Matrix

| Symptom / Error | Root Cause | Fix |
|---|---|---|
| **404 Not Found** when opening `/terminal.html` | File was only copied to `www/` and missing in `WEBSERVER/www/` (or vice-versa). | Deploy identical files to both `WEBSERVER/www/` and `www/`. Run `pack_update_zip.py`. |
| **Network / CGI Execution Error: Failed to fetch** | `console.cgi` is missing `0755` permissions, has Windows CRLF `\r\n`, or didn't output HTTP headers. | Chmod `0755`, convert to LF, and ensure `printf "Content-Type: text/plain\r\n\r\n"` is emitted. |
| **`cat: can't open '/sys/class/power_supply/battery/capacity'`** | MDM9607 board lacks standard Android fuel-gauge sysfs path. | Use `battery_info` which reads `/sys/bus/spmi/devices/qpnp-vadc-*/vbat_sns`. |
| **Update installs but changes disappear after reboot** | `updater-script` did not mount physical UBIFS partition `/dev/ubi2_0` to `/system`. Files wrote to RAMDISK. | Ensure `mount("ubifs", "UBI", "system", "/system"); run_program("/bin/mount", "-t", "ubifs", "/dev/ubi2_0", "/system");` is present. |
| **`model name missmatch (JMR1140) : (AR5800RJ)`** | `system/build.prop` contains `JMR1140` instead of `AR5800RJ`. | Change `ro.product.model=AR5800RJ` in `system/build.prop`. |
| **Web update aborts immediately / corrupt package** | ZIP was created with `STORE` (0) compression or non-standard ZIP tool. | Compress using standard `zipfile.ZIP_DEFLATED` (type 8) via `pack_update_zip.py`. |

---

## 6. Available Update Packages

* 💻 **[jiofi_web_terminal_update.zip](file:///home/gaurav/jiofi/zip_update/jiofi_web_terminal_update.zip)** (960 KB) ⭐ **[RECOMMENDED]**
  *(Installs the Root Web Terminal at `http://192.168.225.1/terminal.html`, `console.cgi` backend, `battery_info` diagnostic tool, `libqcmap_cm.so.1` patched version `GauravJiofiMK1`, upgraded BusyBox 1.38.0, `jiofetch`, and persistent ADB shell enabler.)*

* 📄 **[jiofi_jiofetch_update.zip](file:///home/gaurav/jiofi/zip_update/jiofi_jiofetch_update.zip)** (877 KB)
  *(Original working update ZIP containing Busybox 1.38.0 and jiofetch)*

* 🔧 **[jiofi_adb_enabler.zip](file:///home/gaurav/jiofi/zip_update/jiofi_adb_enabler.zip)** (95 KB)
  *(ADB enabler — patches USB composition to start `adbd` on every boot. Gives persistent ADB shell access without any other changes.)*


---

## 7. How to Flash via Web Panel

1. Open your router's Web Control Panel (`http://192.168.225.1/`).
2. Navigate to **Firmware Update**.
   *(If the Upgrade button is hidden by ACS, open DevTools console and set `upgradesmanaged = 0;` or use Level 1 account `administrator`)*.
3. Select your desired update `.zip` (e.g. `jiofi_web_terminal_update.zip`).
4. Click **Upgrade**.
5. Wait for the router to flash and reboot automatically (takes ~1–2 minutes).
6. Once rebooted:
   * **Web Terminal**: Open `http://192.168.225.1/terminal.html` in any browser on phone or PC!
   * **ADB Shell**: Connect via USB and run `adb shell`.
