#!/usr/bin/env bash
# ============================================================
#  install.sh — WiFiZer0 Setup & Dependency Installer
#  Platform : Kali Linux (Debian-based)
#  Run as   : sudo bash install.sh
#
#  What this script does:
#  1. Installs all system packages via apt
#  2. Creates WiFiZer0_Tools/ next to this script
#  3. Clones & builds eaphammer inside WiFiZer0_Tools/
#  4. Creates a Python3 venv (./venv/) and installs all
#     Python dependencies (ours + eaphammer's) into it
#  5. Patches wifi_pentest.sh to find the local eaphammer
#  6. Makes wifi_pentest.sh executable
#  7. Prints a final status report
# ============================================================

set -euo pipefail

# ────────────────────────────────────────────────────────────
#  COLOUR PALETTE
# ────────────────────────────────────────────────────────────
AM='\033[38;5;208m'  # amber / orange
GN='\033[38;5;82m'   # bright green
RD='\033[38;5;196m'  # red
YL='\033[38;5;226m'  # yellow
CY='\033[38;5;45m'   # cyan
WH='\033[1;37m'      # bright white
DM='\033[38;5;244m'  # dim grey
BD='\033[1m'         # bold
NC='\033[0m'         # reset

# ────────────────────────────────────────────────────────────
#  PATHS  (all relative to the directory holding install.sh)
# ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/WiFiZer0_Tools"
VENV_DIR="${SCRIPT_DIR}/venv"
VENV_PIP="${VENV_DIR}/bin/pip"
VENV_PYTHON="${VENV_DIR}/bin/python3"
EAPHAMMER_DIR="${TOOLS_DIR}/eaphammer"
EAPHAMMER_WRAPPER="${EAPHAMMER_DIR}/eaphammer"
REQ_FILE="${SCRIPT_DIR}/requirements.txt"
MAIN_SCRIPT="${SCRIPT_DIR}/wifi_pentest.sh"
LOG_FILE="${SCRIPT_DIR}/install.log"

# ────────────────────────────────────────────────────────────
#  TRACKING
# ────────────────────────────────────────────────────────────
declare -a INSTALLED=()
declare -a SKIPPED=()
declare -a FAILED=()
declare -a WARNINGS=()

# ────────────────────────────────────────────────────────────
#  HELPERS
# ────────────────────────────────────────────────────────────
log()  { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG_FILE"; }
ok()   { printf "${GN}  [+]${NC} %s\n"  "$*"; log "OK:   $*"; INSTALLED+=("$*"); }
skip() { printf "${CY}  [~]${NC} %s\n"  "$*"; log "SKIP: $*"; SKIPPED+=("$*");   }
warn() { printf "${YL}  [!]${NC} %s\n"  "$*"; log "WARN: $*"; WARNINGS+=("$*");  }
err()  { printf "${RD}  [-]${NC} %s\n"  "$*"; log "ERR:  $*"; FAILED+=("$*");    }
info() { printf "${CY}  [*]${NC} %s\n"  "$*"; log "INFO: $*"; }
step() { printf "\n${AM}${BD}  ══ %s ══${NC}\n" "$*"; log "STEP: $*"; }
die()  { printf "\n${RD}${BD}  FATAL: %s${NC}\n\n" "$*"; log "FATAL: $*"; exit 1; }

apt_install() {
    local pkg="$1"
    if dpkg -s "$pkg" &>/dev/null 2>&1; then
        skip "$pkg  (already installed)"
    else
        info "Installing $pkg ..."
        if apt-get install -y --no-install-recommends "$pkg" >> "$LOG_FILE" 2>&1; then
            ok "$pkg"
        else
            err "$pkg  (apt install failed — check $LOG_FILE)"
        fi
    fi
}

pip_install() {
    local pkg="$1"
    info "pip: $pkg"
    if "$VENV_PIP" install --quiet "$pkg" >> "$LOG_FILE" 2>&1; then
        ok "python: $pkg"
    else
        err "python: $pkg  (pip install failed)"
    fi
}

# ────────────────────────────────────────────────────────────
#  BANNER
# ────────────────────────────────────────────────────────────
clear
printf "${AM}${BD}"
if command -v figlet &>/dev/null; then
    figlet -f slant "WiFiZer0" 2>/dev/null | sed 's/^/  /' || true
else
    echo "  WiFiZer0"
fi
printf "${NC}"
printf "  ${CY}Wireless Penetration Testing Toolkit — Installer${NC}\n"
printf "  ${DM}────────────────────────────────────────────────────────${NC}\n"
printf "  ${WH}This will install all system packages, Python deps,${NC}\n"
printf "  ${WH}and clone EAPHammer into:${NC}\n"
printf "  ${AM}  %s${NC}\n" "$TOOLS_DIR"
printf "  ${DM}────────────────────────────────────────────────────────${NC}\n"
printf "  ${YL}For authorized testing only. Ensure written permission.${NC}\n\n"

# ────────────────────────────────────────────────────────────
#  PRE-FLIGHT CHECKS
# ────────────────────────────────────────────────────────────
step "Pre-flight checks"

# Must be root
if [[ $EUID -ne 0 ]]; then
    die "Run as root:  sudo bash install.sh"
fi
ok "Running as root"

# Must be on a Debian/Ubuntu/Kali system
if ! command -v apt-get &>/dev/null; then
    die "apt-get not found. This script requires a Debian-based OS (Kali Linux)."
fi
ok "apt-get available"

# Check internet connectivity
if ! curl -fs --max-time 5 https://github.com &>/dev/null; then
    warn "GitHub not reachable — eaphammer clone may fail."
fi

# Initialise log
: > "$LOG_FILE"
log "WiFiZer0 install started at $(date)"
log "SCRIPT_DIR=$SCRIPT_DIR"
log "TOOLS_DIR=$TOOLS_DIR"
log "VENV_DIR=$VENV_DIR"

# ────────────────────────────────────────────────────────────
#  DIRECTORY STRUCTURE
# ────────────────────────────────────────────────────────────
step "Creating directory structure"

mkdir -p "$TOOLS_DIR"
ok "Created: $TOOLS_DIR"

# ────────────────────────────────────────────────────────────
#  SYSTEM PACKAGE UPDATES
# ────────────────────────────────────────────────────────────
step "Updating apt package index"
info "Running apt-get update ..."
if apt-get update -qq >> "$LOG_FILE" 2>&1; then
    ok "apt-get update"
else
    warn "apt-get update had errors (continuing — may use cached index)"
fi

# ────────────────────────────────────────────────────────────
#  CORE SYSTEM TOOLS
# ────────────────────────────────────────────────────────────
step "Core wireless & capture tools"

apt_install "aircrack-ng"       # airmon-ng, airodump-ng, aireplay-ng, aircrack-ng
apt_install "hcxdumptool"       # PMKID / WPA capture
apt_install "hcxtools"          # hcxpcapngtool (hashcat conversion)
apt_install "tshark"            # EAPOL frame counting
apt_install "iw"                # interface management
apt_install "wireless-tools"    # iwconfig fallback
apt_install "net-tools"         # ifconfig fallback

step "Supporting tools"

apt_install "dialog"            # TUI framework
apt_install "tmux"              # multi-tab session manager
apt_install "figlet"            # ASCII banner art
apt_install "curl"              # internet checks / downloads
apt_install "git"               # cloning eaphammer
apt_install "wget"              # alternative downloader
apt_install "jq"                # JSON parsing (bettercap output)

step "WPS attack tools"

apt_install "reaver"            # WPS Pixie Dust + PIN brute
apt_install "bully"             # alternative WPS tool
# wash is bundled with reaver
if command -v wash &>/dev/null; then
    skip "wash  (bundled with reaver)"
else
    warn "wash not found — reaver package may be incomplete"
fi

step "MITM & cracking tools"

apt_install "bettercap"         # ARP spoof / network MITM
apt_install "hashcat"           # offline hash cracker
apt_install "john"              # JohnTheRipper (fallback cracker)

step "PSK verification, enumeration, and spoofing tools"

apt_install "wpasupplicant"     # wpa_supplicant + wpa_cli for PSK verification
apt_install "arp-scan"          # post-crack LAN host discovery
apt_install "nmap"              # post-crack network mapping
apt_install "macchanger"        # MAC address spoofing
# cewl is optional (ruby gem) — advisory warn only
command -v cewl &>/dev/null || warn "cewl not installed (optional for wordlist harvesting; gem install cewl)"

step "OUI vendor database"

apt_install "ieee-data"         # /usr/share/ieee-data/oui.txt
# Verify it landed
if [[ -f "/usr/share/ieee-data/oui.txt" ]]; then
    ok "OUI database: /usr/share/ieee-data/oui.txt"
else
    # Try alternative path / manual download
    oui_alt="/usr/share/wireshark/manuf"
    if [[ -f "$oui_alt" ]]; then
        warn "oui.txt not at expected path — found wireshark manuf at $oui_alt"
    else
        warn "OUI database not found — vendor lookup will be disabled"
    fi
fi

step "EAPHammer system dependencies"

apt_install "hostapd"           # underlying AP daemon
apt_install "dnsmasq"           # DHCP / DNS for rogue AP
apt_install "apache2"           # captive portal web server
apt_install "libssl-dev"        # OpenSSL headers (eaphammer build)
apt_install "libffi-dev"        # FFI (cryptography Python package)
apt_install "build-essential"   # gcc / make (native extension builds)
apt_install "pkg-config"        # library path resolution

step "Python3 build tools"

apt_install "python3"
apt_install "python3-pip"
apt_install "python3-venv"
apt_install "python3-dev"       # headers for native Python extensions

# ────────────────────────────────────────────────────────────
#  WORDLISTS
# ────────────────────────────────────────────────────────────
step "Wordlists"

apt_install "wordlists"         # fasttrack.txt, others

# Decompress rockyou.gz if not yet done
ROCKYOU="/usr/share/wordlists/rockyou.txt"
ROCKYOU_GZ="${ROCKYOU}.gz"
if [[ -f "$ROCKYOU" ]]; then
    skip "rockyou.txt  (already decompressed)"
elif [[ -f "$ROCKYOU_GZ" ]]; then
    info "Decompressing rockyou.gz ..."
    if gunzip -k "$ROCKYOU_GZ" >> "$LOG_FILE" 2>&1; then
        ok "rockyou.txt  (decompressed to /usr/share/wordlists/)"
    else
        err "rockyou.txt  (gunzip failed)"
    fi
else
    warn "rockyou.gz not found — install manually:  apt install wordlists"
fi

# ────────────────────────────────────────────────────────────
#  PYTHON VIRTUAL ENVIRONMENT
# ────────────────────────────────────────────────────────────
step "Python3 virtual environment"

if [[ -d "$VENV_DIR" && -x "$VENV_PYTHON" ]]; then
    skip "venv already exists at $VENV_DIR"
else
    info "Creating venv at $VENV_DIR ..."
    if python3 -m venv "$VENV_DIR" >> "$LOG_FILE" 2>&1; then
        ok "venv created: $VENV_DIR"
    else
        die "Failed to create Python venv.  Check: python3-venv installed?"
    fi
fi

info "Upgrading pip inside venv ..."
"$VENV_PIP" install --quiet --upgrade pip >> "$LOG_FILE" 2>&1 || true
ok "pip upgraded"

# ────────────────────────────────────────────────────────────
#  PYTHON DEPENDENCIES (requirements.txt)
# ────────────────────────────────────────────────────────────
step "Installing Python dependencies (requirements.txt)"

if [[ -f "$REQ_FILE" ]]; then
    info "Installing from $REQ_FILE ..."
    if "$VENV_PIP" install --quiet -r "$REQ_FILE" >> "$LOG_FILE" 2>&1; then
        ok "All packages from requirements.txt installed"
    else
        err "Some packages from requirements.txt failed — check $LOG_FILE"
        # Try installing individually so we know which ones failed
        while IFS= read -r line; do
            [[ "$line" =~ ^#   ]] && continue
            [[ -z "$line"      ]] && continue
            pip_install "$line"
        done < "$REQ_FILE"
    fi
else
    warn "requirements.txt not found at $REQ_FILE — skipping"
fi

# Additional packages useful for eaphammer that aren't in our requirements.txt
step "Additional Python packages for eaphammer"

for pkg in \
    "setuptools" \
    "wheel" \
    "cryptography" \
    "pyroute2" \
    "scapy" \
    "dbus-python" \
    "python-dateutil"; do
    info "pip: $pkg"
    "$VENV_PIP" install --quiet "$pkg" >> "$LOG_FILE" 2>&1 \
        && ok "python: $pkg" \
        || warn "python: $pkg  (optional — may not be needed on all setups)"
done

# ────────────────────────────────────────────────────────────
#  EAPHAMMER — clone & build in WiFiZer0_Tools/
# ────────────────────────────────────────────────────────────
step "EAPHammer (cloning into WiFiZer0_Tools/)"

EAPHAMMER_REPO="https://github.com/s0lst1c3/eaphammer.git"

if [[ -d "$EAPHAMMER_DIR/.git" ]]; then
    info "eaphammer already cloned — pulling latest ..."
    git -C "$EAPHAMMER_DIR" pull --ff-only >> "$LOG_FILE" 2>&1 \
        && ok "eaphammer updated (git pull)" \
        || warn "git pull failed — using existing clone"
else
    info "Cloning eaphammer from GitHub ..."
    if git clone --depth=1 "$EAPHAMMER_REPO" "$EAPHAMMER_DIR" >> "$LOG_FILE" 2>&1; then
        ok "eaphammer cloned to $EAPHAMMER_DIR"
    else
        err "git clone failed — check internet connection and $LOG_FILE"
        FAILED+=("eaphammer clone")
    fi
fi

# Install eaphammer's own Python requirements into our shared venv
if [[ -f "${EAPHAMMER_DIR}/requirements.txt" ]]; then
    info "Installing eaphammer Python requirements into venv ..."
    if "$VENV_PIP" install --quiet -r "${EAPHAMMER_DIR}/requirements.txt" \
            >> "$LOG_FILE" 2>&1; then
        ok "eaphammer Python requirements installed"
    else
        warn "Some eaphammer Python requirements failed — check $LOG_FILE"
    fi
fi

# Run eaphammer's own setup if present
if [[ -f "${EAPHAMMER_DIR}/setup.py" ]]; then
    info "Running eaphammer setup.py install ..."
    (
        cd "$EAPHAMMER_DIR"
        "$VENV_PYTHON" setup.py install --quiet >> "$LOG_FILE" 2>&1
    ) && ok "eaphammer setup.py complete" \
      || warn "eaphammer setup.py had errors (may still work) — check $LOG_FILE"
elif [[ -f "${EAPHAMMER_DIR}/setup.sh" ]]; then
    info "Running eaphammer setup.sh ..."
    (
        cd "$EAPHAMMER_DIR"
        bash setup.sh >> "$LOG_FILE" 2>&1
    ) && ok "eaphammer setup.sh complete" \
      || warn "eaphammer setup.sh had errors — check $LOG_FILE"
fi

# ── Create a venv-aware wrapper so wifi_pentest.sh can call eaphammer ──────
step "Creating eaphammer venv wrapper"

WRAPPER_PATH="${TOOLS_DIR}/eaphammer_wrapper.sh"
cat > "$WRAPPER_PATH" << WRAPPER_EOF
#!/usr/bin/env bash
# WiFiZer0 — eaphammer wrapper
# Activates the shared venv and delegates to eaphammer in WiFiZer0_Tools/
VENV_DIR="${VENV_DIR}"
EAPHAMMER_DIR="${EAPHAMMER_DIR}"
VENV_PYTHON="${VENV_DIR}/bin/python3"
source "\${VENV_DIR}/bin/activate"
exec "\${VENV_PYTHON}" "\${EAPHAMMER_DIR}/eaphammer.py" "\$@"
WRAPPER_EOF
chmod +x "$WRAPPER_PATH"
ok "Wrapper created: $WRAPPER_PATH"

# Also create a convenience symlink at WiFiZer0_Tools/eaphammer if the clone
# put the main script somewhere predictable
EAPHAMMER_PY="${EAPHAMMER_DIR}/eaphammer.py"
EAPHAMMER_BIN="${EAPHAMMER_DIR}/eaphammer"
if [[ -f "$EAPHAMMER_PY" && ! -x "$EAPHAMMER_BIN" ]]; then
    # Make the main python file executable and wrap it
    cat > "$EAPHAMMER_BIN" << EAP_EOF
#!/usr/bin/env bash
source "${VENV_DIR}/bin/activate"
exec "${VENV_PYTHON}" "${EAPHAMMER_PY}" "\$@"
EAP_EOF
    chmod +x "$EAPHAMMER_BIN"
    ok "eaphammer launcher created: $EAPHAMMER_BIN"
elif [[ -x "$EAPHAMMER_BIN" ]]; then
    # Prepend venv activation to the existing script
    ORIG_SHEBANG=$(head -1 "$EAPHAMMER_BIN")
    if [[ "$ORIG_SHEBANG" == "#!/usr/bin/env python"* ]]; then
        # Replace python shebang with our venv python
        sed -i "1s|.*|#!${VENV_PYTHON}|" "$EAPHAMMER_BIN"
        ok "eaphammer shebang patched to use venv python"
    else
        ok "eaphammer binary already executable: $EAPHAMMER_BIN"
    fi
fi

# ────────────────────────────────────────────────────────────
#  PATCH wifi_pentest.sh — point find_eaphammer() at local install
# ────────────────────────────────────────────────────────────
step "Patching wifi_pentest.sh to use local eaphammer"

if [[ -f "$MAIN_SCRIPT" ]]; then
    # Determine the best local eaphammer binary
    LOCAL_EAP=""
    [[ -x "$EAPHAMMER_BIN"    ]] && LOCAL_EAP="$EAPHAMMER_BIN"
    [[ -x "$WRAPPER_PATH"     ]] && LOCAL_EAP="$WRAPPER_PATH"

    if [[ -n "$LOCAL_EAP" ]]; then
        # Patch find_eaphammer() to also check WiFiZer0_Tools path
        # The function currently checks: command -v eaphammer || /opt/eaphammer/eaphammer
        # We insert our local path as first preference
        OLD_FIND='EAPHAMMER=$(command -v eaphammer 2>/dev/null \
        || { [[ -x "/opt/eaphammer/eaphammer" ]] && echo "/opt/eaphammer/eaphammer"; } \
        || echo "")'
        NEW_FIND="EAPHAMMER=\$(command -v eaphammer 2>/dev/null \\
        || { [[ -x \"${LOCAL_EAP}\" ]] && echo \"${LOCAL_EAP}\"; } \\
        || { [[ -x \"/opt/eaphammer/eaphammer\" ]] && echo \"/opt/eaphammer/eaphammer\"; } \\
        || echo \"\")"

        # Use python3 for the multi-line sed replacement (safer than sed)
        "$VENV_PYTHON" - << PYEOF >> "$LOG_FILE" 2>&1
import re, sys

script = open('${MAIN_SCRIPT}', 'r').read()
old = r"""EAPHAMMER=\$(command -v eaphammer 2>/dev/null \\\\
        || \\{ \\[\\[ -x "/opt/eaphammer/eaphammer" \\]\\] && echo "/opt/eaphammer/eaphammer"; \\} \\\\
        || echo "")"""
new = """EAPHAMMER=\$(command -v eaphammer 2>/dev/null \\\\
        || { [[ -x "${LOCAL_EAP}" ]] && echo "${LOCAL_EAP}"; } \\\\
        || { [[ -x "/opt/eaphammer/eaphammer" ]] && echo "/opt/eaphammer/eaphammer"; } \\\\
        || echo "")"""

# Simple literal replacement for the two find_eaphammer occurrences
OLD_LITERAL = 'EAPHAMMER=\$(command -v eaphammer 2>/dev/null \\\\\n        || { [[ -x "/opt/eaphammer/eaphammer" ]] && echo "/opt/eaphammer/eaphammer"; } \\\\\n        || echo "")'
NEW_LITERAL = 'EAPHAMMER=\$(command -v eaphammer 2>/dev/null \\\\\n        || { [[ -x "${LOCAL_EAP}" ]] && echo "${LOCAL_EAP}"; } \\\\\n        || { [[ -x "/opt/eaphammer/eaphammer" ]] && echo "/opt/eaphammer/eaphammer"; } \\\\\n        || echo "")'

updated = script.replace(OLD_LITERAL, NEW_LITERAL)
if updated != script:
    open('${MAIN_SCRIPT}', 'w').write(updated)
    print("Patched find_eaphammer() — inserted WiFiZer0_Tools path")
else:
    print("Pattern not matched — manual patch may be needed")
PYEOF
        ok "find_eaphammer() patched: $LOCAL_EAP added as first search path"
    else
        warn "No local eaphammer binary found — patch skipped (will fall back to system eaphammer)"
    fi

    # Update EAP_ACTIVE_CERT path if eaphammer uses a local cert dir
    LOCAL_CERT_DIR="${EAPHAMMER_DIR}/certs"
    if [[ -d "$LOCAL_CERT_DIR" ]]; then
        sed -i "s|EAP_ACTIVE_CERT=\"/etc/eaphammer/certs/active/fullchain.pem\"|EAP_ACTIVE_CERT=\"${LOCAL_CERT_DIR}/active/fullchain.pem\"|" \
            "$MAIN_SCRIPT" >> "$LOG_FILE" 2>&1 \
            && ok "EAP_ACTIVE_CERT patched to $LOCAL_CERT_DIR/active/fullchain.pem" \
            || warn "Could not patch EAP_ACTIVE_CERT (manual update may be needed)"
    fi

    chmod +x "$MAIN_SCRIPT"
    ok "wifi_pentest.sh marked executable"
else
    warn "wifi_pentest.sh not found at $MAIN_SCRIPT — skipping patch"
fi

# ────────────────────────────────────────────────────────────
#  VENV ACTIVATION HELPER
# ────────────────────────────────────────────────────────────
step "Creating venv activation helper"

ACTIVATE_HELPER="${SCRIPT_DIR}/activate_env.sh"
cat > "$ACTIVATE_HELPER" << ACTEOF
#!/usr/bin/env bash
# Source this file to activate the WiFiZer0 venv:
#   source activate_env.sh
VENV_DIR="${VENV_DIR}"
if [[ "\${BASH_SOURCE[0]}" == "\${0}" ]]; then
    echo "Source this file, don't run it:"
    echo "  source activate_env.sh"
    exit 1
fi
source "\${VENV_DIR}/bin/activate"
echo "WiFiZer0 venv activated — Python: \$(which python3)"
ACTEOF
chmod +x "$ACTIVATE_HELPER"
ok "activate_env.sh created"

# ────────────────────────────────────────────────────────────
#  UPDATE VENV PATH IN wifi_pentest.sh (sanity check)
# ────────────────────────────────────────────────────────────
step "Verifying venv path in wifi_pentest.sh"

if [[ -f "$MAIN_SCRIPT" ]]; then
    if grep -q "VENV_DIR=\"\${SCRIPT_DIR}/venv\"" "$MAIN_SCRIPT"; then
        ok "VENV_DIR in wifi_pentest.sh matches installer venv path"
    else
        warn "VENV_DIR in wifi_pentest.sh may differ from $VENV_DIR"
        warn "Expected: VENV_DIR=\"\${SCRIPT_DIR}/venv\""
    fi
fi

# ────────────────────────────────────────────────────────────
#  VERIFY KEY TOOL BINARIES
# ────────────────────────────────────────────────────────────
step "Binary verification"

declare -A TOOL_CHECK=(
    ["airmon-ng"]="aircrack-ng"
    ["airodump-ng"]="aircrack-ng"
    ["aireplay-ng"]="aircrack-ng"
    ["aircrack-ng"]="aircrack-ng"
    ["hcxdumptool"]="hcxdumptool"
    ["hcxpcapngtool"]="hcxtools"
    ["tshark"]="tshark"
    ["dialog"]="dialog"
    ["tmux"]="tmux"
    ["hashcat"]="hashcat"
    ["reaver"]="reaver"
    ["bully"]="bully"
    ["bettercap"]="bettercap"
    ["figlet"]="figlet"
    ["git"]="git"
)

printf "\n"
all_ok=1
for tool in "${!TOOL_CHECK[@]}"; do
    if command -v "$tool" &>/dev/null; then
        printf "  ${GN}[+]${NC} %-20s %s\n" "$tool" "$(command -v "$tool")"
    else
        printf "  ${RD}[!]${NC} %-20s NOT FOUND  (pkg: ${TOOL_CHECK[$tool]})\n" "$tool"
        all_ok=0
    fi
done

# eaphammer special check
EAP_FOUND=""
command -v eaphammer &>/dev/null           && EAP_FOUND="$(command -v eaphammer)"
[[ -x "$EAPHAMMER_BIN" ]]                 && EAP_FOUND="$EAPHAMMER_BIN"
[[ -x "$WRAPPER_PATH"  ]]                 && EAP_FOUND="$WRAPPER_PATH"
if [[ -n "$EAP_FOUND" ]]; then
    printf "  ${GN}[+]${NC} %-20s %s\n" "eaphammer" "$EAP_FOUND"
else
    printf "  ${RD}[!]${NC} %-20s NOT FOUND\n" "eaphammer"
    all_ok=0
fi

# wash (bundled with reaver)
if command -v wash &>/dev/null; then
    printf "  ${GN}[+]${NC} %-20s %s\n" "wash" "$(command -v wash)"
else
    printf "  ${YL}[~]${NC} %-20s not found (optional — WPS scan fallback used)\n" "wash"
fi

# OUI database
OUI_FILE="/usr/share/ieee-data/oui.txt"
if [[ -f "$OUI_FILE" ]]; then
    printf "  ${GN}[+]${NC} %-20s %s\n" "oui.txt" "$OUI_FILE"
else
    printf "  ${YL}[~]${NC} %-20s not found (vendor lookup disabled)\n" "oui.txt"
fi

# rockyou wordlist
if [[ -f "/usr/share/wordlists/rockyou.txt" ]]; then
    RKSZ=$(du -sh /usr/share/wordlists/rockyou.txt | cut -f1)
    printf "  ${GN}[+]${NC} %-20s /usr/share/wordlists/rockyou.txt [%s]\n" "rockyou.txt" "$RKSZ"
else
    printf "  ${YL}[~]${NC} %-20s not found — run: gunzip /usr/share/wordlists/rockyou.txt.gz\n" "rockyou.txt"
fi

# Python venv
if [[ -x "$VENV_PYTHON" ]]; then
    PY_VER=$("$VENV_PYTHON" --version 2>&1)
    printf "  ${GN}[+]${NC} %-20s %s  [%s]\n" "venv/python3" "$VENV_PYTHON" "$PY_VER"
else
    printf "  ${RD}[!]${NC} %-20s VENV NOT FOUND\n" "venv/python3"
    all_ok=0
fi

printf "\n"

# ────────────────────────────────────────────────────────────
#  PYTHON PACKAGE VERIFICATION
# ────────────────────────────────────────────────────────────
step "Python package verification"

PKG_REPORT=$("$VENV_PYTHON" - << 'PYEOF' 2>/dev/null
import importlib.util
pkgs = {
    'flask':          'Flask',
    'flask_cors':     'Flask-CORS',
    'flask_socketio': 'Flask-SocketIO',
    'OpenSSL':        'pyOpenSSL',
    'bs4':            'beautifulsoup4',
    'tqdm':           'tqdm',
    'pem':            'pem',
    'cryptography':   'cryptography',
    'scapy':          'scapy',
}
for mod, pkg in pkgs.items():
    found = importlib.util.find_spec(mod) is not None
    print(f"{'OK' if found else 'MISSING'}:{mod}:{pkg}")
PYEOF
)

while IFS=: read -r status mod pkg; do
    if [[ "$status" == "OK" ]]; then
        printf "  ${GN}[+]${NC} python: %-20s (%s)\n" "$mod" "$pkg"
    else
        printf "  ${RD}[!]${NC} python: %-20s (%s) — MISSING\n" "$mod" "$pkg"
        FAILED+=("python:$pkg")
    fi
done <<< "$PKG_REPORT"

# ────────────────────────────────────────────────────────────
#  DIRECTORY LAYOUT SUMMARY
# ────────────────────────────────────────────────────────────
step "Installation layout"

printf "\n"
printf "  ${WH}%s/${NC}\n" "$SCRIPT_DIR"
printf "  ${DM}├──${NC} ${AM}wifi_pentest.sh${NC}       main tool\n"
printf "  ${DM}├──${NC} ${AM}install.sh${NC}            this installer\n"
printf "  ${DM}├──${NC} ${AM}requirements.txt${NC}      Python deps list\n"
printf "  ${DM}├──${NC} ${AM}eaphammer_enterprise.conf${NC}  EAP cert config\n"
printf "  ${DM}├──${NC} ${AM}activate_env.sh${NC}       venv activation helper\n"
printf "  ${DM}├──${NC} ${CY}venv/${NC}                  Python3 virtual env\n"
printf "  ${DM}│   └──${NC} bin/python3, pip, ...\n"
printf "  ${DM}└──${NC} ${CY}WiFiZer0_Tools/${NC}\n"
if [[ -d "$EAPHAMMER_DIR" ]]; then
    printf "      ${DM}└──${NC} ${CY}eaphammer/${NC}          EAPHammer clone\n"
    [[ -x "$EAPHAMMER_BIN"  ]] && printf "          ${DM}├──${NC} eaphammer  (launcher)\n"
    [[ -x "$WRAPPER_PATH"   ]] && printf "      ${DM}├──${NC} eaphammer_wrapper.sh\n"
fi
printf "\n"

# ────────────────────────────────────────────────────────────
#  FINAL REPORT
# ────────────────────────────────────────────────────────────
step "Installation summary"

printf "\n"
printf "  ${GN}Installed / verified :  %d item(s)${NC}\n" "${#INSTALLED[@]}"
printf "  ${CY}Skipped (already OK) :  %d item(s)${NC}\n" "${#SKIPPED[@]}"
printf "  ${YL}Warnings             :  %d item(s)${NC}\n" "${#WARNINGS[@]}"
printf "  ${RD}Failures             :  %d item(s)${NC}\n" "${#FAILED[@]}"

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf "\n  ${YL}${BD}Warnings:${NC}\n"
    for w in "${WARNINGS[@]}"; do
        printf "  ${YL}  [!]${NC} %s\n" "$w"
    done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    printf "\n  ${RD}${BD}Failures:${NC}\n"
    for f in "${FAILED[@]}"; do
        printf "  ${RD}  [-]${NC} %s\n" "$f"
    done
    printf "\n  ${YL}See full log: ${WH}%s${NC}\n\n" "$LOG_FILE"
else
    printf "\n  ${GN}${BD}All critical components installed successfully!${NC}\n"
fi

printf "\n  ${DM}────────────────────────────────────────────────────────${NC}\n"
printf "  ${WH}Launch WiFiZer0:${NC}\n\n"
printf "  ${AM}  cd %s${NC}\n" "$SCRIPT_DIR"
printf "  ${AM}  tmux${NC}                   ${DM}# recommended: enables tab mode${NC}\n"
printf "  ${AM}  sudo ./wifi_pentest.sh${NC}  ${DM}# or without tmux for single-window mode${NC}\n"
printf "\n  ${DM}Log file: %s${NC}\n" "$LOG_FILE"
printf "  ${DM}────────────────────────────────────────────────────────${NC}\n\n"

# ────────────────────────────────────────────────────────────
#  HARDWARE RECOMMENDATIONS
# ────────────────────────────────────────────────────────────
printf "  ${WH}${BD}RECOMMENDED HARDWARE SETUP (2-3 Adapters)${NC}\n"
printf "  ${DM}────────────────────────────────────────────────────────${NC}\n\n"
printf "  ${AM}ADAPTER 1  — PRIMARY ATTACK ADAPTER  (Required)${NC}\n"
printf "  Role: Monitor mode + packet injection\n"
printf "  Used for: Scan, Handshake, PMKID, WPS, Rogue AP, EAP\n\n"
printf "  ${CY}  Model                   Chipset     Bands   Notes${NC}\n"
printf "  ${DM}  ─────────────────────────────────────────────────────${NC}\n"
printf "  ${GN}  Alfa AWUS036ACHM  ${NC}      MT7612U     2.4+5   Best all-rounder\n"
printf "  ${GN}  Alfa AWUS036ACM   ${NC}      MT7612U     2.4+5   Compact, same chip\n"
printf "      Alfa AWUS036ACH         RTL8812AU   2.4+5   Excellent range\n"
printf "      Panda PAU0D             MT7612U     2.4+5   Budget option\n"
printf "      Alfa AWUS036NHA         RTL8188CUS  2.4     2.4GHz only, great inject\n\n"
printf "  ${AM}ADAPTER 2  — SECOND MONITOR ADAPTER  (Recommended)${NC}\n"
printf "  Role: Parallel attack on a different band/channel\n"
printf "  Use: Same models as Adapter 1 (2nd identical unit works great)\n\n"
printf "  ${AM}ADAPTER 3  — MANAGED / CONNECTED ADAPTER  (For MITM)${NC}\n"
printf "  Role: Connected to target network for Bettercap MITM\n"
printf "  Use: Any adapter, including built-in laptop Wi-Fi\n\n"
printf "  ${CY}VERIFY INJECTION WORKS:${NC}\n"
printf "    sudo airmon-ng start wlan0\n"
printf "    sudo aireplay-ng --test wlan0mon\n"
printf "    ${DM}(look for: Injection is working!)${NC}\n\n"
printf "  ${CY}CHECK CURRENT ADAPTERS:${NC}\n"
printf "    iw dev              ${DM}# list wireless interfaces${NC}\n"
printf "    lsusb               ${DM}# show USB adapter chipset${NC}\n"
printf "    dmesg | tail -20    ${DM}# kernel driver messages${NC}\n"
printf "  ${DM}────────────────────────────────────────────────────────${NC}\n\n"
