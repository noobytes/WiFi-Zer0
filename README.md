# WiFi-Zer0

> **For authorized penetration testing only. Always obtain written permission before use.**

WiFi-Zer0 is a wireless penetration testing toolkit for Kali Linux. It provides a terminal-based menu interface (built on `dialog` + `tmux`) that wraps industry-standard tools like `aircrack-ng`, `eaphammer`, `bettercap`, and `hashcat` into a unified, guided workflow.

---

## Features

| Category | Capabilities |
|---|---|
| **Scanning** | 2.4 GHz, 5 GHz, and dual-band AP/client discovery with persistent database |
| **WPA2/WPA3 Attacks** | PMKID capture, 4-way handshake capture, deauthentication |
| **WPS Attacks** | Pixie Dust, brute-force, specific PIN |
| **WEP Attacks** | ARP replay, fragmentation, ChopChop, auto mode |
| **Enterprise (802.1X)** | EAP evil twin via eaphammer — PEAP, TTLS, TLS, FAST |
| **Evil Twin / Rogue AP** | KARMA/MANA open & WPA modes, captive portal |
| **MITM** | Bettercap-based ARP spoofing, DNS spoofing, SSL stripping |
| **Password Cracking** | Hashcat integration — wordlist, rules, mask, and combo modes |
| **Hidden SSID Discovery** | Targeted probe-response capture to reveal hidden networks |
| **PSK Verification** | Confirm a recovered passphrase connects to the target AP |
| **MAC Spoofing** | Random, specific, or preserve-original modes per interface |
| **TX Power Control** | Adjust transmit power per session |
| **Scope Enforcement** | Warn when a target BSSID falls outside the defined engagement scope |
| **Wordlist Manager** | Generate and manage custom wordlists per engagement |
| **Engagement Profiles** | Save and restore named engagement configurations |
| **Auto-Attack Pipeline** | Automated PMKID → handshake → crack chain |
| **Session Persistence** | AP/client database and target state survive across runs |

---

## Requirements

- **OS:** Kali Linux (Debian-based)
- **Privileges:** Root (required by wireless tools)
- **Hardware:** Wireless adapter capable of monitor mode and packet injection

### System Dependencies (installed automatically by `install.sh`)

- `aircrack-ng` suite (`airodump-ng`, `aireplay-ng`, `airmon-ng`, `airgraph-ng`)
- `hostapd` / `hostapd-wpe`
- `eaphammer`
- `bettercap`
- `hashcat`
- `tmux`
- `dialog`
- `macchanger`
- `iw`, `iwconfig`, `rfkill`

### Python Dependencies

```
beautifulsoup4>=4.12.0
flask>=3.0.0
flask-cors>=4.0.0
flask-socketio>=5.3.0
python-engineio>=4.9.0
pyOpenSSL>=24.0.0
pem>=23.1.0
pywebcopy>=7.0.0
tqdm>=4.66.0
```

---

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/WiFi-Zer0.git
cd WiFi-Zer0
sudo bash install.sh
```

The installer will:
1. Install all system packages via `apt`
2. Clone and build `eaphammer` into `WiFiZer0_Tools/`
3. Create a Python virtual environment (`./venv/`) and install Python dependencies
4. Patch `wifi_pentest.sh` to locate the local eaphammer build
5. Make `wifi_pentest.sh` executable

---

## Usage

```bash
sudo bash wifi_pentest.sh
```

On first launch, WiFi-Zer0 will offer to start a `tmux` session so each attack runs in its own named tab. The main menu guides you through interface selection, scanning, target locking, and attack execution.

### Output

All session data is saved under `./wpt_output/`:

| File/Dir | Contents |
|---|---|
| `ap_database.tsv` | All APs seen across sessions |
| `client_database.tsv` | All clients seen across sessions |
| `session.sh` | Current engagement target state |
| `scope.txt` | In-scope BSSID list for scope enforcement |
| `profiles/` | Saved engagement profiles |
| Capture files | `.pcap`, `.hc22000`, and credential logs per attack |

---

## Legal Disclaimer

This tool is intended for **authorized security assessments only**. Use against networks without explicit written permission from the owner is illegal and unethical. The authors assume no liability for misuse.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
