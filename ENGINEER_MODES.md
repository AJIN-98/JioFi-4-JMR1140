

# JioFi 4 (JMR1140 / AMTelecom AR5800RJ) Hidden Modes, AT Commands & Advanced Engineering Guide

This document provides a comprehensive catalogue of hidden developer features, diagnostic endpoints, undocumented AT commands, privilege levels, and high-impact reverse-engineering findings discovered in the stock firmware (`mdm9607-sysfs.ubi`).

---

## 1. High-Impact Finding: LTE Band 40 / Band 3 / Band 5 Lock Engine

### The Band 5 Throttling Problem
On the Reliance Jio LTE network, the JMR1140 frequently switches to **Band 5 (850 MHz)** because of its lower frequency and high wall-penetration characteristics. However, Band 5 has very limited spectrum bandwidth (typically 5–10 MHz), causing user throughput to crawl at **1–3 Mbps** even when high-speed **Band 40 (2300 MHz, up to 20 MHz bandwidth, 30–50 Mbps)** is available.

### Firmware Discovery
Qualcomm and AMTelecom implemented a complete **Dedicated EARFCN Scanning and Cell Selection engine** for Reliance Jio (RJIL):
* **Modem Controller**: [`/usr/bin/QCMAP_Web_CLIENT`](file:///home/gaurav/jiofi/rootfs/usr/bin/QCMAP_Web_CLIENT) implements `_ZN12QCMAP_Client11SetCellScanEP24qcmap_rjil_scan_type_v01P18qmi_error_type_v01` and `GetCellScan`.
* **CGI Gateway**: [`/WEBSERVER/www/cgi-bin/qcmap_web_cgi`](file:///home/gaurav/jiofi/personal_builds/sim_adb_build/extracted/907419386/rootfs/WEBSERVER/www/cgi-bin/qcmap_web_cgi) routes `Page: "SetCell"` and `Page: "GetCell"`.
* **Frontend Logic**: In [`WEBSERVER/www/setting/QCMAP_LTE.html`](file:///home/gaurav/jiofi/personal_builds/sim_adb_build/extracted/907419386/rootfs/WEBSERVER/www/setting/QCMAP_LTE.html), the cell selection forms and frequency boundary verification (`CheckBandRange()`) are completely written, but commented out of the UI.

### Supported Frequency & EARFCN Ranges
From `CheckBandRange()` in `QCMAP_LTE.html`:
* **Band 40 (TDD 2300 MHz)**: Range `38650` – `39649` | Bandwidth value `32` (20 MHz)
* **Band 3 (FDD 1800 MHz)**: Range `1200` – `1949` | Bandwidth value `32` (20 MHz)
* **Band 5 (FDD 850 MHz)**: Range `2400` – `2649` | Bandwidth value `8` (10 MHz)

### How to Lock onto Band 40 (Browser Console)
1. Open `http://jiofi.local.html` (or `http://192.168.225.1`) and log in.
2. Press **F12** to open Developer Tools and switch to the **Console** tab.
3. Run the following command:

```javascript
// Lock router onto Band 40 (2300 MHz) with 20 MHz channel width
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: {
        Page: "SetCell",
        Mask: 0,
        result: "0",
        cell_scan_mode: "1",           // 1 = Dedicated EARFCN
        cell_scan_band_nums: "1",
        cell_scan_band_1: "40",        // Band 40
        cell_scan_start_freq_1: "38650",
        cell_scan_end_freq_1: "39649",
        cell_band_width_1: "32",       // 20 MHz channel bandwidth
        token: session_token
    },
    dataType: "text",
    success: function(res) { console.log("Band Lock Success:", res); }
});
```

#### How to Lock onto Band 3 (1800 MHz):
```javascript
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: {
        Page: "SetCell",
        Mask: 0,
        result: "0",
        cell_scan_mode: "1",
        cell_scan_band_nums: "1",
        cell_scan_band_1: "3",         // Band 3
        cell_scan_start_freq_1: "1200",
        cell_scan_end_freq_1: "1949",
        cell_band_width_1: "32",
        token: session_token
    },
    dataType: "text",
    success: function(res) { console.log("Band 3 Lock Success:", res); }
});
```

#### How to Revert to Full Auto Scan:
```javascript
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: {
        Page: "SetCell",
        Mask: 0,
        result: "0",
        cell_scan_mode: "0",           // 0 = Full auto scan
        token: session_token
    },
    dataType: "text",
    success: function(res) { console.log("Revert to Auto Scan:", res); }
});
```

#### Verifying Active Band:
```javascript
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: {
        Page: "GetLTEStatus",
        mask: 0,
        token: session_token
    },
    dataType: "text",
    success: function(res) { console.log("LTE Status:", res); }
});
```

---

## 2. In-System AT Command Execution (ADB Shell)

Running `echo -e "AT+CSQ\r" > /dev/smd8` produces:
```text
cat: can't open '/dev/smd8': Resource temporarily unavailable
```

### Why This Happens
1. **Daemon Lock**: On boot, [`/etc/init.d/start_stop_qti_ppp_le`](file:///home/gaurav/jiofi/rootfs/etc/init.d/start_stop_qti_ppp_le) launches [`/usr/bin/qti_ppp`](file:///home/gaurav/jiofi/rootfs/usr/bin/qti_ppp), which holds `/dev/smd8` open (`Open SMD TTY file to receive AT commands from modem`). Because the device is opened exclusively, other processes encounter `EAGAIN` (`Resource temporarily unavailable`).
2. **SMD Open Timeout**: Qualcomm SMD TTY drivers require an open timeout to be configured before non-blocking opens succeed.

---

### How to Run AT Commands

#### Method A: Direct from Host PC over USB Serial (Most Reliable)
When the JioFi is connected to your PC via USB, the kernel exposes the serial COM interfaces (e.g. `/dev/ttyUSB0`, `/dev/ttyUSB1`, `/dev/ttyUSB2` on Linux, or `COMx` on Windows).
* Open the AT serial port with `picocom`, `minicom`, or `putty`:
  ```sh
  picocom -b 115200 /dev/ttyUSB1
  ```
  Then type `AT+CSQ` or `AT+CEREG?`. (This is also the interface used by [`unlock_jiofi4.py`](file:///home/gaurav/jiofi/unlock_jiofi4.py)).

#### Method B: On-Device via ADB Shell (Releasing `/dev/smd8`)
To communicate with `/dev/smd8` directly from inside an ADB shell session:

```sh
# 1. Temporarily stop the qti_ppp daemon holding the port:
/etc/init.d/start_stop_qti_ppp_le stop

# 2. Set the kernel SMD open timeout (10 seconds):
echo 10 > /sys/class/tty/smd8/open_timeout

# 3. Read and write directly using Busybox microcom:
microcom -t 1000 /dev/smd8

# Or send a one-liner via background cat:
cat /dev/smd8 &
echo -e "AT+CSQ\r" > /dev/smd8

# 4. Once finished, restart qti_ppp to resume cellular data bridging:
/etc/init.d/start_stop_qti_ppp_le start
```

---

## 3. Web UI Privilege Levels: Hidden Superuser & Operator Accounts

On the JMR1140, AMTelecom replaced the legacy `/to_engineer_login.html` page with a **3-tier privilege hierarchy** stored in [`/etc/usermgr.en`](file:///home/gaurav/jiofi/rootfs/etc/usermgr.en) and checked by `qcmap_auth`:

| Level | Account Name | Default Password | MD5 Hash | Privileges |
|:---|:---|:---|:---|:---|
| **Level 1** | `administrator` | `administrator` | `200ceb26807d6bf99fd6f4f0d1ca54d4` | Superuser / Engineer. Unhides APN tables, full user administration, system logs. |
| **Level 2** | `operator` | `operator` | `4b583376b2767b923c3e1da60d10de59` | Operator technician access. |
| **Level 3** | `admin` | `admin` | `21232f297a57a5a743894a0e4a801fc3` | Consumer account. Hides APN tables and diagnostics with CSS (`session_level == 3`). |

### How to Access Secret / Unlinked Web Pages
Because the Web UI is a Single-Page Application driven by [`QCMAP.html`](file:///home/gaurav/jiofi/personal_builds/sim_adb_build/extracted/907419386/rootfs/WEBSERVER/www/QCMAP.html), subpages contain a JavaScript redirect guard:
```javascript
if (!window.jQuery) { document.location = "http://jiofi.local.html"; }
```
Direct browser URL navigation will bounce back to the login page. Instead, log in, open DevTools (`F12` → **Console**), and call `loadpage('<path>')`:

| Feature | Console Command | Function |
|:---|:---|:---|
| **System Event Log** | `loadpage('help/QCMAP_Log_Config.html')` | View live system logs and export raw `/systemlog` dump. |
| **Raw Log View** | `loadpage('help/QCMAP_Log.html')` | Simple unformatted text log viewer. |
| **RF Link Budget Calculator** | `loadpage('help/QCMAP_Link_Budge_Calculator.html')` | Attenuation and signal calculator. |
| **DHCP Server Configuration** | `loadpage('setting/QCMAP_Dhcp_Server.html')` | Custom lease ranges and static IP assignments. |
| **Firewall & Port Forwarding** | `loadpage('setting/QCMAP_Firewall.html')` | Inbound packet rules and DMZ controls. |
| **MicroSD File Manager** | `loadpage('storage/QCMAP_WiFiDisk.html')` | Web browser for internal storage card. |
| **Qualcomm WWAN Panel** | `loadpage('QCMAP_WWAN.html')` | Low-level cellular data bearer status. |
| **Qualcomm NAT Panel** | `loadpage('QCMAP_NAT.html')` | Full-cone / symmetric NAT behavior and port timeouts. |

---

## 4. JioCall / Jio4GVoice Architecture & Undocumented TCP AT Server (Port 6666)

Reverse-engineering the official **JioCall** APK (`com.jio.join_5.1.1`) and the stock router firmware (`QCMAP_ConnectionManager` / `libtask_mgr.so.1`) reveals the exact proprietary protocol stack Reliance Jio and AMTelecom engineered to enable VoLTE voice/video calls and SMS from non-VoLTE or Wi-Fi-only smartphones.

---

### A. The 3GPP VoLTE Dilemma & Why Jio Needs This
Reliance Jio operates an all-IP IMS (IP Multimedia Subsystem) core. Under 3GPP standards (TS 24.229), every SIP `REGISTER` and `INVITE` request **must** contain a valid `P-Access-Network-Info` (PANI) header specifying the physical cellular tower ID (E-UTRAN Global Cell ID / GCI) and tracking area code (TAC). This is required for:
1. **Regulatory Emergency Call Routing & Location Services** (E911).
2. **Cell-level Billing & QoS Policy Enforcement**.

When a smartphone connects to a JioFi hotspot over Wi-Fi, the phone does **not** have direct baseband access to the Jio cellular network. To solve this, Jio and AMTelecom created an undocumented **remote cellular baseband telemetry tunnel** over TCP.

---

### B. The Undocumented TCP AT Command Server (Port 6666)

Running inside [`/usr/bin/QCMAP_ConnectionManager`](file:///home/gaurav/jiofi/rootfs/usr/bin/QCMAP_ConnectionManager) and backed by [`/usr/lib/libtask_mgr.so.1`](file:///home/gaurav/jiofi/rootfs/usr/lib/libtask_mgr.so.1) (`taskmgr/tcp_at_parser.cpp`):
* **Thread**: `vvm_tcp_server_thread`
* **Port**: **TCP 6666** (bound to `0.0.0.0` or the bridge interface `192.168.225.1`)
* **Commands Implemented**: `AT+CEVVMCMD` and `AT+CEVVMEV`

#### How JioCall Interacts with the Router
In JioCall's native engine (`lib/armeabi-v7a/libcomlib.so` from WIT Software's WCL stack — `PANIPluginMifiImpl.cpp`):
1. **Discovery**: When connected to the hotspot, the app polls:
   ```http
   POST http://192.168.225.1/cgi-bin/qcmap_web_cgi
   Content-Type: application/x-www-form-urlencoded

   Page=GetDefault
   ```
   The router returns the raw SIM IMSI, device model (`AR5800RJ`), and cellular registration state without authentication.
2. **PANI Socket Connect**: The app launches the `PANI-Mifi IO` worker thread and opens a raw TCP socket to `192.168.225.1:6666`.
3. **Activation (`AT+CEVVMCMD=1`)**:
   The app sends `AT+CEVVMCMD=1\r\n`.
   The router logs `tcp_at_cevvmcmd_cmd enter` -> `VVM ACTIVATE`.
4. **Event Subscription (`AT+CEVVMEV=1`)**:
   The app sends `AT+CEVVMEV=1\r\n`.
   The router logs `VVM tcp_at_cevvmev_cmd enter` and subscribes the TCP client to modem cell change events.
5. **Baseband Telemetry Stream**:
   The router queries the Qualcomm baseband via QMI NAS and streams unsolicited cell tower events to the client:
   ```text
   +CEVVMEV: <MCC><MNC><TAC><CellID>,...
   ```
   *(Internal router log: `[!!vvm_cevvm_event!!] EUTRA GCI mcc(%s), mnc(%s), tac(%d), cellid(%x)`)*
6. **SIP PANI Header Generation**:
   JioCall's `wcl::PANIPluginMifiImpl::onRecv` formats this data into the standard 3GPP PANI header:
   ```http
   P-Access-Network-Info: 3GPP-E-UTRAN-TDD;utran-cell-id-3gpp=4058740016010C612
   ```
   *(Where `405` = MCC, `874` = MNC, `0016` = TAC, `010C612` = Cell ID)*.

---

### C. Testing Port 6666 Yourself (Live Cellular Telemetry)

You can connect to this undocumented server from your PC, phone, or inside ADB shell using `netcat` or `telnet`:

```sh
# From a connected PC or phone terminal:
nc 192.168.225.1 6666

# Or inside ADB shell:
nc 127.0.0.1 6666
```

Once connected, enter:
```text
AT+CEVVMCMD=1
AT+CEVVMEV=1
```
The router will immediately respond with `OK` and stream live cell tower identity updates whenever the modem handovers occur. To stop:
```text
AT+CEVVMCMD=0
```

---

### D. SIP Signaling & Audio Path (SIP ALG)

* **Not a Local PBX**: The JioFi router does **not** run Asterisk or a local SIP server.
* **Direct IMS Core Connection**: The phone's SIP engine registers directly with Jio's IMS Core (`ims.mnc874.mcc405.3gppnetwork.org`) over UDP/TCP port 5060 or TLS 5061.
* **Kernel SIP ALG**: To allow bidirectional VoIP traffic through NAT without STUN/TURN, the JioFi kernel enables Qualcomm SIP ALG (`<EnableSIPAlg>1</EnableSIPAlg>` in [`/etc/mobileap_cfg.xml`](file:///home/gaurav/jiofi/rootfs/etc/mobileap_cfg.xml)). The kernel modules `nf_conntrack_sip` and `nf_nat_sip` dynamically inspect and rewrite IP addresses and UDP RTP ports inside SIP SDP payloads on the fly.
* **Secondary Provisioning**: For initial authentication, the app uses `https://config.rcs.mnc874.mcc405.pub.3gppnetwork.org/` to exchange an SMS-based OTP for permanent SIP digest credentials.

---

## 5. Proprietary Modem AT Diagnostic Commands

Registered by [`amt_atfwd_daemon`](file:///home/gaurav/jiofi/rootfs/usr/bin/amt_atfwd_daemon) via Qualcomm QMI ATCOP:

* `AT%DBGMODE=1` & `AT%DBGUSBSET=1`: Switches USB gadget to composition `02E1` with ADB (`ffs`) enabled and launches `/etc/init.d/adbd`.
* `AT%WLANFTM`: Stops Wi-Fi AP and starts `/usr/bin/ftmdaemon` (Qualcomm Factory Test Mode for RF calibration).
* `AT%WIFICAL`: Initiates Wi-Fi radio calibration.
* `AT%TCLED` / `AT%LEDON`: Runs hardware LED test sequences.
* `AT%GPKBUT`: Validates Power and WPS button GPIO triggers.
* `AT%BATL`: Queries raw PMIC battery voltage telemetry.
* `AT%FRST`: Dual Linux filesystem and baseband NV memory factory reset.

---

## 6. Undocumented Diagnostic Web APIs (AJAX Endpoints)

In addition to cell band locking, the `QCMAP_Web_CLIENT` daemon implements several hidden diagnostic queries that the Web UI either comments out or restricts to Level 1 (`administrator`) accounts:

### A. Raw RF Radio Measurements (`GetSignalStrength`)
The Web UI only shows a 5-bar icon. Calling `GetSignalStrength` returns true physical-layer modem metrics (RSRP, RSRQ, RSSI, and SINR):
```javascript
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: { Page: "GetSignalStrength", mask: 0, token: session_token },
    dataType: "text",
    success: function(res) { console.log("Raw RF Metrics:", res); }
});
```
* **RSRP** (Reference Signal Received Power): Actual received signal level in dBm.
* **RSRQ** (Reference Signal Received Quality): Signal quality including interference.
* **SINR** (Signal to Interference-plus-Noise Ratio): The single most critical metric for maximum throughput (higher is better).

### B. Hardware Performance & Crash Diagnostics (`GetSystemPerformance`)
Queries CPU and RAM limits, real-time data rates, and the hardware reboot reason:
```javascript
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: { Page: "GetSystemPerformance", mask: 0, token: session_token },
    dataType: "text",
    success: function(res) { console.log("System Performance:", res); }
});
```
Returns: `cpu_max_usg`, `cpu_min_usg`, `mem_max_usg`, `mem_min_usg`, `uplink_cur_usg`, `dwlink_cur_usg`, `device_time`, and `restart_reason` (e.g. kernel panic, watchdog timer, battery drop, or clean user restart).

### C. Configuration Backup & Restore (`RunBackupConfig` / `RunRestoreConfig`)
In [`setting/QCMAP_Firmware_Upgrade.html`](file:///home/gaurav/jiofi/personal_builds/sim_adb_build/extracted/907419386/rootfs/WEBSERVER/www/setting/QCMAP_Firmware_Upgrade.html), backup/restore buttons are hidden when `test_level == 3`. You can trigger them directly:
```javascript
// Backup config to downloadable file:
$.ajax({
    type: "POST",
    url: "cgi-bin/qcmap_web_cgi",
    data: { Page: "RunBackupConfig", mask: 0, token: session_token },
    dataType: "text",
    success: function(res) { console.log("Backup Path:", res); }
});
```

### D. Remote Web Management over LTE (`SetWebserverWWANAccess`)
Enables access to the router's web admin panel over the cellular WAN connection (disabled by default for security).

---

## 7. Qualcomm Baseband Diagnostic & RF Tools (On-Device)

The stock filesystem includes complete Qualcomm diagnostic logging binaries:

1. **`diag_socket_log`**: Streams Qualcomm DIAG packets (LTE PHY/MAC/RLC/RRC messages) over TCP to a remote PC running Wireshark or Qualcomm QXDM:
   ```sh
   diag_socket_log -a <PC_IP_ADDRESS> -p 2500
   ```
2. **`diag_mdlog`**: Mobile Diagnostic Logger. Records raw Qualcomm baseband packet traces directly to an attached MicroSD card (`/media/card`) without needing a computer attached.
3. **Wi-Fi Power & Regulatory Control (`iwpriv`)**:
   The Realtek RTL8189ES driver (`rtl8189es.ko`) supports raw driver parameter queries and TX power adjustments:
   ```sh
   # Dump current TX power limits per channel and rate:
   iwpriv wlan0 dump_txpwr_lmt

   # Override target TX power:
   iwpriv wlan0 mp_txpower ...
   ```

---

## 8. Sending and Reading SMS (Qualcomm Baseband AT Commands)

The stock AMTelecom Web UI completely omits an SMS inbox. However, the Qualcomm MDM9607 modem hardware fully supports 3GPP SMS transmission and reception using standard AT commands.

### A. SMS AT Command Reference

| Action | AT Command | Description |
|:---|:---|:---|
| **Text Mode** | `AT+CMGF=1` | Switch modem from PDU hex mode to human-readable ASCII text mode. |
| **Select Storage** | `AT+CPMS="SM","SM","SM"` | Select SIM card memory (`"SM"`) or router NVRAM (`"ME"`). |
| **List All SMS** | `AT+CMGL="ALL"` | Dump all stored incoming and outgoing SMS messages with index numbers. |
| **List Unread SMS** | `AT+CMGL="REC UNREAD"` | Query only new unread messages (useful for OTPs). |
| **Read Specific SMS** | `AT+CMGR=<index>` | Read message body and sender metadata at slot `<index>` (e.g. `AT+CMGR=1`). |
| **Send SMS** | `AT+CMGS="<phone_number>"` | Prompts with `> `. Enter message body, then send ASCII byte `0x1A` (Ctrl+Z). |
| **Delete Single SMS** | `AT+CMGD=<index>` | Delete message at slot `<index>` (e.g. `AT+CMGD=1`). |
| **Delete All SMS** | `AT+CMGD=1,4` | Purge entire SMS inbox from SIM memory. |

---

### B. Interactive Usage in ADB Shell

```sh
# 1. Stop qti_ppp to release /dev/smd8:
/etc/init.d/start_stop_qti_ppp_le stop

# 2. Set SMD kernel open timeout:
echo 10 > /sys/class/tty/smd8/open_timeout

# 3. Launch microcom:
microcom -t 1000 /dev/smd8
```

#### Reading All Messages (e.g. OTPs):
```text
AT+CMGF=1
AT+CPMS="SM","SM","SM"
AT+CMGL="ALL"
```
*Output:*
```text
+CMGL: 1,"REC READ","+919876543210",,"26/09/16,13:10:00+22"
Your OTP is 482910. Do not share this with anyone.
OK
```

#### Sending an SMS:
```text
AT+CMGF=1
AT+CMGS="+919876543210"
> Hello from JioFi!
<Press Ctrl+Z>
```
*Output:*
```text
+CMGS: 12
OK
```

*(Press **Ctrl + X** to exit microcom, then restart cellular data with `/etc/init.d/start_stop_qti_ppp_le start`)*.

---

### C. Automated Python CLI Tool (`jiofi_sms.py`)

A standalone python utility [`jiofi_sms.py`](jiofi_sms.py) is provided in the repository to manage SMS directly from your host PC over USB serial (`/dev/ttyUSB1` or Windows `COMx`) without restarting services:

```sh
# List all messages (clean formatted table)
python3 jiofi_sms.py --list

# Read a specific message by index:
python3 jiofi_sms.py --read 1

# Send an SMS:
python3 jiofi_sms.py --send "+919876543210" "Hello from my JioFi!"

# Delete a message:
python3 jiofi_sms.py --delete 1

# Delete all messages:
python3 jiofi_sms.py --delete-all
```
