#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/wifi_pentest.sh"

pass_count=0
fail_count=0

pass() {
    pass_count=$((pass_count + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    fail_count=$((fail_count + 1))
    printf '[FAIL] %s\n' "$1"
}

assert_eq() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        pass "$name"
    else
        fail "$name (got: '$got', want: '$want')"
    fi
}

assert_ok() {
    local name="$1"
    shift
    if "$@"; then
        pass "$name"
    else
        fail "$name"
    fi
}

assert_not_ok() {
    local name="$1"
    shift
    if "$@"; then
        fail "$name"
    else
        pass "$name"
    fi
}

if ! bash -n "$SCRIPT_PATH" >/dev/null 2>&1; then
    echo "Syntax check failed for ${SCRIPT_PATH}"
    exit 1
fi

# shellcheck source=/dev/null
WPT_LIBRARY_MODE=1 source "$SCRIPT_PATH"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Core validation helpers
assert_ok "validate_bssid accepts canonical MAC" validate_bssid "AA:BB:CC:DD:EE:FF"
assert_not_ok "validate_bssid rejects invalid MAC" validate_bssid "AA:BB:CC:DD:EE"
assert_ok "validate_channel accepts 2.4GHz channel" validate_channel "11"
assert_ok "validate_channel accepts 5GHz channel" validate_channel "149"
assert_not_ok "validate_channel rejects invalid channel" validate_channel "999"
assert_ok "validate_psk accepts valid ASCII PSK" validate_psk "Password123!"
assert_not_ok "validate_psk rejects short PSK" validate_psk "short1"
assert_not_ok "validate_psk rejects non-ASCII PSK" validate_psk "pässword123"

# Band helpers
SELECTED_BAND="2.4"
assert_eq "band_label 2.4" "$(band_label)" "2.4 GHz"
assert_eq "band_dir_name 2.4" "$(band_dir_name)" "2.4GHz"
assert_eq "band_airodump_flag 2.4" "$(band_airodump_flag)" "bg"

SELECTED_BAND="5"
assert_eq "band_label 5" "$(band_label)" "5 GHz"
assert_eq "band_dir_name 5" "$(band_dir_name)" "5GHz"
assert_eq "band_airodump_flag 5" "$(band_airodump_flag)" "a"

SELECTED_BAND="dual"
assert_eq "band_label dual" "$(band_label)" "2.4 + 5 GHz"
assert_eq "band_dir_name dual" "$(band_dir_name)" "dual"
assert_eq "band_airodump_flag dual" "$(band_airodump_flag)" "abg"

# Scope enforcement helper
SCOPE_FILE="${tmpdir}/scope.txt"
cat > "$SCOPE_FILE" <<'EOF'
# Scope list
AA:BB:CC:DD:EE:FF
CorpWiFi
EOF
assert_ok "scope_check matches scoped BSSID" scope_check "AA:BB:CC:DD:EE:FF" ""
assert_ok "scope_check matches scoped SSID" scope_check "11:22:33:44:55:66" "CorpWiFi"
assert_not_ok "scope_check blocks out-of-scope target" scope_check "11:22:33:44:55:66" "UnknownSSID"

# Output/wordlist helper paths
OUTPUT_DIR="${tmpdir}/output"
mkdir -p "$OUTPUT_DIR"
# shellcheck disable=SC2034
TARGET_SSID="CorpWiFi"
# shellcheck disable=SC2034
SELECTED_BAND="5"
outdir="$(make_outdir "handshake")"
if [[ -d "$outdir" && "$outdir" == *"/5GHz/"* ]]; then
    pass "make_outdir creates band-segmented path"
else
    fail "make_outdir creates band-segmented path"
fi

wordlist_file="$(generate_target_wordlist "CorpWiFi" "Acme")"
if [[ -f "$wordlist_file" ]]; then
    lines="$(wc -l < "$wordlist_file")"
    if [[ "$lines" -gt 20 ]]; then
        pass "generate_target_wordlist creates populated file"
    else
        fail "generate_target_wordlist creates populated file"
    fi
else
    fail "generate_target_wordlist creates file"
fi

# Live-scan reliability: if airodump exits immediately, function should not
# sleep for the full requested duration.
# shellcheck disable=SC2034
TARGET_BSSID="AA:BB:CC:DD:EE:FF"
# shellcheck disable=SC2034
TARGET_CHANNEL="6"
# shellcheck disable=SC2034
LAST_IFACE="wlan0mon"
# shellcheck disable=SC2034
GLOBAL_IFACE=""

iw() {
    if [[ "${1:-}" == "dev" && "${3:-}" == "info" ]]; then
        cat <<'EOF'
Interface wlan0mon
	type monitor
EOF
        return 0
    fi
    return 0
}

airodump-ng() {
    return 1
}

_scan_started=$SECONDS
mapfile -t _scan_clients < <(_live_scan_clients "wlan0mon" "60")
_scan_elapsed=$((SECONDS - _scan_started))
if (( _scan_elapsed <= 5 )); then
    pass "live scan exits quickly when capture process dies"
else
    fail "live scan exits quickly when capture process dies (elapsed: ${_scan_elapsed}s)"
fi

unset -f iw airodump-ng

# AP discovery checklist regression: Space key must toggle, not exit.
mapfile -t _sel_toggle_empty < <(_dialog_checklist_toggle_selection 2)
assert_eq "checklist toggle adds unselected index" "${_sel_toggle_empty[*]-}" "2"

mapfile -t _sel_toggle_remove < <(_dialog_checklist_toggle_selection 2 1 2 3)
assert_eq "checklist toggle removes selected index" "${_sel_toggle_remove[*]-}" "1 3"

mapfile -t _sel_toggle_append < <(_dialog_checklist_toggle_selection 2 1 3)
assert_eq "checklist toggle appends newly selected index" "${_sel_toggle_append[*]-}" "1 3 2"

# Audit risk scorer sanity checks
IFS='|' read -r _risk_score _risk_sev _risk_find _risk_rem <<< "$(ap_risk_assess "OPN" "" "")"
assert_eq "ap_risk_assess open network severity" "$_risk_sev" "Critical"
assert_ok "ap_risk_assess open network score high" test "$_risk_score" -ge 80

IFS='|' read -r _risk_score2 _risk_sev2 _risk_find2 _risk_rem2 <<< "$(ap_risk_assess "WPA3" "SAE" "required")"
assert_eq "ap_risk_assess strong WPA3 severity" "$_risk_sev2" "Low"

echo
echo "Self-test summary: ${pass_count} passed, ${fail_count} failed"
[[ "$fail_count" -eq 0 ]]
