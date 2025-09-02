#!/usr/bin/env bash
# Lubuntu 24.04.3 LTS (Noble) basic initialization & tuning
# Safe defaults + optional knobs. Run with sudo.
# v1.0

set -euo pipefail

# ---------------------------
# CONFIG KNOBS (edit as needed)
# ---------------------------
ENABLE_UFW=true          # Basic firewall
ALLOW_SSH=true           # Allow SSH in UFW
SSH_PORT=22              # SSH port to allow (if ALLOW_SSH=true)

ENABLE_UNATTENDED=true   # Security updates automatically
INSTALL_COMMON_TOOLS=true
TUNE_SYSCTL=true         # Kernel/sysctl tuning (desktop-friendly)
TUNE_LIMITS=true         # Increase file descriptor limits
TUNE_JOURNAL=true        # Cap journal size
ENABLE_FSTRIM=true       # Weekly SSD TRIM (safe on SSD/NVMe)
SET_BASH_ALIASES=true    # Handy aliases
CLEANUP_APT=true         # Autoremove & clean

# Sysctl values (desktop sane defaults)
SWAPPINESS=10            # Lower = prefer RAM, typical desktop value ~10
VFS_CACHE_PRESSURE=50    # Lower keeps inode/dentry cache a bit longer

# Network stack tuning (safe + modern)
TCP_CONGESTION="bbr"     # Requires Linux 4.9+, Noble uses newer; OK
DEFAULT_QDISC="fq"

# Journal size cap
JOURNAL_MAX="200M"

# Common tools to install
COMMON_TOOLS=(
  build-essential curl wget git vim nano neovim
  htop iotop iftop nload sysstat bmon
  net-tools iperf3 traceroute mtr-tiny nmap
  openssh-server
  ufw fail2ban
  unzip zip p7zip-full
  software-properties-common ca-certificates gnupg lsb-release
)

# ---------------------------
# Helpers
# ---------------------------
log() { printf "\033[1;32m[+] %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m[!] %s\033[0m\n" "$*"; }
err() { printf "\033[1;31m[✗] %s\033[0m\n" "$*"; }
need_root() {
  if [[ $(id -u) -ne 0 ]]; then
    err "Please run as root (use: sudo $0)"; exit 1
  fi
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

detect_codename() {
  . /etc/os-release
  echo "${UBUNTU_CODENAME:-noble}"
}

# ---------------------------
# Steps
# ---------------------------

step_update_upgrade() {
  log "Updating package lists & upgrading..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
}

step_install_tools() {
  if [[ "$INSTALL_COMMON_TOOLS" == "true" ]]; then
    log "Installing common tools..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${COMMON_TOOLS[@]}"
  fi
}

step_firewall() {
  if [[ "$ENABLE_UFW" == "true" ]]; then
    log "Configuring UFW (firewall)..."
    systemctl enable ufw || true
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    if [[ "$ALLOW_SSH" == "true" ]]; then
      ufw allow "${SSH_PORT}"/tcp
    fi
    ufw --force enable
  else
    warn "UFW disabled by config."
  fi
}

step_unattended() {
  if [[ "$ENABLE_UNATTENDED" == "true" ]]; then
    log "Enabling unattended-upgrades (security updates)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
    local f20="/etc/apt/apt.conf.d/20auto-upgrades"
    backup_file "$f20"
    cat > "$f20" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    systemctl restart unattended-upgrades || true
  else
    warn "Unattended upgrades disabled by config."
  fi
}

step_sysctl() {
  if [[ "$TUNE_SYSCTL" == "true" ]]; then
    log "Applying desktop-friendly sysctl/network tuning..."
    local f="/etc/sysctl.d/99-tuning.conf"
    backup_file "$f"
    cat > "$f" <<EOF
# Desktop-friendly VM settings
vm.swappiness=${SWAPPINESS}
vm.vfs_cache_pressure=${VFS_CACHE_PRESSURE}

# Increase inotify limits (better for IDEs, watching files, etc.)
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024

# Modern network stack defaults
net.core.default_qdisc=${DEFAULT_QDISC}
net.ipv4.tcp_congestion_control=${TCP_CONGESTION}

# Reasonable socket buffers/backlogs
net.core.somaxconn=8192
net.core.netdev_max_backlog=16384
net.ipv4.tcp_fastopen=3
EOF
    sysctl --system
  fi
}

step_limits() {
  if [[ "$TUNE_LIMITS" == "true" ]]; then
    log "Raising file descriptor limits..."
    local f="/etc/security/limits.d/99-nofile.conf"
    backup_file "$f"
    cat > "$f" <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  fi
}

step_journal() {
  if [[ "$TUNE_JOURNAL" == "true" ]]; then
    log "Capping systemd-journald size to ${JOURNAL_MAX}..."
    mkdir -p /etc/systemd/journald.conf.d
    local f="/etc/systemd/journald.conf.d/size.conf"
    backup_file "$f"
    cat > "$f" <<EOF
[Journal]
SystemMaxUse=${JOURNAL_MAX}
EOF
    systemctl restart systemd-journald
  fi
}

step_fstrim() {
  if [[ "$ENABLE_FSTRIM" == "true" ]]; then
    log "Enabling weekly fstrim.timer (safe on SSD/NVMe)..."
    systemctl enable fstrim.timer
    systemctl start fstrim.timer || true
  fi
}

step_aliases() {
  if [[ "$SET_BASH_ALIASES" == "true" ]]; then
    log "Adding handy bash aliases to /etc/skel and root..."
    local block='
# ----- Handy aliases (added by lubuntu-init) -----
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."
alias grep="grep --color=auto"
alias k="kubectl"
alias venv="python3 -m venv .venv && source .venv/bin/activate"
# --------------------------------------------------
'
    for home in /root /etc/skel; do
      if [[ -d "$home" ]]; then
        if ! grep -q "Handy aliases (added by lubuntu-init)" "$home/.bashrc" 2>/dev/null; then
          printf "\n%s\n" "$block" >> "$home/.bashrc"
        fi
      fi
    done
  fi
}

step_fail2ban() {
  if dpkg -s fail2ban >/dev/null 2>&1; then
    log "Configuring fail2ban with basic SSH jail..."
    mkdir -p /etc/fail2ban
    local f="/etc/fail2ban/jail.local"
    backup_file "$f"
    cat > "$f" <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
  fi
}

step_autoremove() {
  if [[ "$CLEANUP_APT" == "true" ]]; then
    log "Cleaning up APT cache and autoremove..."
    apt-get autoremove -y
    apt-get autoclean -y || true
  fi
}

summary() {
  log "All done! Summary of applied steps:"
  echo "  - Updates & dist-upgrade"
  [[ "$INSTALL_COMMON_TOOLS" == "true" ]] && echo "  - Installed common tools"
  [[ "$ENABLE_UFW" == "true" ]] && echo "  - UFW enabled (SSH ${ALLOW_SSH:+allowed on port $SSH_PORT})"
  [[ "$ENABLE_UNATTENDED" == "true" ]] && echo "  - Unattended security updates enabled"
  [[ "$TUNE_SYSCTL" == "true" ]] && echo "  - Sysctl tuning applied"
  [[ "$TUNE_LIMITS" == "true" ]] && echo "  - File descriptor limits raised"
  [[ "$TUNE_JOURNAL" == "true" ]] && echo "  - Journald capped at ${JOURNAL_MAX}"
  [[ "$ENABLE_FSTRIM" == "true" ]] && echo "  - Weekly fstrim.timer enabled"
  [[ "$SET_BASH_ALIASES" == "true" ]] && echo "  - Handy bash aliases added"
  echo "  - Fail2ban SSH jail configured (if installed)"
  echo
  warn "Reboot is recommended to ensure all settings take full effect."
}

main() {
  need_root
  local codename; codename="$(detect_codename)"
  log "Detected Ubuntu codename: ${codename}"
  step_update_upgrade
  step_install_tools
  step_firewall
  step_unattended
  step_sysctl
  step_limits
  step_journal
  step_fstrim
  step_aliases
  step_fail2ban
  step_autoremove
  summary
}

main "$@"
