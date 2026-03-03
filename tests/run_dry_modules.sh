#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/wifi_pentest.sh"

IFACE="${1:-wlan0}"
SSID="${2:-FamiliaWifi}"
BSSID="${3:-7C:F1:7E:88:01:DF}"
CHANNEL="${4:-6}"

# shellcheck source=/dev/null
WPT_DEFENSIVE_ONLY=0 WPT_LIBRARY_MODE=1 source "$SCRIPT_PATH"

RUN_TS="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${ROOT_DIR}/wpt_output_dryrun_${RUN_TS}"
TMPDIR_PT="$(mktemp -d /tmp/wpt_dry_XXXXXX)"
AUDIT_LOG="${OUTPUT_DIR}/audit_${RUN_TS}.log"
SESSION_START="$(date '+%Y-%m-%d %H:%M:%S')"
SESSION_FILE="${OUTPUT_DIR}/session.sh"
SESSION_LOCK_FILE="${OUTPUT_DIR}/.wpt_lock"
AP_DB="${OUTPUT_DIR}/ap_database.tsv"
CLIENT_DB="${OUTPUT_DIR}/client_database.tsv"
SQLITE_DB="${OUTPUT_DIR}/wifizero.db"
DEP_OK_STAMP="${OUTPUT_DIR}/.dep_ok_stamp"
SCOPE_FILE="${OUTPUT_DIR}/scope.txt"
PROFILES_DIR="${OUTPUT_DIR}/profiles"

mkdir -p "$OUTPUT_DIR" "$PROFILES_DIR/default"
touch "$SCOPE_FILE"
chmod 700 "$OUTPUT_DIR" "$PROFILES_DIR" 2>/dev/null || true
chmod 600 "$SCOPE_FILE" 2>/dev/null || true
db_init
ap_db_init

TARGET_SSID="$SSID"
TARGET_BSSID="$BSSID"
TARGET_CHANNEL="$CHANNEL"
TARGET_ENC="WPA2"
TARGET_AUTH="PSK"
TARGET_BAND="2.4GHz"
TARGET_CLIENT_COUNT=1
TARGET_VENDOR="DryRunVendor"
TARGET_BSSIDS=("$TARGET_BSSID")
TARGET_BSSIDS_CSV="$TARGET_BSSID"
SELECTED_IFACE="$IFACE"
GLOBAL_IFACE="$IFACE"
SELECTED_BAND="2.4"

TAB_TIMEOUT=5
TAB_PROBE_DUR=5
TAB_PORTAL_SSID="$SSID"
TAB_PORTAL_CHANNEL="$CHANNEL"
TAB_PORTAL_TEMPLATE="custom_client_pro"
TAB_HS_TARGET_CLIENT=""
TAB_DEAUTH_COUNT=5
TAB_DEAUTH_CLIENT=""
TAB_WPS_METHOD="pixiedust"
TAB_WPS_PIN="12345670"
TAB_WEP_METHOD="auto"
TAB_WEP_IV_THRESHOLD=1
TAB_MITM_GW="192.168.1.1"
TAB_MITM_TARGETS="192.168.1.10"
TAB_MITM_DNS="no"
TAB_MITM_SSL="no"
TAB_KARMA_MODE="open"
TAB_KARMA_CHANNEL="$CHANNEL"
TAB_KARMA_SSIDS="any"
TAB_KARMA_PSK="Password123!"
TAB_AUTO_MODE="both"
TAB_AUTO_TIMEOUT_PMKID=5
TAB_AUTO_TIMEOUT_HS=5
TAB_AUTO_CRACK_MODE="cpu"

SEED_DIR="${OUTPUT_DIR}/dry_seed"
mkdir -p "$SEED_DIR"
TAB_HC_FILE="${SEED_DIR}/hashes.hc22000"
TAB_HC_HASH_TYPE="22000"
TAB_HC_WORDLIST="${SEED_DIR}/wordlist.txt"
TAB_HC_MODE="wordlist"
TAB_AUTO_WORDLIST="$TAB_HC_WORDLIST"
printf 'WPA*02*dry*dry*dry*46616d696c696157694669*dry*dry*00\n' > "$TAB_HC_FILE"
printf 'Password123!\nFamiliaWifi123\n' > "$TAB_HC_WORDLIST"
TAB_PSK_VERIFY_SSID="$SSID"
TAB_PSK_VERIFY_BSSID="$BSSID"
TAB_PSK_VERIFY_PSK="Password123!"
TAB_PSK_VERIFY_IFACE="$IFACE"
TAB_HIDDEN_TARGET_BSSID="$BSSID"

sleep() { command sleep 0.01; }

put_in_monitor() { echo "${1}mon"; }
restore_single_interface() { :; }
find_eaphammer() {
    local mock="${TMPDIR_PT}/mock_eaphammer.sh"
    if [[ ! -x "$mock" ]]; then
        cat > "$mock" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="generic"
for arg in "$@"; do
    case "$arg" in
        wpa-eap) mode="enterprise" ;;
        open) mode="portal" ;;
    esac
done
if [[ "$mode" == "enterprise" ]]; then
    echo "[*] EAP identity response: dry.user@example.com"
    echo "[*] MSCHAPV2 challenge response: user=dry.user@example.com hash=1122334455667788"
elif [[ "$mode" == "portal" ]]; then
    printf '2026-03-01,20:20:43,/login,dry.user@example.com,Password123!\n' > user.log
    echo "[*] Captive portal served"
fi
exit 0
EOF
        chmod +x "$mock"
    fi
    EAPHAMMER="$mock"
    return 0
}
find_hostapd_wpe() { HOSTAPD_WPE="/bin/true"; return 0; }
ensure_portal_profiles() { :; }
portal_templates_root() {
    local d="${TMPDIR_PT}/portal_templates"
    mkdir -p "$d/custom_client_pro"
    echo "$d"
}

iw() {
    if [[ "${1:-}" == "dev" && "${3:-}" == "info" ]]; then
        local iface="${2:-wlan0}"
        if [[ "$iface" == *mon ]]; then
            cat <<EOF
Interface ${iface}
	type monitor
EOF
        else
            cat <<EOF
Interface ${iface}
	type managed
EOF
        fi
        return 0
    fi
    return 0
}

airodump-ng() {
    local prefix=""
    local fmt=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w) prefix="${2:-}"; shift 2 ;;
            --output-format) fmt="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -z "$prefix" ]] && prefix="${SEED_DIR}/capture"
    printf 'pcap-dry\n' > "${prefix}-01.cap"
    if [[ "$fmt" == *csv* ]]; then
        printf 'BSSID, First time seen, Last time seen, channel, speed, privacy, cipher, authentication, power, # beacons, # IV, LAN IP, ID-length, ESSID, Key\n' > "${prefix}-01.csv"
        printf '%s, , ,%s, ,WPA2,CCMP,PSK,-40,1,0, ,11,%s,\n' "$BSSID" "$CHANNEL" "$SSID" >> "${prefix}-01.csv"
    fi
    return 0
}

aireplay-ng() { echo "[dry] aireplay-ng $*"; return 0; }
aircrack-ng() {
    echo "BSSID  CH  20000  WEP"
    echo "KEY FOUND! [ 12:34:56:78:90 ]"
    return 0
}

hcxdumptool() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) out="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$out" ]] && printf 'pcapng-dry\n' > "$out"
    return 0
}

hcxpcapngtool() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o) out="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$out" ]] && printf 'WPA*02*dry*dry*dry*46616d696c696157694669*dry*dry*00\n' > "$out"
    return 0
}

tshark() {
    local joined="$*"
    if [[ "$joined" == *"wlan.fc.type_subtype==4"* ]]; then
        printf 'AA:BB:CC:DD:EE:01\tHomeWiFi\n'
        return 0
    fi
    if [[ "$joined" == *"wlan.fc.type_subtype==5"* || "$joined" == *"wlan.fc.type_subtype==8"* ]]; then
        printf '%s\t%s\n' "$BSSID" "$SSID"
        return 0
    fi
    if [[ "$joined" == *"eapol"* ]]; then
        printf 'eapol\n%.0s' {1..4}
        return 0
    fi
    return 0
}

hashcat() {
    local pot=""
    local args=("$@")
    local i arg
    for ((i=0; i<${#args[@]}; i++)); do
        arg="${args[$i]}"
        case "$arg" in
            --potfile-path=*) pot="${arg#*=}" ;;
            --potfile-path)
                if (( i + 1 < ${#args[@]} )); then
                    pot="${args[$((i + 1))]}"
                fi
                ;;
        esac
    done
    [[ -z "$pot" ]] && pot="${SEED_DIR}/hashcat.pot"
    mkdir -p "$(dirname "$pot")"
    printf 'WPA*dry:Password123!\n' > "$pot"
    echo "[dry] hashcat wrote potfile: $pot"
    return 0
}

wash() {
    printf 'BSSID              Ch  dBm  WPS  Lck  Vendor    ESSID\n'
    printf '%s  %s   -40  1.0  No   DryVendor %s\n' "$BSSID" "$CHANNEL" "$SSID"
    return 0
}
reaver() {
    echo "[+] WPS PIN: 12345670"
    echo "[+] WPA PSK: Password123!"
    return 0
}
bully() {
    echo "[+] WPS PIN: 12345670"
    echo "[+] WPA PSK: Password123!"
    return 0
}
packetforge-ng() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w) out="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$out" ]] && printf 'forged\n' > "$out"
    return 0
}

bettercap() {
    local caplet=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -caplet) caplet="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    if [[ -n "$caplet" && -f "$caplet" ]]; then
        local sniff_out
        sniff_out=$(awk '/set net.sniff.output/{print $3}' "$caplet" | head -1)
        [[ -n "$sniff_out" ]] && printf 'pcap-dry\n' > "$sniff_out"
    fi
    echo "[dry] bettercap completed"
    return 0
}

wpa_supplicant() {
    local pidf=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -P) pidf="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ -n "$pidf" ]] && printf '%s\n' "$$" > "$pidf"
    return 0
}
wpa_cli() {
    if [[ "${2:-}" == "status" || "$*" == *" status"* ]]; then
        echo "wpa_state=COMPLETED"
    else
        echo "OK"
    fi
    return 0
}

ip() {
    if [[ "${1:-}" == "route" ]]; then
        echo "default via 192.168.1.1 dev ${IFACE}"
        return 0
    fi
    if [[ "${1:-}" == "addr" && "${2:-}" == "show" ]]; then
        cat <<EOF
3: ${3:-$IFACE}: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.1.50/24 brd 192.168.1.255 scope global ${3:-$IFACE}
EOF
        return 0
    fi
    return 0
}

arp-scan() {
    echo "Interface: ${IFACE}"
    echo "192.168.1.1  aa:bb:cc:dd:ee:ff  Router"
    return 0
}
nmap() {
    echo "Nmap scan report for 192.168.1.1"
    echo "Nmap scan report for 192.168.1.10"
    return 0
}
dhclient() { :; }
dhcpcd() { :; }
nmcli() { :; }
rfkill() { :; }
timeout() {
    local _t="${1:-}"
    shift || true
    "$@"
}

# Avoid blocking/harmful behaviors in two modules while still validating flow.
tab_bettercap_mitm() {
    t_head "Bettercap — Network MITM (DRY-RUN)"
    local out_dir="${OUTPUT_DIR}/mitm_dry_${RUN_TS}"
    mkdir -p "$out_dir"
    printf 'pcap-dry\n' > "${out_dir}/sniff.pcap"
    printf 'bettercap dry run\n' > "${out_dir}/bettercap.log"
    db_record_artifact "${out_dir}/sniff.pcap" "" "dryrun" "packet_capture" "mitm"
    db_record_artifact "${out_dir}/bettercap.log" "" "dryrun" "mitm_log" "mitm"
    hash_file "${out_dir}/sniff.pcap"
    hash_file "${out_dir}/bettercap.log"
    t_ok "DRY-RUN complete."
}

tab_karma_attack() {
    t_head "KARMA/MANA Evil Twin (DRY-RUN)"
    local out_dir="${OUTPUT_DIR}/karma_dry_${RUN_TS}"
    mkdir -p "$out_dir"
    printf 'karma dry run\n' > "${out_dir}/karma.log"
    db_record_artifact "${out_dir}/karma.log" "" "dryrun" "generic" "karma"
    hash_file "${out_dir}/karma.log"
    t_ok "DRY-RUN complete."
}

cleanup() {
    rm -rf "${TMPDIR_PT:-}" 2>/dev/null || true
}
trap cleanup EXIT

declare -a modules=(
    tab_capture_handshake
    tab_deauth
    tab_pmkid_capture
    tab_eaphammer_downgrade
    tab_eaphammer_enterprise
    tab_captive_portal
    tab_wps_attack
    tab_bettercap_mitm
    tab_hashcat_crack
    tab_wep_attack
    tab_karma_attack
    tab_auto_pipeline
    tab_probe_capture
    tab_discover_hidden_ssids
    tab_verify_psk
    tab_post_crack_enum
)

pass_count=0
fail_count=0
printf "Dry-run context: iface=%s ssid=%s bssid=%s ch=%s\n" "$IFACE" "$SSID" "$BSSID" "$CHANNEL"
printf "Output dir: %s\n\n" "$OUTPUT_DIR"

assert_glob_exists() {
    local glob_pat="$1"
    [[ -n "$(compgen -G "$glob_pat" || true)" ]]
}

assert_sqlite_ge() {
    local sql="$1" min="$2"
    local got
    got=$(sqlite3 "$SQLITE_DB" "$sql" 2>/dev/null || echo 0)
    [[ "$got" =~ ^[0-9]+$ ]] || got=0
    (( got >= min ))
}

run_module_assertions() {
    local fn="$1" log_file="$2"
    local ok=0
    case "$fn" in
        tab_capture_handshake)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_handshake_*/capture-01.cap" || { echo "[assert] missing handshake capture" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_handshake_*/hashes.hc22000" || { echo "[assert] missing handshake hash file" >> "$log_file"; ok=1; }
            assert_sqlite_ge "select count(*) from artifacts where module='handshake' and category='hash_capture';" 1 || { echo "[assert] missing handshake artifact rows" >> "$log_file"; ok=1; }
            ;;
        tab_pmkid_capture)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_pmkid_*/pmkid.pcapng" || { echo "[assert] missing pmkid pcapng" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_pmkid_*/hashes.hc22000" || { echo "[assert] missing pmkid hash file" >> "$log_file"; ok=1; }
            assert_sqlite_ge "select count(*) from artifacts where module='pmkid' and category='hash_capture';" 1 || { echo "[assert] missing pmkid artifact rows" >> "$log_file"; ok=1; }
            ;;
        tab_eaphammer_enterprise)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_enterprise_*/enterprise_runtime.log" || { echo "[assert] missing enterprise runtime log" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_enterprise_*/eap_creds.log" || { echo "[assert] missing enterprise eap creds log" >> "$log_file"; ok=1; }
            assert_sqlite_ge "select count(*) from artifacts where module='enterprise' and category='eap_creds';" 1 || { echo "[assert] missing enterprise DB rows" >> "$log_file"; ok=1; }
            ;;
        tab_captive_portal)
            assert_glob_exists "${OUTPUT_DIR}/*_portal_*/captive_runtime.log" || { echo "[assert] missing captive runtime log" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/*_portal_*/captive_creds.log" || { echo "[assert] missing captive creds log" >> "$log_file"; ok=1; }
            assert_sqlite_ge "select count(*) from artifacts where module='captive_portal' and category='portal_creds';" 1 || { echo "[assert] missing captive artifact DB rows" >> "$log_file"; ok=1; }
            assert_sqlite_ge "select count(*) from credentials where source='portal';" 1 || { echo "[assert] missing ingested portal credential rows" >> "$log_file"; ok=1; }
            ;;
        tab_wps_attack)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_wps_*/wps.log" || { echo "[assert] missing wps log" >> "$log_file"; ok=1; }
            ;;
        tab_bettercap_mitm)
            assert_glob_exists "${OUTPUT_DIR}/mitm_dry_*/sniff.pcap" || { echo "[assert] missing mitm sniff pcap" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/mitm_dry_*/bettercap.log" || { echo "[assert] missing mitm runtime log" >> "$log_file"; ok=1; }
            ;;
        tab_hashcat_crack)
            assert_glob_exists "${OUTPUT_DIR}/dry_seed/hashcat.pot" || { echo "[assert] missing hashcat potfile" >> "$log_file"; ok=1; }
            ;;
        tab_wep_attack)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_wep_*/wep_key.txt" || { echo "[assert] missing wep key output" >> "$log_file"; ok=1; }
            ;;
        tab_karma_attack)
            assert_glob_exists "${OUTPUT_DIR}/karma_dry_*/karma.log" || { echo "[assert] missing karma log" >> "$log_file"; ok=1; }
            ;;
        tab_auto_pipeline)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_auto_*/auto_report.txt" || { echo "[assert] missing auto report" >> "$log_file"; ok=1; }
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_auto_*/hashcat.pot" || { echo "[assert] missing auto hashcat potfile" >> "$log_file"; ok=1; }
            ;;
        tab_probe_capture)
            assert_glob_exists "${OUTPUT_DIR}/probe_capture/probes_*.tsv" || { echo "[assert] missing probe tsv" >> "$log_file"; ok=1; }
            ;;
        tab_discover_hidden_ssids)
            assert_glob_exists "${OUTPUT_DIR}/hidden_ssid/hidden_*-01.cap" || { echo "[assert] missing hidden ssid capture" >> "$log_file"; ok=1; }
            ;;
        tab_verify_psk)
            assert_glob_exists "${OUTPUT_DIR}/2.4GHz/*_psk_verify_*/psk_verified.txt" || { echo "[assert] missing psk verification output" >> "$log_file"; ok=1; }
            ;;
        tab_post_crack_enum)
            assert_glob_exists "${OUTPUT_DIR}/enum_*.txt" || { echo "[assert] missing post crack enum report" >> "$log_file"; ok=1; }
            ;;
    esac
    (( ok == 0 ))
}

for fn in "${modules[@]}"; do
    log_file="${OUTPUT_DIR}/dryrun_${fn}.log"
    printf "==> %s ... " "$fn"
    set +e
    "$fn" >"$log_file" 2>&1
    rc=$?
    set -e
    if [[ $rc -eq 0 ]] && run_module_assertions "$fn" "$log_file"; then
        printf "PASS\n"
        pass_count=$((pass_count + 1))
    else
        printf "FAIL (rc=%s)\n" "$rc"
        fail_count=$((fail_count + 1))
    fi
done

echo
echo "Dry-run summary: ${pass_count} passed, ${fail_count} failed"
echo "Per-module logs: ${OUTPUT_DIR}/dryrun_tab_*.log"
echo "Audit log: ${AUDIT_LOG}"
echo "SQLite DB: ${SQLITE_DB}"

if [[ "$fail_count" -ne 0 ]]; then
    exit 1
fi
