#!/usr/bin/env bash
# LinuxOps Toolkit v1.1.0 - cross-distribution administration and diagnostics
# Use only on systems you own or are authorized to administer.
set -u
APP_NAME='LinuxOps Toolkit'; VERSION='1.1.0'
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/linuxops-toolkit"; STATE_FILE="$CACHE_DIR/system.state"; LOG_DIR="$CACHE_DIR/logs"; LOG_FILE="$LOG_DIR/linuxops-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$CACHE_DIR" "$LOG_DIR" || { printf 'Cannot create cache directory: %s\n' "$CACHE_DIR" >&2; exit 1; }
RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
say(){ printf '%b\n' "$*"; }; pause(){ read -r -p 'Press Enter to continue...' _ || true; }
run(){ say "${CYAN}> $*${RESET}"; "$@" 2>&1 | tee -a "$LOG_FILE"; local rc=${PIPESTATUS[0]}; ((rc==0)) || say "${RED}Command failed (exit $rc). See log: $LOG_FILE${RESET}"; return "$rc"; }
confirm(){ local ans; read -r -p "$1 [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] && return 0; say "${YELLOW}Administrator privileges are required. Run with sudo for this action.${RESET}"; return 1; }

# Detect host; a manual choice is a profile label, never a substitute for a detected package manager.
OS_NAME='Unknown Linux'; OS_ID='unknown'; OS_VERSION='unknown'; ID_LIKE='';
if [[ -r /etc/os-release ]]; then . /etc/os-release; OS_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"; OS_ID="${ID:-unknown}"; OS_VERSION="${VERSION_ID:-unknown}"; ID_LIKE="${ID_LIKE:-}"; fi
PKG=unknown
if command -v apt-get >/dev/null 2>&1; then PKG=apt
elif command -v dnf >/dev/null 2>&1; then PKG=dnf
elif command -v yum >/dev/null 2>&1; then PKG=yum
elif command -v pacman >/dev/null 2>&1; then PKG=pacman
elif command -v zypper >/dev/null 2>&1; then PKG=zypper
elif command -v apk >/dev/null 2>&1; then PKG=apk
elif command -v xbps-install >/dev/null 2>&1; then PKG=xbps
fi
PROFILE='auto'
manual_profile(){
  say 'Select a distro profile (informational; actual package manager remains auto-detected):'
  local opts=('Auto-detect' 'Debian / Ubuntu' 'Kali Linux' 'Parrot OS' 'Fedora' 'RHEL / Rocky / AlmaLinux' 'Arch / Manjaro' 'openSUSE' 'Alpine' 'Void Linux' 'Other / Unknown') i
  for i in "${!opts[@]}"; do printf '[%d] %s\n' "$i" "${opts[$i]}"; done
  local n; read -r -p 'Choice: ' n
  case "$n" in 0) PROFILE=auto;; 1) PROFILE=debian;; 2) PROFILE=kali;; 3) PROFILE=parrot;; 4) PROFILE=fedora;; 5) PROFILE=rhel;; 6) PROFILE=arch;; 7) PROFILE=opensuse;; 8) PROFILE=alpine;; 9) PROFILE=void;; 10) PROFILE=other;; *) say 'Invalid choice; retaining auto-detect.';; esac
}
state_value(){ sed -n "s/^$1=//p" "$STATE_FILE" 2>/dev/null | head -n1; }
write_state(){ local tmp="$STATE_FILE.tmp.$$"; {
  printf 'timestamp=%s\n' "$(date -Is)"; printf 'os_name=%q\n' "$OS_NAME"; printf 'os_id=%q\n' "$OS_ID"; printf 'os_version=%q\n' "$OS_VERSION"; printf 'package_manager=%q\n' "$PKG"; printf 'profile=%q\n' "$PROFILE"; printf 'kernel=%q\n' "$(uname -srvm 2>/dev/null || true)"; printf 'arch=%q\n' "$(uname -m 2>/dev/null || true)"; printf 'hostname=%q\n' "$(hostname 2>/dev/null || true)";
} > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$STATE_FILE"; }
old_id=$(state_value os_id); old_ver=$(state_value os_version); old_pkg=$(state_value package_manager)
if [[ -s "$STATE_FILE" && "$old_id" == "$OS_ID" && "$old_ver" == "$OS_VERSION" && "$old_pkg" == "$PKG" ]]; then say "${GREEN}Reusing matching detection cache.${RESET}"; else
  if [[ -s "$STATE_FILE" ]]; then say "${YELLOW}Host profile changed (distro/version/package manager); refreshing cache.${RESET}"; fi
  write_state
fi
if [[ ${1:-} == --manual ]]; then manual_profile; write_state; fi

# Map executable names to distribution package names; unknown tools are not guessed.
package_for(){ local tool=$1; case "$tool:$PKG" in
  smartctl:apt) echo smartmontools;; smartctl:dnf|smartctl:yum) echo smartmontools;; smartctl:pacman) echo smartmontools;; smartctl:zypper) echo smartmontools;; smartctl:apk) echo smartmontools;; smartctl:xbps) echo smartmontools;;
  traceroute:apt) echo traceroute;; traceroute:dnf|traceroute:yum) echo traceroute;; traceroute:pacman) echo traceroute;; traceroute:zypper) echo traceroute;; traceroute:apk) echo traceroute;; traceroute:xbps) echo traceroute;;
  tracepath:apt) echo iputils-tracepath;; tracepath:dnf|tracepath:yum) echo iputils;; tracepath:pacman) echo iputils;; tracepath:zypper) echo iputils;; tracepath:apk) echo iputils;; tracepath:xbps) echo iputils;;
  lspci:apt) echo pciutils;; lspci:dnf|lspci:yum) echo pciutils;; lspci:pacman) echo pciutils;; lspci:zypper) echo pciutils;; lspci:apk) echo pciutils;; lspci:xbps) echo pciutils;;
  lsusb:apt) echo usbutils;; lsusb:dnf|lsusb:yum) echo usbutils;; lsusb:pacman) echo usbutils;; lsusb:zypper) echo usbutils;; lsusb:apk) echo usbutils;; lsusb:xbps) echo usbutils;;
  *) echo "$tool";; esac; }
install_packages(){ local -a p=("$@"); ((${#p[@]})) || return 0; need_root || return 1; case "$PKG" in
 apt) run apt-get update && run apt-get install -y "${p[@]}";; dnf) run dnf install -y "${p[@]}";; yum) run yum install -y "${p[@]}";; pacman) run pacman -Syu --noconfirm "${p[@]}";; zypper) run zypper --non-interactive install "${p[@]}";; apk) run apk add "${p[@]}";; xbps) run xbps-install -y "${p[@]}";; *) say 'No supported package manager detected.'; return 1;; esac; }
install_if_missing(){ local -a pkgs=(); local x p; for x in "$@"; do if ! command -v "$x" >/dev/null 2>&1; then p=$(package_for "$x"); pkgs+=("$p"); fi; done; ((${#pkgs[@]}==0)) && return 0; say "Missing tool package(s): ${pkgs[*]}"; confirm 'Install these packages?' || return 1; install_packages "${pkgs[@]}"; }

show_system(){ clear; say "${BLUE}=== SYSTEM INFORMATION ===${RESET}"; say "OS: $OS_NAME"; say "Profile: $PROFILE | Package manager: $PKG"; say "Kernel: $(uname -sr)"; say "Architecture: $(uname -m)"; say "Hostname: $(hostname)"; uptime -p 2>/dev/null || uptime; nproc 2>/dev/null || true; free -h 2>/dev/null || true; lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS 2>/dev/null || true; pause; }
show_hardware(){ clear; say '=== HARDWARE ==='; command -v lscpu >/dev/null && lscpu | sed -n '1,25p'; command -v lspci >/dev/null && { say '--- PCI ---'; lspci; }; command -v lsusb >/dev/null && { say '--- USB ---'; lsusb; }; pause; }
show_memory_disk(){ clear; free -h 2>/dev/null || true; say '--- Filesystems ---'; df -hT; say '--- Block devices ---'; lsblk; pause; }
network_info(){ clear; command -v ip >/dev/null && { ip -br addr; say '--- Routes ---'; ip route; }; say '--- DNS ---'; resolvectl status 2>/dev/null || cat /etc/resolv.conf 2>/dev/null || true; say '--- Listening sockets ---'; ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || true; pause; }
ping_test(){ local h; read -r -p 'Host/IP [1.1.1.1]: ' h; h=${h:-1.1.1.1}; command -v ping >/dev/null || install_if_missing ping; command -v ping >/dev/null && run ping -c 4 -- "$h"; pause; }
dns_test(){ local h; read -r -p 'Domain [example.com]: ' h; h=${h:-example.com}; if command -v resolvectl >/dev/null; then run resolvectl query "$h"; elif command -v getent >/dev/null; then run getent ahosts "$h"; else say 'No DNS lookup utility found.'; fi; pause; }
route_test(){ local h; read -r -p 'Host/IP [1.1.1.1]: ' h; h=${h:-1.1.1.1}; if command -v traceroute >/dev/null; then run traceroute "$h"; elif command -v tracepath >/dev/null; then run tracepath "$h"; else install_if_missing traceroute; command -v traceroute >/dev/null && run traceroute "$h"; fi; pause; }
network_restart(){ need_root || return; local svc=''; command -v systemctl >/dev/null && { systemctl is-active --quiet NetworkManager && svc=NetworkManager || true; [[ -n $svc ]] || { systemctl is-active --quiet systemd-networkd && svc=systemd-networkd || true; }; }; if [[ -z $svc ]]; then say 'No supported active systemd network service detected.'; elif confirm "Restart $svc? This may disconnect remote sessions."; then run systemctl restart "$svc"; fi; pause; }
package_update(){ need_root || return; confirm 'Proceed with system package update/upgrade?' || return; case "$PKG" in apt) run apt-get update && run apt-get upgrade;; dnf) run dnf upgrade;; yum) run yum update;; pacman) run pacman -Syu;; zypper) run zypper refresh && run zypper update;; apk) run apk update && run apk upgrade;; xbps) run xbps-install -Su;; *) say 'Unsupported package manager.';; esac; pause; }
package_install(){ local p; read -r -p 'Package names (space-separated): ' p; [[ -n $p ]] || return; local -a a; read -r -a a <<< "$p"; confirm "Install ${a[*]}?" && install_packages "${a[@]}"; pause; }
package_clean(){ need_root || return; say 'Cleanup may remove cached packages or unused dependencies.'; confirm 'Continue with package cleanup?' || return; case "$PKG" in apt) run apt-get autoremove && run apt-get autoclean;; dnf) run dnf autoremove;; yum) run yum autoremove;; pacman) run pacman -Sc;; zypper) run zypper clean --all;; apk) run apk cache clean;; xbps) run xbps-remove -O;; *) say 'No cleanup routine for this package manager.';; esac; pause; }
user_info(){ clear; id; say '--- Groups ---'; groups; say '--- Local users (UID 1000-59999) ---'; awk -F: '$3>=1000 && $3<60000 {print $1 ":" $3}' /etc/passwd; say '--- Admin groups ---'; getent group sudo 2>/dev/null || true; getent group wheel 2>/dev/null || true; pause; }
service_menu(){ clear; command -v systemctl >/dev/null || { say 'systemctl unavailable (non-systemd host?).'; pause; return; }; systemctl --no-pager --type=service --all | sed -n '1,100p'; local svc act; read -r -p 'Service name to manage (blank to return): ' svc; [[ -n $svc ]] || return; systemctl cat "$svc" >/dev/null 2>&1 || { say 'Unknown service.'; pause; return; }; say '[1] status [2] start [3] stop [4] restart [5] enable [6] disable'; read -r -p 'Action: ' act; case "$act" in 1) run systemctl status --no-pager "$svc";; 2|3|4|5|6) need_root || { pause; return; }; confirm "Run selected action on $svc?" || return; case "$act" in 2) run systemctl start "$svc";; 3) run systemctl stop "$svc";; 4) run systemctl restart "$svc";; 5) run systemctl enable "$svc";; 6) run systemctl disable "$svc";; esac;; *) say 'Invalid action.';; esac; pause; }
log_menu(){ clear; if command -v journalctl >/dev/null; then run journalctl -p warning..alert -b --no-pager -n 100; else dmesg --level=err,warn 2>/dev/null | tail -n 100 || true; fi; pause; }
disk_check(){ local d; read -r -p 'Device (e.g. /dev/sda; blank for filesystem usage): ' d; if [[ -z $d ]]; then df -hT; else [[ -b $d ]] || { say 'Not a block device; refusing SMART query.'; pause; return; }; if ! command -v smartctl >/dev/null; then install_if_missing smartctl || true; fi; command -v smartctl >/dev/null && run smartctl -H "$d" || say 'smartctl unavailable or installation declined.'; fi; pause; }
mounts(){ mount | (command -v column >/dev/null && column -t || cat); pause; }
security_status(){ clear; if command -v ufw >/dev/null; then run ufw status verbose; elif command -v firewall-cmd >/dev/null; then run firewall-cmd --state; run firewall-cmd --list-all; elif command -v nft >/dev/null; then run nft list ruleset; else say 'No common firewall frontend detected.'; fi; command -v getenforce >/dev/null && say "SELinux: $(getenforce)"; command -v aa-status >/dev/null && run aa-status; if command -v systemctl >/dev/null; then systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true; fi; pause; }
report(){ local out="$CACHE_DIR/linuxops-report-$(date +%Y%m%d-%H%M%S).txt"; { echo "$APP_NAME $VERSION"; date -Is; echo '[OS]'; cat /etc/os-release 2>/dev/null; echo '[Kernel]'; uname -a; echo '[CPU]'; lscpu 2>/dev/null; echo '[Memory]'; free -h 2>/dev/null; echo '[Disk]'; df -hT; lsblk; echo '[Network]'; ip -br addr 2>/dev/null; ip route 2>/dev/null; echo '[Listening sockets]'; ss -tulpn 2>/dev/null; } > "$out"; chmod 600 "$out"; say "Report saved: $out"; pause; }
show_cache(){ clear; cat "$STATE_FILE" 2>/dev/null || say 'No cache available.'; say "Cache directory: $CACHE_DIR"; pause; }
refresh_cache(){ write_state && say 'Detection cache refreshed.'; pause; }

while true; do clear; say "${CYAN}========== LINUXOPS TOOLKIT v$VERSION ==========${RESET}"; say "OS: $OS_NAME | Profile: $PROFILE | Package manager: $PKG"; say "Kernel: $(uname -r) | Arch: $(uname -m)"; say ''; say '[1] System information       [2] Hardware information'; say '[3] Memory & disk            [4] Network information'; say '[5] Ping test                [6] DNS test'; say '[7] Route/traceroute         [8] Restart network service'; say '[9] Update/upgrade           [10] Install packages'; say '[11] Package cleanup         [12] Users & groups'; say '[13] Services                [14] System logs'; say '[15] Disk/SMART check        [16] Mounts'; say '[17] Security status         [18] Diagnostic report'; say '[19] Show cache              [20] Refresh cache'; say '[21] Manual distro profile'; say '[0] Exit'; read -r -p 'Select an option: ' c || exit 0; case "$c" in 1) show_system;; 2) show_hardware;; 3) show_memory_disk;; 4) network_info;; 5) ping_test;; 6) dns_test;; 7) route_test;; 8) network_restart;; 9) package_update;; 10) package_install;; 11) package_clean;; 12) user_info;; 13) service_menu;; 14) log_menu;; 15) disk_check;; 16) mounts;; 17) security_status;; 18) report;; 19) show_cache;; 20) refresh_cache;; 21) manual_profile; write_state;; 0) say 'Goodbye.'; exit 0;; *) say 'Invalid option.'; sleep 1;; esac; done
