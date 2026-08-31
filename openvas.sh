#!/usr/bin/env bash
#
# gvm-openvas-setup.sh
# Installs and configures Greenbone Vulnerability Management (GVM/OpenVAS)
# on Debian-based systems (Debian, Kali, Ubuntu) using the native gvm-setup flow.
#
# Tested against: Debian 12/13, Kali 2026.x, Ubuntu 22.04/24.04
# Run as root or with sudo.
#
# Usage:
#   sudo ./gvm-openvas-setup.sh install     # full install + setup (includes black theme)
#   sudo ./gvm-openvas-setup.sh check       # run gvm-check-setup only
#   sudo ./gvm-openvas-setup.sh start       # start services
#   sudo ./gvm-openvas-setup.sh status      # show service status
#   sudo ./gvm-openvas-setup.sh reset-pass  # reset admin password
#   sudo ./gvm-openvas-setup.sh theme       # (re)apply the black GSA theme only
#
set -euo pipefail

LOG_FILE="/var/log/gvm-openvas-setup.log"
ADMIN_USER="admin"
GSA_WEB_DIRS=(
    "/usr/share/gvm/gsad/web"
    "/usr/share/gsad/web"
    "/usr/local/share/gvm/gsad/web"
)
THEME_MARKER="/* gvm-openvas-setup black-theme */"

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (use sudo)." >&2
        exit 1
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log "Detected distro: $PRETTY_NAME"
    else
        log "WARNING: could not detect distro via /etc/os-release, proceeding anyway."
    fi
}

install_gvm() {
    log "Updating package lists..."
    apt-get update -y

    log "Installing gvm package (pulls in openvas-scanner, gvmd, ospd-openvas, etc.)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y gvm

    log "Package install complete. Running gvm-setup — this downloads NVT feeds,"
    log "CERT-Bund, CVE, and SCAP data. This step can take 30-90+ minutes depending"
    log "on network speed. Do not interrupt it."
    gvm-setup 2>&1 | tee -a "$LOG_FILE"
}

run_check() {
    log "Running gvm-check-setup to validate installation..."
    if gvm-check-setup 2>&1 | tee -a "$LOG_FILE"; then
        log "gvm-check-setup completed. Review output above for any FAIL/WARN items."
    else
        log "gvm-check-setup reported issues. See $LOG_FILE for details."
        log "Common fixes:"
        log "  - Feed sync incomplete: re-run 'greenbone-nvt-sync', 'greenbone-feed-sync --type GVMD_DATA', 'greenbone-feed-sync --type SCAP', 'greenbone-feed-sync --type CERT'"
        log "  - Socket/service not running: run '$0 start' then '$0 status'"
        log "  - Redis not running: 'systemctl start redis-server@openvas' (or 'redis-server')"
    fi
}

start_services() {
    log "Starting GVM services..."
    systemctl enable --now redis-server@openvas 2>/dev/null || systemctl enable --now redis-server 2>/dev/null || true
    systemctl enable --now ospd-openvas
    systemctl enable --now gvmd
    systemctl enable --now gsad
    log "Services started (or already running). Web UI should be reachable shortly."
    log "Default URL: https://127.0.0.1:9392  (accept the self-signed cert warning)"
}

show_status() {
    for svc in redis-server@openvas ospd-openvas gvmd gsad; do
        echo "--- $svc ---"
        systemctl status "$svc" --no-pager -l 2>&1 | head -n 10 || true
        echo
    done
}

reset_password() {
    log "Resetting password for GVM admin user '$ADMIN_USER'..."
    NEW_PASS=$(gvmd --user="$ADMIN_USER" --new-password="$(openssl rand -base64 12)")
    log "Password reset. Check gvmd output above; if it printed the password, save it now."
    log "Alternatively run manually: gvmd --user=$ADMIN_USER --new-password='YourNewPassword'"
}

find_gsa_web_dir() {
    for d in "${GSA_WEB_DIRS[@]}"; do
        if [[ -d "$d" ]]; then
            echo "$d"
            return 0
        fi
    done
    # Fallback: search for the compiled JS bundle that GSA serves
    local found
    found=$(find /usr/share /usr/local/share -maxdepth 4 -type d -name web 2>/dev/null | grep -i gsa | head -n1 || true)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

apply_black_theme() {
    log "Locating GSA web assets directory..."
    local web_dir
    if ! web_dir=$(find_gsa_web_dir); then
        log "ERROR: could not locate GSA web directory. Is gsad installed? Skipping theme."
        return 1
    fi
    log "Found GSA web directory: $web_dir"

    local override_css="$web_dir/black-theme-override.css"
    local index_html="$web_dir/index.html"

    log "Writing black theme stylesheet to $override_css ..."
    cat > "$override_css" <<CSSEOF
$THEME_MARKER
/* Full-black override theme for Greenbone Security Assistant (GSA) */

:root {
  --gsa-bg: #000000 !important;
  --gsa-panel: #050505 !important;
  --gsa-border: #1a1a1a !important;
  --gsa-text: #e6e6e6 !important;
  --gsa-accent: #2fa8ff !important;
}

html, body, #app, #root,
.layout, .content, .page, .container,
.mantine-AppShell-root, .mantine-AppShell-main {
  background-color: #000000 !important;
  color: #e6e6e6 !important;
}

/* Header / navbar */
header, nav, .navbar, .topbar, .app-header,
[class*="Header"], [class*="header"] {
  background-color: #000000 !important;
  border-color: #1a1a1a !important;
  color: #e6e6e6 !important;
}

/* Sidebar / menu */
aside, .sidebar, .menu, [class*="Sidebar"], [class*="sidebar"] {
  background-color: #050505 !important;
  border-color: #1a1a1a !important;
}

/* Cards, panels, tables, dialogs */
.card, .panel, table, thead, tbody, tr, td, th,
.dialog, .modal, [class*="Dialog"], [class*="Modal"],
[class*="Card"], [class*="Panel"], [class*="Table"] {
  background-color: #000000 !important;
  color: #e6e6e6 !important;
  border-color: #1a1a1a !important;
}

/* Table row hover / stripe kept dark, not white */
tr:hover, tbody tr:nth-child(even) {
  background-color: #0d0d0d !important;
}

/* Inputs, selects, textareas */
input, select, textarea,
[class*="Input"], [class*="Select"], [class*="TextArea"] {
  background-color: #0a0a0a !important;
  color: #e6e6e6 !important;
  border-color: #262626 !important;
}

/* Buttons - keep accent color for primary actions */
button, [class*="Button"] {
  background-color: #111111 !important;
  color: #e6e6e6 !important;
  border-color: #262626 !important;
}
button:hover, [class*="Button"]:hover {
  background-color: #1a1a1a !important;
}

/* Links / accent text */
a, [class*="link"] {
  color: var(--gsa-accent) !important;
}

/* Charts / dashboards: force dark backgrounds behind SVGs */
svg, .chart, [class*="Chart"], [class*="Dashboard"] {
  background-color: #000000 !important;
}

/* Scrollbars */
::-webkit-scrollbar { background-color: #000000; }
::-webkit-scrollbar-thumb { background-color: #262626; border-radius: 4px; }

/* Severity badges keep their semantic colors (do not override) */
CSSEOF

    log "Stylesheet written. Injecting <link> tag into $index_html ..."
    if [[ ! -f "$index_html" ]]; then
        log "ERROR: $index_html not found. Cannot auto-inject; stylesheet is saved but not linked."
        log "Manually add: <link rel=\"stylesheet\" href=\"/black-theme-override.css\">"
        return 1
    fi

    # Back up index.html once
    if [[ ! -f "$index_html.orig" ]]; then
        cp "$index_html" "$index_html.orig"
        log "Backed up original index.html to $index_html.orig"
    fi

    if grep -q "black-theme-override.css" "$index_html"; then
        log "Theme link already present in index.html, skipping injection."
    else
        # Inject right before </head>
        sed -i 's#</head>#  <link rel="stylesheet" href="/black-theme-override.css">\n</head>#' "$index_html"
        log "Injected stylesheet link into index.html."
    fi

    log "Restarting gsad to pick up static asset changes..."
    systemctl restart gsad || log "WARNING: could not restart gsad automatically, restart it manually."

    log "Black theme applied. Hard-refresh the GSA page (Ctrl+Shift+R) to clear cached CSS/JS."
}

print_summary() {
    cat <<'EOF'

=====================================================================
GVM / OpenVAS Setup Summary
=====================================================================
- Web UI (Greenbone Security Assistant): https://127.0.0.1:9392
- Default admin username is usually printed at the end of gvm-setup
  (look for "User created with password" in the terminal output/log)
- If you missed the generated password, reset it with:
    sudo gvmd --user=admin --new-password='YourNewPassword'
- Feed updates (run periodically, e.g. via cron):
    sudo greenbone-nvt-sync
    sudo greenbone-feed-sync --type GVMD_DATA
    sudo greenbone-feed-sync --type SCAP
    sudo greenbone-feed-sync --type CERT
- Logs for this script: /var/log/gvm-openvas-setup.log
- Full GVM logs: /var/log/gvm/
- Black theme applied to GSA web UI (hard-refresh browser: Ctrl+Shift+R)
  Re-apply anytime with: sudo ./gvm-openvas-setup.sh theme
  Original index.html backed up alongside it as index.html.orig
=====================================================================
EOF
}

main() {
    require_root
    touch "$LOG_FILE"
    detect_distro

    case "${1:-install}" in
        install)
            install_gvm
            run_check
            start_services
            apply_black_theme || log "Theme step failed — see log; core GVM install is unaffected."
            print_summary
            ;;
        check)
            run_check
            ;;
        start)
            start_services
            ;;
        status)
            show_status
            ;;
        reset-pass)
            reset_password
            ;;
        theme)
            apply_black_theme
            ;;
        *)
            echo "Usage: $0 {install|check|start|status|reset-pass|theme}"
            exit 1
            ;;
    esac
}

main "$@"
