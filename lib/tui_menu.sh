#!/usr/bin/env bash
# Modular compact TUI menu for WiFiZer0.
# This file overrides main_menu() while keeping main_menu_classic() available.

_TUI_LAST_MAIN="r"
_TUI_LAST_SESSION="settings"
_TUI_LAST_RECON="scan"
_TUI_LAST_ATTACK="scan"
_TUI_LAST_POST="harvest"
_TUI_LAST_MANAGE="tasks"

_tui_apfx() {
    [[ -n "${TARGET_BSSID:-}" ]] && echo "[>]" || echo "[!]"
}

_tui_scope_count() {
    [[ -f "${SCOPE_FILE:-}" ]] || { echo 0; return; }
    grep -cv '^[[:space:]]*#' "$SCOPE_FILE" 2>/dev/null || echo 0
}

_tui_recommended_module() {
    [[ -z "${TARGET_BSSID:-}" ]] && { echo "scan"; return; }
    local enc="${TARGET_ENC^^}" auth="${TARGET_AUTH^^}"
    if [[ "$auth" == *"MGT"* ]]; then
        echo "db"
    elif [[ "$enc" == *"WPA3"* && "$enc" == *"WPA2"* ]]; then
        echo "report"
    elif [[ "$enc" == *"WPA3"* ]]; then
        echo "report"
    elif [[ "$enc" == *"OPN"* || -z "$enc" ]]; then
        echo "probe"
    elif [[ "$enc" == *"WEP"* ]]; then
        echo "report"
    else
        echo "probe"
    fi
}

_tui_recommended_text() {
    case "$(_tui_recommended_module)" in
        scan)   echo "Recon scan (no target selected yet)" ;;
        db)     echo "Review AP/client DB posture for selected target" ;;
        probe)  echo "Passive client probe visibility check" ;;
        report) echo "Generate remediation report and findings" ;;
        *)      echo "Recon scan and posture validation" ;;
    esac
}

_tui_confirm_high_impact() {
    local action="$1" title="" body="" height=13 width=70
    case "$action" in
        deauth)
            title=" Confirm Deauthentication "
            body="\n  This action will actively disconnect client devices.\n\n  Ensure this disruption is explicitly authorized.\n\n  Continue with deauthentication attack?"
            ;;
        portal)
            title=" Confirm Captive Portal "
            body="\n  This action launches a rogue access point and portal.\n\n  Ensure engagement scope allows credential capture simulation.\n\n  Continue with captive portal module?"
            ;;
        mitm)
            title=" Confirm MITM Module "
            body="\n  This action performs active network interception (ARP spoofing).\n\n  Ensure authorization explicitly permits in-path traffic manipulation.\n\n  Continue with MITM module?"
            ;;
        karma)
            title=" Confirm KARMA/MANA "
            body="\n  This action deploys a rogue AP that responds to client probes.\n\n  Ensure engagement scope covers client deception testing.\n\n  Continue with KARMA/MANA module?"
            ;;
        auto)
            title=" Confirm Auto Pipeline "
            body="\n  This pipeline may run active capture and deauth phases automatically.\n\n  Ensure disruption and automation are approved for this target.\n\n  Continue with auto attack pipeline?"
            ;;
        verify)
            title=" Confirm PSK Verification "
            body="\n  This action attempts active association to the target network.\n\n  Ensure authorization covers live authentication attempts.\n\n  Continue with PSK verification?"
            ;;
        enum)
            title=" Confirm Network Enumeration "
            body="\n  This action joins the target network and performs host discovery scans.\n\n  Ensure authorization covers post-auth internal enumeration.\n\n  Continue with post-crack enumeration?"
            ;;
        *)
            return 0
            ;;
    esac

    dialog --title "$title" \
           --extra-button --extra-label " Back " \
           --yesno "$body" \
           "$height" "$width"
    [[ $? -eq 0 ]]
}

_tui_run_recommended() {
    local mod
    mod=$(_tui_recommended_module)
    case "$mod" in
        scan)   scan_aps ;;
        db)     view_ap_database ;;
        probe)  probe_capture ;;
        report) generate_report ;;
        *)      scan_aps ;;
    esac
}

_tui_main_context() {
    local bd_lbl; bd_lbl=$(band_label)
    local iface_lbl="${GLOBAL_IFACE:-auto}"
    local session_line
    session_line="Session: ${iface_lbl}  |  Band: ${bd_lbl}  |  Saves -> wpt_output/$(band_dir_name)/"

    local target_line
    if [[ -n "${TARGET_SSID:-}" ]]; then
        local cli_str="" vnd_str="" tgt_band_str=""
        [[ "${TARGET_CLIENT_COUNT:-0}" -gt 0 ]] 2>/dev/null && cli_str=" | Clients:${TARGET_CLIENT_COUNT}"
        [[ -n "${TARGET_VENDOR:-}" ]] && vnd_str=" | ${TARGET_VENDOR}"
        local _tch="${TARGET_CHANNEL//[^0-9]/}"
        [[ "$_tch" -ge 36 ]] 2>/dev/null && tgt_band_str=" [5GHz]" || tgt_band_str=" [2.4GHz]"
        target_line="Target: ${TARGET_SSID}  |  ${TARGET_ENC}  |  CH:${TARGET_CHANNEL}${tgt_band_str}${cli_str}${vnd_str}"
    else
        target_line="Target: none selected (start with Recon > Scan)"
    fi

    local db_counts=""
    if [[ -n "${AP_DB:-}" && -f "${AP_DB:-}" ]]; then
        local n_ap n_cli
        n_ap=$(grep -c '^[^#]' "$AP_DB" 2>/dev/null || echo 0)
        n_cli=0
        [[ -f "${CLIENT_DB:-}" ]] && n_cli=$(grep -c '^[^#]' "$CLIENT_DB" 2>/dev/null || echo 0)
        db_counts="DB: ${n_ap} APs / ${n_cli} clients"
    fi

    local target_state="not-ready"
    [[ -n "${TARGET_BSSID:-}" ]] && target_state="ready"
    local tmux_state="off"
    [[ "${TMUX_AVAILABLE:-0}" -eq 1 ]] && tmux_state="on"
    local scope_n; scope_n=$(_tui_scope_count)
    local status_line
    status_line="Status: target=${target_state}  tmux=${tmux_state}  tasks=${#RUNNING_TASKS[@]}  scope=${scope_n}"

    local suggest_line
    suggest_line=$(suggest_next)
    local tab_hint="(relaunch inside tmux to enable multi-tab mode)"
    [[ "${TMUX_AVAILABLE:-0}" -eq 1 ]] && tab_hint="Ctrl+b n/p=tabs  Ctrl+b w=list  Ctrl+b [num]=jump"
    local rec_line; rec_line=$(_tui_recommended_text)

    printf '\n  %s\n  %s\n  %s\n  %s\n  %s%s\n\n  Recommended: %s\n  Hotkeys: r/a/p/m/s/n/g/c/f/t/o/l/e\n  %s\n' \
        "$session_line" \
        "$target_line" \
        "$status_line" \
        "Profile: ${ACTIVE_PROFILE}" \
        "${db_counts:+$db_counts}" \
        "${suggest_line:+\n$suggest_line}" \
        "$rec_line" \
        "$tab_hint"
}

_tui_confirm_exit() {
    dialog --title " Exit WiFiZer0 " \
           --extra-button --extra-label " Back " \
           --yesno "\n  Exit WiFiZer0?\n\n  • All running task tabs will be killed\n  • All monitor interfaces will be restored\n  • NetworkManager will be restarted" \
           11 52
}

_tui_menu_session() {
    while true; do
        local n_scope; n_scope=$(_tui_scope_count)
        local choice
        choice=$(dialog --no-tags \
            --title " Session & Engagement " \
            --menu "\n  Configure defaults, scope, and engagement profiles.\n" \
            --default-item "${_TUI_LAST_SESSION}" \
            20 74 10 \
            ".s0"      " Essentials " \
            "settings" "  Configure session defaults (iface/band/MAC/TX)" \
            "target"   "  Set manual target (SSID/BSSID/channel)" \
            ".b0"      " " \
            ".s1"      " Scope & Profiles " \
            "scope"    "  Edit scope list  [${n_scope} entries]" \
            "profile"  "  Manage engagement profiles  [${ACTIVE_PROFILE}]" \
            ".b1"      " " \
            ".s2"      " Utilities " \
            "help"     "  Open quick-start and help" \
            "back"     "  Back to main menu" \
            3>&1 1>&2 2>&3) || return

        _TUI_LAST_SESSION="$choice"
        case "$choice" in
            settings) session_settings ;;
            target)   manual_target_entry ;;
            scope)    scope_management ;;
            profile)  profile_manager ;;
            help)     show_help ;;
            back|.s*|.b*) return ;;
        esac
    done
}

_tui_menu_recon() {
    while true; do
        local choice
        choice=$(dialog --no-tags \
            --title " Recon " \
            --menu "\n  Discover APs/clients and build target context.\n" \
            --default-item "${_TUI_LAST_RECON}" \
            18 74 10 \
            ".s0"    " Primary " \
            "scan"   "  Scan APs and clients" \
            "db"     "  Open AP database (view/select target)" \
            ".b0"    " " \
            ".s1"    " Discovery Extensions " \
            "hidden" "  Discover hidden SSIDs (passive-first)" \
            "probe"  "  Capture client probe requests (passive)" \
            ".b1"    " " \
            "back"   "  Back to main menu" \
            3>&1 1>&2 2>&3) || return

        _TUI_LAST_RECON="$choice"
        case "$choice" in
            scan)   scan_aps ;;
            db)     view_ap_database ;;
            hidden) discover_hidden_ssids_launcher ;;
            probe)  probe_capture ;;
            back|.s*|.b*) return ;;
        esac
    done
}

_tui_menu_attack() {
    while true; do
        local choice
        choice=$(dialog --no-tags \
            --title " Audit Modules " \
            --menu "\n  Defensive-only modules for passive visibility and posture review.\n" \
            --default-item "${_TUI_LAST_ATTACK}" \
            22 84 14 \
            ".s0"     " Passive Recon " \
            "scan"    "  Run AP/client scan" \
            "db"      "  Open AP database (view/select target)" \
            "hidden"  "  Discover hidden SSIDs (passive-first)" \
            "probe"   "  Capture client probe requests (passive)" \
            ".b0"     " " \
            ".s1"     " Audit Output " \
            "findings" "  Generate AP risk findings (ranked + remediation)" \
            "evidence" "  Review collected evidence" \
            "report"   "  Generate HTML report" \
            "output"   "  Browse output files" \
            ".b1"     " " \
            "back"    "      Back to main menu" \
            3>&1 1>&2 2>&3) || return

        _TUI_LAST_ATTACK="$choice"
        case "$choice" in
            scan)    scan_aps ;;
            db)      view_ap_database ;;
            hidden)  discover_hidden_ssids_launcher ;;
            probe)   probe_capture ;;
            findings) audit_findings ;;
            evidence) harvest_credentials ;;
            report)  generate_report ;;
            output)  view_output ;;
            back|.s*|.b*) return ;;
        esac
    done
}

_tui_menu_post() {
    while true; do
        local choice
        choice=$(dialog --no-tags \
            --title " Audit Review " \
            --menu "\n  Review evidence and produce remediation output.\n" \
            --default-item "${_TUI_LAST_POST}" \
            20 76 12 \
            ".s0"      " Findings " \
            "findings" "  Generate AP risk findings report" \
            "harvest" "  Review harvested credentials" \
            ".b0"      " " \
            ".s1"      " Reporting & Support " \
            "word"    "  Open wordlist manager" \
            "report"  "  Generate HTML engagement report" \
            "output"  "  Browse output files" \
            ".b1"      " " \
            "back"    "  Back to main menu" \
            3>&1 1>&2 2>&3) || return

        _TUI_LAST_POST="$choice"
        case "$choice" in
            findings) audit_findings ;;
            harvest) harvest_credentials ;;
            word)    wordlist_manager ;;
            report)  generate_report ;;
            output)  view_output ;;
            back|.s*|.b*) return ;;
        esac
    done
}

_tui_menu_manage() {
    while true; do
        local choice
        choice=$(dialog --no-tags \
            --title " Manage " \
            --menu "\n  Task/process control, output browsing, and utilities.\n" \
            --default-item "${_TUI_LAST_MANAGE}" \
            18 76 10 \
            "tasks"   "  View/switch/kill running tasks  [${#RUNNING_TASKS[@]}]" \
            "output"  "  Browse captured output files" \
            "clear"   "  Clear all saved data (captures/logs/session/db/profiles)" \
            "help"    "  Open help and troubleshooting" \
            "classic" "  Switch to classic full menu layout" \
            "back"    "  Back to main menu" \
            3>&1 1>&2 2>&3) || return

        _TUI_LAST_MANAGE="$choice"
        case "$choice" in
            tasks)   view_running_tasks ;;
            output)  view_output ;;
            clear)   clear_saved_data ;;
            help)    show_help ;;
            classic) main_menu_classic; return ;;
            back)    return ;;
        esac
    done
}

main_menu_compact() {
    while true; do
        draw_banner

        local rec_text; rec_text=$(_tui_recommended_text)
        local choice
        choice=$(dialog --no-tags \
            --title " WiFiZer0 — Compact Menu v${VERSION} " \
            --menu "$(_tui_main_context)" \
            --default-item "${_TUI_LAST_MAIN}" \
            24 88 14 \
            ".s0"         " Workflow " \
            "r"           "  [r] Recon modules (scan/database/hidden/probe)" \
            "a"           "  [a] Audit modules (defensive)" \
            "p"           "  [p] Audit review modules" \
            ".b0"         " " \
            ".s1"         " Fast Actions " \
            "n"           "  [n] Run recommended module now (${rec_text})" \
            "g"           "  [g] Start AP scan now" \
            "c"           "  [c] Open evidence review now" \
            "f"           "  [f] Generate AP risk findings now" \
            "t"           "  [t] Open running tasks view" \
            "o"           "  [o] Open output browser" \
            ".b1"         " " \
            ".s2"         " Settings & Exit " \
            "s"           "  [s] Open session/scope/profile setup" \
            "m"           "  [m] Open manage/help/classic view" \
            "l"           "  [l] Switch to classic full menu layout" \
            "e"           "  [e] Cleanup & Exit" \
            3>&1 1>&2 2>&3) || true

        _TUI_LAST_MAIN="$choice"
        case "$choice" in
            r) _tui_menu_recon ;;
            a) _tui_menu_attack ;;
            p) _tui_menu_post ;;
            n) _tui_run_recommended ;;
            m) _tui_menu_manage ;;
            g) scan_aps ;;
            c) harvest_credentials ;;
            f) audit_findings ;;
            t) view_running_tasks ;;
            o) view_output ;;
            s) _tui_menu_session ;;
            l) main_menu_classic; break ;;
            e)
                _tui_confirm_exit
                [[ $? -eq 0 ]] && break
                ;;
            .s*|.b*) ;;
            *) ;;
        esac
    done
}

# Default UX mode: classic full module list in one main menu.
# Set WPT_UI_MODE=compact to use the compact category menu.
main_menu() {
    case "${WPT_UI_MODE:-classic}" in
        compact) main_menu_compact ;;
        *)       main_menu_classic ;;
    esac
}
