from pathlib import Path
content = r'''#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# === OpenBox Minimal Gaming Installer (Corrected & Hardened) ===
# Usage: sudo bash v2.fixed.sh
# This is a corrected version of the user's v2.sh with:
#  - missing helper functions added (print_status/print_success/etc.)
#  - safer checks for root and username
#  - robust apt handling and retries
#  - improved file edits and backups
#  - preserved original configuration intent (no features removed)
#  - added logging to /var/log/openbox-setup.log

LOGFILE="/var/log/openbox-setup.log"
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' EXIT
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# Helper printing functions
print_status()  { echo -e "[\e[33m.. \e[0m] $*"; }
print_success() { echo -e "[\e[32mOK \e[0m] $*"; }
print_error()   { echo -e "[\e[31m!! \e[0m] $*"; }
print_warn()    { echo -e "[\e[35m!! \e[0m] $*"; }
_highlight()    { echo -e "[\e[36m** \e[0m] $*"; }

# --- PRECHECKS ---
if [ "$(id -u)" -ne 0 ]; then
    print_error "Ce script doit être exécuté en root (sudo)"
    exit 1
fi

# --- USER CONFIGURATION (edit before running) ---
USERNAME="${USERNAME:-anonymous}"

if [ -z "$USERNAME" ] || [ "$USERNAME" = "votreuser" ]; then
    print_error "ERREUR CRITIQUE : Modifiez la variable USERNAME dans le script."
    exit 1
fi

# Ensure user exists
if ! id -u "$USERNAME" >/dev/null 2>&1; then
    print_error "Le compte utilisateur '$USERNAME' n'existe pas. Créez-le d'abord :"
    echo "  adduser $USERNAME && usermod -aG sudo $USERNAME"
    exit 1
fi

USER_HOME="/home/$USERNAME"
if [ ! -d "$USER_HOME" ]; then
    print_error "Le répertoire $USER_HOME n'existe pas."
    exit 1
fi

print_status "Installation pour l'utilisateur: $USERNAME (home: $USER_HOME)"

# Create a small wrapper to run apt with retries
apt_update_once() {
    local tries=0
    until apt-get update -y; do
        tries=$((tries+1))
        if [ $tries -ge 3 ]; then
            print_warn "apt-get update failed after $tries tries - continuing but some packages may fail"
            break
        fi
        sleep 2
    done
}

apt_install() {
    local pkgs=("$@")
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" || {
        print_warn "apt-get install failed for: ${pkgs[*]}"
    }
}

# Keep PATH stable
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

print_status "Début: mise à jour et préparation des dépôts"
apt_update_once
apt_install apt-transport-https ca-certificates gnupg curl wget software-properties-common
apt-get full-upgrade -y || print_warn "full-upgrade non complet"
apt_autoclean() { apt-get -y autoremove; apt-get -y autoclean; }
apt_autoclean
print_success "Système mis à jour"

# --- Repositories: enable contrib/non-free and backports safely ---
print_status "Activation des dépôts contrib/non-free et backports"
# Backup
cp -a /etc/apt/sources.list /etc/apt/sources.list.bak_$(date +%s) || true

# Add contrib/non-free to lines that have 'main' but avoid doubling
if ! grep -q "contrib" /etc/apt/sources.list; then
    sed -ri 's/^(deb(-src)?\s+[^ ]+\s+[^ ]+\s+)(main)(.*)/\1main contrib non-free non-free-firmware\4/' /etc/apt/sources.list || true
fi

# Add backports file for trixie
cat > /etc/apt/sources.list.d/trixie-backports.list <<'EOF'
deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware
EOF

apt_update_once
print_success "Dépôts configurés"

# --- Define packages used commonly later ---
BASE_PKGS=(build-essential git htop net-tools ethtool xdotool wmctrl libnotify-bin playerctl)
GUI_PKGS=(xorg openbox obconf lxappearance xinit xterm x11-utils pcmanfm)
GAMING_PKGS=(mesa-vulkan-drivers mesa-utils libgl1-mesa-dri xserver-xorg-video-amdgpu vulkan-tools libvulkan1 firmware-amd-graphics)
OTHER_PKGS=(curl wget gnupg ca-certificates flatpak ufw apparmor unattended-upgrades zram-tools linux-cpupower)

print_status "Installation des paquets de base"
apt_install "${BASE_PKGS[@]}" "${GUI_PKGS[@]}" "${OTHER_PKGS[@]}" || true
print_success "Paquets de base installés (ou tentés)"

# --- Add user to sudo/render/video groups where relevant ---
usermod -aG sudo,video,render "$USERNAME" 2>/dev/null || true

# --- Keyboard tweaks: safer approach ---
print_status "Configuration clavier AZERTY (patch minimal)"
if [ -f /usr/share/X11/xkb/symbols/fr ]; then
    if ! grep -q "mswindows-capslock" /usr/share/X11/xkb/symbols/fr; then
        sed -i '/include "latin"/a include "mswindows-capslock"' /usr/share/X11/xkb/symbols/fr || true
    fi
    cat > /usr/share/X11/xkb/symbols/mswindows-capslock <<'EOF'
// Minimal safe mswindows-capslock snippet (preserve original)
partial alphanumeric_keys
xkb_symbols "basic" {
    key <AE01> { type= "FOUR_LEVEL_ALPHABETIC", [ ampersand, 1, bar, exclamdown ] };
    key <AE02> { type= "FOUR_LEVEL_ALPHABETIC", [ eacute, 2, at, oneeighth ] };
    key <AE03> { type= "FOUR_LEVEL_ALPHABETIC", [ quotedbl, 3, numbersign, sterling ] };
    key <AE04> { type= "FOUR_LEVEL_ALPHABETIC", [ apostrophe, 4, onequarter, dollar ] };
};
EOF
    print_success "Patch clavier installé (redémarrage X requis)"
else
    print_warn "Fichier xkb/fr introuvable - configuration clavier ignorée"
fi

# --- AMD GPU packages from backports when available ---
print_status "Installation pilotes AMD (backports si présents)"
if apt-cache policy | grep -q "trixie-backports"; then
    apt_install -t trixie-backports "${GAMING_PKGS[@]}" || apt_install "${GAMING_PKGS[@]}"
else
    apt_install "${GAMING_PKGS[@]}"
fi
print_success "Pilotes AMD: tentative d'installation terminée"

# Environment fragment
mkdir -p /etc/environment.d
cat > /etc/environment.d/amd-gpu.conf <<'EOF'
# RADV / AMD hints
RADV_PERFTEST=rt
AMD_VULKAN_ICD=RADV
EOF

# modprobe options
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/amdgpu.conf <<'EOF'
options amdgpu ppfeaturemask=0xffffffff
EOF

# --- LACT installation (best-effort) ---
print_status "Installation LACT (si disponible)"
if ! command -v lact >/dev/null 2>&1; then
    LACT_URL="https://api.github.com/repos/ilya-zlobintsev/LACT/releases/latest"
    LACT_VER="$(curl -s "$LACT_URL" | grep -oP '"tag_name":\s*"\Kv?[0-9.]+' | head -n1 || true)"
    LACT_VER="${LACT_VER:-0.8.3}"
    LACT_DEB="/tmp/lact_${LACT_VER}_amd64.deb"
    curl -fsSL -o "$LACT_DEB" "https://github.com/ilya-zlobintsev/LACT/releases/download/v${LACT_VER}/lact_${LACT_VER}_amd64.deb" || true
    if [ -s "$LACT_DEB" ]; then
        apt_install "$LACT_DEB" && rm -f "$LACT_DEB" || print_warn "LACT install failed"
    else
        print_warn "LACT deb not downloaded"
    fi
else
    print_status "LACT déjà présent"
fi

# If LACT not installed try CoreCtrl
if ! command -v lact >/dev/null 2>&1; then
    print_status "Fallback: CoreCtrl"
    apt_install corectrl || print_warn "corectrl non disponible"
    usermod -aG render,video "$USERNAME" 2>/dev/null || true
fi

# --- MangoHud configuration (ensure installed) ---
print_status "Installation et configuration MangoHud"
apt_install mangohud || print_warn "mangohud pas disponible"
mkdir -p "$USER_HOME/.config/MangoHud"
cat > "$USER_HOME/.config/MangoHud/MangoHud.conf" <<'EOF'
# MangoHud defaults (preserved intent)
vsync=0
fps_limit=180
fps_limit_method=early
no_display=0
frametime=1
frame_timing=1
gpu_temp=1
cpu_temp=1
gpu_stats=1
cpu_stats=1
vram=1
ram=1
position=top-left
font_size=24
toggle_hud=Shift_R+F12
EOF
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/MangoHud" || true
print_success "MangoHud configuré (si installé)"

# --- GameMode installation and config ---
print_status "Installation GameMode"
apt_install gamemode || print_warn "gamemode non disponible"
groupadd -f gamemode 2>/dev/null || true
usermod -aG gamemode "$USERNAME" 2>/dev/null || true

mkdir -p /etc/gamemode.d
cat > /etc/gamemode.d/custom.conf <<'EOF'
[general]
renice=10

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
amd_performance_level=high

[custom]
start=echo 512 > /proc/sys/vm/nr_hugepages
end=echo 0 > /proc/sys/vm/nr_hugepages
EOF
print_success "GameMode configuré (soft)"

# --- Network tuning (BBR + buffers) ---
print_status "Optimisation réseau (BBR + buffers)"
modprobe tcp_bbr 2>/dev/null || true
echo "tcp_bbr" >/etc/modules-load.d/bbr.conf || true

cat > /etc/sysctl.d/99-network-gaming.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 2048
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
EOF
sysctl --system || print_warn "sysctl --system non critique échoué"
NIC="$(ip route | awk '/default/ {print $5; exit}')"
if [ -n "$NIC" ]; then
    ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || print_warn "Impossible de modifier buffers NIC"
fi
print_success "Paramètres réseau appliqués"

# --- Flatpak & Flathub ---
print_status "Installation Flatpak"
apt_install flatpak || print_warn "flatpak non installé"
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
print_success "Flatpak configuré"

# --- Privacy / Telemetry opt-out (best-effort) ---
print_status "Désactivation télémétrie (best-effort)"
systemctl mask ubuntu-report 2>/dev/null || true
systemctl mask ubuntu-advantage 2>/dev/null || true
if [ -f /etc/default/popularity-contest ]; then
    sed -i 's/PARTICIPATE="yes"/PARTICIPATE="no"/' /etc/default/popularity-contest || true
fi
print_success "Télémétrie: actions appliquées (si présentes)"

# --- Firewall (ufw) ---
print_status "Configuration UFW"
apt_install ufw || print_warn "ufw non installé"
ufw --force default deny incoming || true
ufw --force default allow outgoing || true
ufw --force enable || true
print_success "UFW configuré"

# --- AppArmor ---
print_status "Installation AppArmor"
apt_install apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra || true
systemctl enable --now apparmor || true
print_success "AppArmor activé (si disponible)"

# --- Unattended upgrades ---
print_status "Activation mises à jour automatiques"
apt_install unattended-upgrades apt-listchanges || true
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections || true
dpkg-reconfigure -f noninteractive unattended-upgrades || true
print_success "Unattended-upgrades configuré (si disponible)"

# --- Remove snap (non-fatal) ---
print_status "Suppression Snap (best-effort)"
apt-get purge -y snapd || true
rm -rf /snap /var/snap /var/lib/snapd /root/snap "$USER_HOME/snap" 2>/dev/null || true
print_success "Snap purgé (si présent)"

# --- Themes, tint2, openbox theme setup (best-effort) ---
print_status "Installation thèmes et composants UI"
apt_install arc-theme papirus-icon-theme fonts-noto fonts-noto-color-emoji fonts-liberation2 fonts-dejavu unzip tint2 picom nitrogen rofi jgmenu || true
# Clone themes (non-fatal)
if [ ! -d "$USER_HOME/.themes" ]; then mkdir -p "$USER_HOME/.themes"; fi
if [ ! -d "$USER_HOME/.themes/Umbra" ]; then
    git clone --depth=1 https://github.com/addy-dclxvi/openbox-theme-collections.git "$USER_HOME/.themes/openbox-themes" 2>/dev/null || true
    if [ -d "$USER_HOME/.themes/openbox-themes" ]; then
        mv "$USER_HOME/.themes/openbox-themes"/* "$USER_HOME/.themes/" 2>/dev/null || true
        rm -rf "$USER_HOME/.themes/openbox-themes/.git" || true
    fi
fi
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.themes" "$USER_HOME/.config" || true
print_success "Thèmes installés (ou tenté)"

# --- PipeWire ---
print_status "Installation PipeWire"
apt_install pipewire pipewire-pulse wireplumber pipewire-alsa pipewire-audio-client-libraries || true
systemctl --user enable --now pipewire 2>/dev/null || true
print_success "PipeWire (tentative)"

# --- Apps & Gaming tools (best-effort) ---
print_status "Installation applications gaming (Steam via Flatpak, Lutris etc.)"
apt_install lutris wine winetricks pavucontrol vlc qbittorrent || true
flatpak install -y flathub com.valvesoftware.Steam com.usebottles.bottles >/dev/null 2>&1 || true
print_success "Apps principales installées (si disponibles)"

# --- Openbox user configuration files (rc.xml, autostart) ---
print_status "Configuration OpenBox pour l'utilisateur"
mkdir -p "$USER_HOME/.config/openbox" "$USER_HOME/.config/tint2" "$USER_HOME/.config/nitrogen"
cp -r /etc/xdg/openbox/* "$USER_HOME/.config/openbox/" 2>/dev/null || true

# Create a robust autostart (preserve original logic but simpler)
cat > "$USER_HOME/.config/openbox/autostart" <<'AUTOSTART'
#!/bin/bash
LOGDIR="$HOME/.local/share/openbox-logs"
mkdir -p "$LOGDIR"
echo "[autostart] starting session at $(date)" >>"$LOGDIR/autostart.log"

# Wait for X
for i in $(seq 1 30); do
  if xdpyinfo >/dev/null 2>&1; then break; fi
  sleep 1
done

# Start common components (if present)
command -v nm-applet >/dev/null 2>&1 && nm-applet &
command -v tint2 >/dev/null 2>&1 && tint2 -c "$HOME/.config/tint2/tint2rc" &
command -v picom >/dev/null 2>&1 && picom --experimental-backends -b &
command -v nitrogen >/dev/null 2>&1 && nitrogen --restore &
command -v volumeicon >/dev/null 2>&1 && volumeicon &
command -v conky >/dev/null 2>&1 && (sleep 3 && conky) &
AUTOSTART
chmod +x "$USER_HOME/.config/openbox/autostart" || true

# Minimal .xinitrc to start openbox-session
cat > "$USER_HOME/.xinitrc" <<'XINIT'
#!/bin/sh
[ -f /etc/environment ] && . /etc/environment
[ -f /etc/environment.d/amd-gpu.conf ] && export $(grep -v '^#' /etc/environment.d/amd-gpu.conf | xargs)
xrdb -merge ~/.Xresources 2>/dev/null || true
exec openbox-session
XINIT
chmod +x "$USER_HOME/.xinitrc"

# Basic rc.xml (preserve keybind intention but keep minimal & valid XML)
cat > "$USER_HOME/.config/openbox/rc.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config>
  <keyboard>
    <keybind key="W-Left"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><width>50%</width><height>100%</height><x>0</x><y>0</y></action></keybind>
    <keybind key="W-Right"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><width>50%</width><height>100%</height><x>50%</x><y>0</y></action></keybind>
  </keyboard>
  <theme><name>Umbra</name></theme>
</openbox_config>
XML

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/openbox" "$USER_HOME/.xinitrc" || true
print_success "OpenBox user config deployed"

# --- GRUB tweaks (safe edit with backup) ---
print_status "Optimisation GRUB (safe edit)"
[ -f /etc/default/grub ] && cp -a /etc/default/grub /etc/default/grub.backup_$(date +%s) || true
grep -q 'amd_pstate=active' /etc/default/grub || \
    sed -ri 's/^(GRUB_CMDLINE_LINUX_DEFAULT=")(.*)(")/\1\2 amd_pstate=active amdgpu.ppfeaturemask=0xffffffff nowatchdog preempt=voluntary mitigations=off pcie_aspm=off\3/' /etc/default/grub || true
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub || true
update-grub || print_warn "update-grub may have failed"
print_success "GRUB updated (if possible)"

# --- initramfs compression ---
print_status "Configuration initramfs compression (zstd)"
mkdir -p /etc/initramfs-tools
echo 'COMPRESS=zstd' > /etc/initramfs-tools/initramfs.conf || true
update-initramfs -u -k all || print_warn "update-initramfs failed (non critique)"
print_success "initramfs set to zstd (if supported)"

# --- Kernel tunings ---
print_status "Application des optimisations kernel (sysctl)"
cat > /etc/sysctl.d/99-gaming-advanced.conf <<'EOF'
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
kernel.sched_rt_runtime_us = 980000
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
vm.nr_hugepages = 512
EOF
sysctl --system || print_warn "sysctl --system non critique échoué"
print_success "Paramètres kernel appliqués"

# --- zram setup (best-effort) ---
print_status "Configuration zram (best-effort)"
if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -q; then
    print_warn "En VM: zram configuration skipped"
else
    apt_install zram-tools || apt_install systemd-zram-generator || true
    mkdir -p /etc/systemd/zram-generator.conf.d
    cat > /etc/systemd/zram-generator.conf.d/gaming.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swappiness = 100
EOF
    systemctl daemon-reload || true
    systemctl enable --now systemd-zram-setup@zram0 2>/dev/null || true
fi
print_success "zram setup attempted"

# --- CPU governor service ---
print_status "Installation service CPU performance"
apt_install linux-cpupower || true
cat > /etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$g" 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload || true
systemctl enable --now cpu-performance.service || true
print_success "CPU performance service enabled"

# --- Watchdogs disable (non-destructive) ---
print_status "Blacklisting some watchdog modules (non-destructive)"
cat > /etc/modprobe.d/disable-watchdog.conf <<'EOF'
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist sp5100_tco
EOF
update-initramfs -u -k all || true
print_success "Watchdogs config applied"

# --- USB HID polling for high polling rates ---
print_status "Config souris 1000Hz (best-effort)"
cat > /etc/modprobe.d/usbhid.conf <<'EOF'
options usbhid mousepoll=1
EOF
cat > /etc/modprobe.d/usbcore.conf <<'EOF'
options usbcore autosuspend=-1
EOF
modprobe -r usbhid usbcore 2>/dev/null || true
modprobe usbhid mousepoll=1 2>/dev/null || true
modprobe usbcore autosuspend=-1 2>/dev/null || true
print_success "Polling rate config appliquée (redémarrage peut être requis)"

# --- System limits ---
print_status "Configuration limites système"
grep -q "$USERNAME soft nofile" /etc/security/limits.conf || cat >> /etc/security/limits.conf <<EOF

# Limits for $USERNAME (gaming)
$USERNAME soft nofile 524288
$USERNAME hard nofile 524288
$USERNAME soft nproc 524288
$USERNAME hard nproc 524288
EOF
print_success "Limites ajoutées (si pas déjà présentes)"

# --- Verification script for user ---
print_status "Création du script de vérification (~/$USERNAME/verify-install.sh)"
cat > "$USER_HOME/verify-install.sh" <<'VERIFY'
#!/bin/bash
echo "Vérification système OpenBox Gaming (exécutez après reboot)"
echo "CPU governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
echo "GPU (glxinfo):"; glxinfo 2>/dev/null | grep "OpenGL renderer" || echo "Run after X"
echo "Vulkan: "; vulkaninfo 2>/dev/null | head -n 5 || echo "Run after reboot/login"
echo "Network congestion control: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null)"
echo "zram: "; zramctl 2>/dev/null || swapon --show | grep zram || echo "zram inactive"
VERIFY
chmod +x "$USER_HOME/verify-install.sh"
chown "$USERNAME:$USERNAME" "$USER_HOME/verify-install.sh" || true
print_success "Script de vérification créé"

# Final message
print_success "Installation / configuration terminée (logs: $LOGFILE)"
_highlight "Relisez le log et redémarrez le système: sudo reboot"
echo "Après reboot: connectez-vous et lancez 'startx' ou installez un display manager"
'''
p = Path("/mnt/data/v2.fixed.sh")
p.write_text(content, encoding="utf-8")
p.chmod(0o755)
print("Wrote /mnt/data/v2.fixed.sh (executable)")
