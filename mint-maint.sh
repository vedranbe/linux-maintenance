#!/bin/bash
set -euo pipefail
source /etc/os-release
DISTRO="$PRETTY_NAME"

#===============================================================================
# System Update & Clean Script
#===============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration - YOUR PATHS (use absolute path or adjust)
SUDO_USER="${SUDO_USER:-$(logname 2>/dev/null || whoami)}"  # Better user detection
SCRIPT_DIR="/home/$SUDO_USER/Documents/Shortcuts"            # Fixed: User's real home
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/system-maint_$(date +%Y%m%d_%H%M%S).log"
RETAIN_LOGS_DAYS=14

# Create log directory if missing
mkdir -p "$LOG_DIR"


# ------------------------------------------------------------------
# 🔐 SUDO BOOTSTRAP (THIS IS THE MAGIC PART)
# ------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    printf  "${CYAN}║  %-58s║${NC}\n" "$DISTRO - System Maintenance Tool"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Custom terminal password prompt
    sudo -v -p "$(echo -e "${GREEN}🔐 [sudo] password for ${SUDO_USER}:${NC} ")"

    # Relaunch script as root preserving arguments
    exec sudo "$0" "$@"
fi
# ------------------------------------------------------------------

# Create log directory if missing (fix ~ expansion)
mkdir -p "$LOG_DIR"

# Logging function (doesn't break stdin)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Detect available tools
detect_tools() {
    USE_FLATPAK=$(command -v flatpak &>/dev/null && echo 1 || echo 0)
    USE_SNAP=$(command -v snap &>/dev/null && echo 1 || echo 0)
    USE_FWUPD=$(command -v fwupdmgr &>/dev/null && echo 1 || echo 0)
    
    echo -e "${CYAN}Tools detected:${NC}"
    echo "  ✓ APT (default)"
    [ "$USE_FLATPAK" -eq 1 ] && echo "  ✓ Flatpak"
    [ "$USE_SNAP" -eq 1 ] && echo "  ✓ Snap"
    [ "$USE_FWUPD" -eq 1 ] && echo "  ✓ Firmware updates"
    echo ""
}

# Timeshift warning
timeshift_check() {
    if command -v timeshift &>/dev/null && { [ -d "/timeshift" ] || timeshift --list 2>/dev/null | grep -q "snapshots"; }; then
        echo -e "${YELLOW}⚠️  Timeshift detected! Consider creating a snapshot first.${NC}"
        read -r -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    fi
    echo ""
}

# Pause function (works with tee logging)
pause() {
    echo ""
    read -r -p "Press Enter to continue..."
}

#===============================================================================
# UPDATE FUNCTIONS (APT ONLY)
#===============================================================================

update_apt() {
    log "[UPDATE] Package lists..."
    echo -e "${BLUE}[UPDATE] Package lists...${NC}"
    
    apt-get update | tee -a "$LOG_FILE"
    log "[UPDATE] Full upgrade (dist-upgrade)..."
    echo -e "${BLUE}[UPDATE] Full upgrade (dist-upgrade)...${NC}"
    apt-get dist-upgrade -y | tee -a "$LOG_FILE"
}


update_flatpak() {
    [ "$USE_FLATPAK" -eq 0 ] && return
    
    log "[UPDATE] Flatpak applications..."
    echo -e "${BLUE}[UPDATE] Flatpak applications...${NC}"
    flatpak update -y | tee -a "$LOG_FILE"
    #flatpak uninstall --unused -y | grep -v "pinned" | grep -v "runtime/" | tee -a "$LOG_FILE"
}

update_firmware() {
    [ "$USE_FWUPD" -eq 0 ] && return
    
    log "[UPDATE] Firmware..."
    echo -e "${BLUE}[UPDATE] Firmware...${NC}"
    fwupdmgr refresh --force 2>/dev/null | tee -a "$LOG_FILE" || true
    fwupdmgr update 2>&1 | tee -a "$LOG_FILE" || log "No firmware updates available"
}

#===============================================================================
# CLEAN FUNCTIONS (APT ONLY)
#===============================================================================

clean_packages() {
    log "[CLEAN] Removing unused packages..."
    echo -e "${BLUE}[CLEAN] Removing unused packages...${NC}"
    
    apt-get autopurge -y | tee -a "$LOG_FILE"    # Fixed
    apt-get autoremove --purge -y | tee -a "$LOG_FILE"  # Fixed
}

clean_caches() {
    log "[CLEAN] Cleaning package caches..."
    echo -e "${BLUE}[CLEAN] Cleaning package caches...${NC}"
    
    local before after
    before=$(du -sh /var/cache/apt 2>/dev/null | cut -f1)
    echo "  Before: $before"
    log "Cache before: $before"
    
    apt-get autoclean | tee -a "$LOG_FILE"       # Fixed
    apt-get clean | tee -a "$LOG_FILE"           # Fixed
    
    after=$(du -sh /var/cache/apt 2>/dev/null | cut -f1)
    echo "  After:  $after"
    log "Cache after: $after"
}

clean_journal() {
    log "[CLEAN] Truncating systemd journal (${RETAIN_LOGS_DAYS} days)..."
    echo -e "${BLUE}[CLEAN] Truncating systemd journal (${RETAIN_LOGS_DAYS} days)...${NC}"
    
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=${RETAIN_LOGS_DAYS}days | tee -a "$LOG_FILE"
    else
        echo "  (systemd not present, skipping)"
        log "No systemd journal"
    fi
}

clean_logs() {
    log "[CLEAN] Rotating and cleaning logs..."
    echo -e "${BLUE}[CLEAN] Rotating and cleaning logs...${NC}"
    
    if [ -f /etc/cron.daily/logrotate ]; then
        /usr/sbin/logrotate -f /etc/logrotate.conf 2>/dev/null | tee -a "$LOG_FILE" || true
    fi
    
    find /var/log -name "*.gz" -mtime +30 -delete 2>/dev/null || true
    find /var/log -name "*.old" -delete 2>/dev/null || true
    find /var/log -name "*.log" -size +100M -type f -exec truncate -s 0 {} + 2>/dev/null || true
    log "Old logs cleaned"
}

clean_user_cache() {
    log "[CLEAN] User cache..."
    echo -e "${BLUE}[CLEAN] User cache...${NC}"
    
    local user_home="/home/$SUDO_USER"
    [ ! -d "$user_home" ] && user_home="$HOME"
    
    if [ -d "$user_home/.cache/thumbnails" ]; then
        rm -rf "$user_home/.cache/thumbnails/"*
        echo "  Thumbnails cleared"
        log "Thumbnails cleared"
    fi
    
    for browser in chromium chrome firefox; do
        local cache_dir="$user_home/.cache/$browser"
        if [ -d "$cache_dir" ]; then
            find "$cache_dir" -name "Cache" -type d -exec rm -rf {} + 2>/dev/null || true
            echo "  $browser cache cleared"
            log "$browser cache cleared"
        fi
    done
    
    rm -rf "$user_home/.cache/apt-file" 2>/dev/null || true
}

clean_snap() {
    [ "$USE_SNAP" -eq 0 ] && return
    
    log "[CLEAN] Removing old Snap revisions..."
    echo -e "${BLUE}[CLEAN] Removing old Snap revisions...${NC}"
    
    local before after
    before=$(du -sh /var/lib/snapd/snaps 2>/dev/null | cut -f1)
    echo "  Current usage: $before"
    log "Snap before: $before"
    
    LANG=C snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' | while read -r snapname revision; do
        [ -z "$snapname" ] && continue
        echo "  Removing $snapname revision $revision"
        log "Removing snap: $snapname revision $revision"
        snap remove "$snapname" --revision="$revision" 2>/dev/null | tee -a "$LOG_FILE" || true
    done
    
    after=$(du -sh /var/lib/snapd/snaps 2>/dev/null | cut -f1)
    echo "  After cleanup: $after"
    log "Snap after: $after"
}

clean_flatpak() {
    [ "$USE_FLATPAK" -eq 0 ] && return
    
    log "[CLEAN] Flatpak unused runtimes..."
    echo -e "${BLUE}[CLEAN] Flatpak unused runtimes...${NC}"
    flatpak uninstall --unused -y | grep -v "pinned" | grep -v "runtime/" | tee -a "$LOG_FILE" || true
}

#===============================================================================
# MAIN MENU
#===============================================================================

show_menu() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    printf  "${CYAN}║  %-58s║${NC}\n" "$DISTRO - System Maintenance Tool"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Full Update (APT + Flatpak + Firmware)"
    echo -e "  ${GREEN}2)${NC} Full Clean (Packages + Caches + Logs + Snap)"
    echo -e "  ${GREEN}3)${NC} Update + Clean (Complete Maintenance)"
    echo -e "  ${GREEN}4)${NC} Quick Update Only"
    echo -e "  ${GREEN}5)${NC} Quick Clean Only"
    echo -e "  ${GREEN}6)${NC} View Disk Usage"
    echo -e "  ${GREEN}7)${NC} View Log Files"
    echo -e "  ${GREEN}0)${NC} Exit"
    echo ""
    echo -e "  ${YELLOW}Script:${NC} $SCRIPT_DIR/mint-maint.sh"
    echo -e "  ${YELLOW}Logs:${NC}   $LOG_DIR/"
    echo -e "  ${YELLOW}Current log:${NC} $(basename "$LOG_FILE")"
    echo ""
}

disk_usage() {
    echo -e "${CYAN}=== Disk Usage Report ===${NC}"
    echo ""
    echo "Package caches:"
    du -sh /var/cache/apt 2>/dev/null || echo "  (none)"
    
    echo ""
    echo "Logs:"
    du -sh /var/log 2>/dev/null || echo "  (none)"
    journalctl --disk-usage 2>/dev/null || echo "  (no systemd journal)"
    
    echo ""
    echo "Snaps:"
    [ -d /var/lib/snapd/snaps ] && du -sh /var/lib/snapd/snaps || echo "  (none)"
    
    echo ""
    echo "Flatpak:"
    [ -d /var/lib/flatpak ] && du -sh /var/lib/flatpak || echo "  (none)"
    
    pause
}

view_logs() {
    echo -e "${CYAN}=== Log Files ===${NC}"
    ls -la "$LOG_DIR" 2>/dev/null || echo "No logs found"
    echo ""
    read -r -p "View specific log? (filename or Enter to skip): " logname
    if [ -n "$logname" ] && [ -f "$LOG_DIR/$logname" ]; then
        less "$LOG_DIR/$logname"
    fi
}

run_update() {
    echo -e "${CYAN}========== STARTING UPDATE ==========${NC}"
    log "========== UPDATE STARTED =========="
    timeshift_check
    update_apt
    update_flatpak
    update_firmware
    
    if [ -f /var/run/reboot-required ]; then
        echo ""
        echo -e "${YELLOW}⚠️  REBOOT REQUIRED: Kernel or libraries updated${NC}"
        log "REBOOT REQUIRED"
    fi
    log "========== UPDATE COMPLETED =========="
}

run_clean() {
    echo -e "${CYAN}========== STARTING CLEAN ==========${NC}"
    log "========== CLEAN STARTED =========="
    clean_packages
    clean_caches
    clean_journal
    clean_logs
    clean_snap
    clean_flatpak
    clean_user_cache
    log "========== CLEAN COMPLETED =========="
}

#===============================================================================
# MAIN - WITH FINAL PAUSE TO PREVENT WINDOW CLOSE
#===============================================================================

main() {
    detect_tools
    
    # Initialize log
    log "Script started by $SUDO_USER"
    log "Log file: $LOG_FILE"
    
    while true; do
        show_menu
        read -r -p "Select option: " choice
        
        case $choice in
            1) run_update; pause ;;
            2) run_clean; pause ;;
            3) run_update; echo ""; run_clean; pause ;;
            4) update_apt; pause ;;
            5) clean_packages; clean_caches; pause ;;
            6) disk_usage ;;
            7) view_logs ;;
            0) 
	            echo -e "${GREEN}Goodbye!${NC}"
        	    log "Script exited by user ($SUDO_USER)"
        	    NORMAL_EXIT=1  # ← Add this flag
        	    echo ""
        	    read -r -p "Press Enter to close window..."
        	    exit 0 
        	    ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

# Trap to catch unexpected exits and pause
on_exit() {
    # Skip if normal menu exit
    [ "${NORMAL_EXIT:-0}" -eq 1 ] && return
    echo ""
    echo "Script interrupted"
    read -r -p "Press Enter to close..."
}

trap 'on_exit' EXIT

main "$@"
