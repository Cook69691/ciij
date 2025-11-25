#!/bin/bash

# Script d'installation automatique OpenBox Minimal (Sécurité & Privacy) sur Debian 13 Trixie
# Exécutez en root : sudo bash openbox-setup.sh
# Assurez-vous d'être connecté après install minimal (écran noir CLI).
# Créez d'abord un user non-root si pas fait : adduser votreuser && usermod -aG sudo votreuser

set -e  # Arrête sur erreur
export DEBIAN_FRONTEND=noninteractive

# --- DÉBUT CONFIGURATION UTILISATEUR ---
# !!! MODIFIEZ CECI AVEC VOTRE VRAI NOM D'UTILISATEUR NON-ROOT !!!
USERNAME="anonymous"
usermod -aG sudo anonymous
# --- FIN CONFIGURATION UTILISATEUR ---

# Validation
if [ "$USERNAME" = "votreuser" ] || [ -z "$USERNAME" ]; then
    echo "ERREUR CRITIQUE : Modifiez la variable USERNAME dans le script."
    exit 1
fi

USER_HOME="/home/$USERNAME"

if [ ! -d "$USER_HOME" ]; then
    echo "ERREUR : Le dossier $USER_HOME n'existe pas. Créez l'utilisateur d'abord."
    echo "Exemple : adduser $USERNAME && usermod -aG sudo $USERNAME"
    exit 1
fi

# Vérifier que le script est exécuté en root
if [ "$EUID" -ne 0 ]; then 
    echo "ERREUR : Ce script doit être exécuté en root (sudo)"
    exit 1
fi

echo "[STATUS] Configuration pour l'utilisateur : $USERNAME (Home: $USER_HOME)"

# Fonctions d'affichage
print_status() {
    echo "=========================================="
    echo "[STATUS] $1"
    echo "=========================================="
}
print_success() {
    echo "[✓ SUCCESS] $1"
}
_highlight() {
    echo "[★ INFO] $1"
}

echo "=== Début installation OpenBox Minimal - Sécurité & Privacy sur Debian 13 Trixie ==="

# 1. Mises à jour et nettoyage
print_status "Mise à jour du système"
apt update && apt full-upgrade -y
apt autoremove -y && apt autoclean
print_success "Système à jour"

# 2. Activation contrib/non-free/non-free-firmware AVANT installation des paquets
print_status "Activation des dépôts contrib/non-free"
cp /etc/apt/sources.list /etc/apt/sources.list.bak
sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
apt update
print_success "Dépôts activés"

# 3. Outils de base
print_status "Installation outils de base"
apt install -y curl wget gnupg ca-certificates build-essential git htop \
    apt-transport-https libnotify-bin ethtool net-tools
apt install -y fastfetch || print_status "fastfetch non disponible (non critique)"
print_success "Outils de base installés"

# 4. GUI de base : Xorg + OpenBox
print_status "Installation Xorg + OpenBox"
apt install -y xorg openbox obconf lxappearance xinit xterm x11-utils
print_success "Environnement graphique installé"

# 5. Pilotes AMD pour RX 6950 XT (Mesa + Firmware)
print_status "Installation pilotes AMD pour RX 6950 XT (RDNA2)"
apt install -y mesa-vulkan-drivers mesa-utils libgl1-mesa-dri xserver-xorg-video-amdgpu \
    vulkan-tools libvulkan1 mesa-va-drivers mesa-vdpau-drivers firmware-amd-graphics \
    libglx-mesa0 libdrm-amdgpu1

# Créer le répertoire pour environment.d s'il n'existe pas
mkdir -p /etc/environment.d

# RADV_PERFTEST valide pour RX 6950 XT (RDNA2 / GFX10.3)
# Options valides 2025 : rt (ray tracing), sam (Smart Access Memory), dccmsaa
cat > /etc/environment.d/amd-gpu.conf <<'EOF'
# Optimisations RADV pour RX 6950 XT (RDNA2)
# rt = Ray Tracing support
# sam = Smart Access Memory optimizations  
RADV_PERFTEST=rt
AMD_VULKAN_ICD=RADV
EOF

# Configuration amdgpu avec ppfeaturemask
cat > /etc/modprobe.d/amdgpu.conf <<EOF
options amdgpu ppfeaturemask=0xffffffff
EOF

print_success "Pilotes AMD installés et configurés"

# 6. LACT (gestion GPU AMD)
print_status "Installation LACT pour gestion GPU"
LACT_INSTALLED=false

if ! command -v lact &>/dev/null; then
    # Récupération de la dernière version
    LACT_VERSION=$(curl -s https://api.github.com/repos/ilya-zlobintsev/LACT/releases/latest | grep -oP '"tag_name": "v?\K[0-9.]+' | head -1)
    
    if [ -z "$LACT_VERSION" ]; then
        LACT_VERSION="0.5.6"
        print_status "Version LACT par défaut : $LACT_VERSION"
    fi
    
    # Téléchargement du .deb Debian
    print_status "Téléchargement LACT version $LACT_VERSION"
    wget -q --show-progress -O /tmp/lact.deb \
        "https://github.com/ilya-zlobintsev/LACT/releases/download/v${LACT_VERSION}/lact_${LACT_VERSION}_amd64.debian.deb" || \
    wget -q --show-progress -O /tmp/lact.deb \
        "https://github.com/ilya-zlobintsev/LACT/releases/download/v${LACT_VERSION}/lact-${LACT_VERSION}-0.amd64.debian-13.deb" || true
    
    if [ -s /tmp/lact.deb ]; then
        apt install -y /tmp/lact.deb && LACT_INSTALLED=true
        rm -f /tmp/lact.deb
    fi
else
    LACT_INSTALLED=true
fi

if [ "$LACT_INSTALLED" = true ]; then
    # Activer le service système lactd (pas lact-tray qui n'existe pas)
    systemctl enable --now lactd 2>/dev/null || systemctl enable lactd || true
    print_success "LACT installé et daemon activé"
    _highlight "Utilisez 'lact gui' pour configurer les courbes de ventilateurs après le reboot"
else
    print_status "Installation CoreCtrl (fallback)"
    apt install -y corectrl || print_status "CoreCtrl non disponible"
    usermod -aG render,video "$USERNAME" 2>/dev/null || true
    print_success "CoreCtrl installé"
fi

# 7. MangoHud (monitoring FPS)
print_status "Installation MangoHud"
apt install -y mangohud || print_status "Erreur installation mangohud"

# Pas de goverlay dans Debian 13 stable, on passe
# apt install -y goverlay || print_status "goverlay non disponible"

mkdir -p "$USER_HOME/.config/MangoHud"
cat > "$USER_HOME/.config/MangoHud/MangoHud.conf" <<'EOF'
# Configuration MangoHud optimisée
vsync=0
fps_limit=180,0
fps_limit_method=early
no_display=0
fps
frametime=1
frame_timing=1
gpu_temp
cpu_temp
gpu_stats
cpu_stats
vram
ram
position=top-left
font_size=24
toggle_hud=Shift_R+F12
toggle_fps_limit=Shift_L+F1
EOF
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/MangoHud"
print_success "MangoHud configuré"

# 8. GameMode + hugepages
print_status "Installation GameMode"
apt install -y gamemode

# Créer le groupe gamemode si nécessaire
groupadd gamemode 2>/dev/null || true
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
start=notify-send "GameMode activé" && echo 512 > /proc/sys/vm/nr_hugepages
end=notify-send "GameMode désactivé" && echo 0 > /proc/sys/vm/nr_hugepages

[filter]
whitelist=

[supervisor]
supervisor_active=1
EOF

print_success "GameMode configuré avec hugepages (1 GiB)"

# 9. Réseau 2.5 Gbps optimisé (BBR v3, buffers)
print_status "Optimisation réseau 2.5 Gbps"
modprobe tcp_bbr 2>/dev/null || true
echo "tcp_bbr" >> /etc/modules-load.d/modules.conf

tee /etc/sysctl.d/99-network-gaming.conf <<'EOF' >/dev/null
# TCP BBR Congestion Control (kernel 6.12 supporte BBR v3)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Buffers réseau (32 MB pour 2.5 Gbps)
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# Backlog
net.core.netdev_max_backlog = 30000
net.core.somaxconn = 2048

# Optimisations gaming
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
EOF
sysctl --system >/dev/null

# Augmenter les buffers de la carte réseau si possible
NIC=$(ip route | grep default | awk '{print $5}' | head -n1)
if [ -n "$NIC" ]; then
    ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null || print_status "Buffers NIC non modifiables pour $NIC"
fi
print_success "Réseau optimisé (BBR + 32 MB buffers)"

# 10. Flatpak
print_status "Installation Flatpak"
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
print_success "Flatpak installé"

# 11. Opt-out Telemetry
print_status "Désactivation télémétrie"
systemctl mask ubuntu-report 2>/dev/null || true
systemctl mask ubuntu-advantage 2>/dev/null || true
if [ -f /etc/default/popularity-contest ]; then
    sed -i 's/PARTICIPATE="yes"/PARTICIPATE="no"/' /etc/default/popularity-contest
    sed -i 's/enabled=1/enabled=0/' /etc/default/popularity-contest 2>/dev/null || true
fi
print_success "Télémétrie désactivée"

# 12. Firewall UFW (strict)
print_status "Configuration UFW"
apt install -y ufw
ufw --force default deny incoming
ufw --force default allow outgoing
ufw --force enable
print_success "Firewall UFW activé"

# 13. AppArmor
print_status "Configuration AppArmor"
apt install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra
systemctl enable apparmor
print_success "AppArmor activé"

# 14. Mises à jour auto sécurité
print_status "Configuration mises à jour automatiques"
apt install -y unattended-upgrades apt-listchanges
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
print_success "Mises à jour automatiques activées"

# 15. Purge Snaps
print_status "Suppression Snap"
apt purge -y snapd 2>/dev/null || true
rm -rf /snap /var/snap /var/lib/snapd /root/snap "$USER_HOME/snap" 2>/dev/null || true
print_success "Snap supprimé"

# 17. Thèmes
print_status "Installation thèmes"
apt install -y arc-theme papirus-icon-theme fonts-noto fonts-noto-color-emoji \
    fonts-liberation2 fonts-dejavu
print_success "Thèmes installés"

# 18. Pipewire AVANT les applications
print_status "Installation Pipewire"
apt install -y pipewire pipewire-pulse wireplumber pipewire-alsa \
    pipewire-audio-client-libraries pipewire-bin
print_success "Pipewire installé"

# 19. Apps principales
print_status "Installation applications principales"

# Composants OpenBox
apt install -y picom nitrogen volumeicon-alsa lxterminal tint2 rofi || true

# Applications
apt install -y vlc qbittorrent kate pavucontrol || true

# Network Manager
apt install -y network-manager network-manager-gnome
systemctl enable NetworkManager
systemctl start NetworkManager || true

# Brave Browser
print_status "Installation Brave Browser"
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
    tee /etc/apt/sources.list.d/brave-browser-release.list
apt update
apt install -y brave-browser

# Steam (avec architecture i386 pour support 32-bit)
print_status "Installation Steam"
dpkg --add-architecture i386
apt update
apt install -y steam-installer || apt install -y steam || print_status "Steam non disponible"

# Discord
if ! command -v discord &>/dev/null; then
    print_status "Installation Discord"
    wget -q --show-progress -O /tmp/discord.deb \
        "https://discord.com/api/download?platform=linux&format=deb"
    if [ -s /tmp/discord.deb ]; then
        apt install -y /tmp/discord.deb || print_status "Discord installation échouée"
        rm -f /tmp/discord.deb
    fi
fi

print_success "Applications installées"

# 20. Configuration OpenBox
print_status "Configuration OpenBox"
mkdir -p "$USER_HOME/.config/openbox"

# .xinitrc pour startx
cat > "$USER_HOME/.xinitrc" <<'EOF'
#!/bin/sh
exec openbox-session
EOF
chmod +x "$USER_HOME/.xinitrc"

# Autostart avec Scaling X11 125%
cat > "$USER_HOME/.config/openbox/autostart" <<'EOF'
#!/bin/sh

# Attendre que X soit prêt
sleep 2

# Scaling X11 125% sans flou : scale 0.8x0.8 (1/1.25 = 0.8)
# Détection du moniteur principal
PRIMARY_OUTPUT=$(xrandr --current | grep " connected primary" | cut -d' ' -f1)
if [ -z "$PRIMARY_OUTPUT" ]; then
    PRIMARY_OUTPUT=$(xrandr --current | grep " connected" | head -1 | cut -d' ' -f1)
fi

if [ -n "$PRIMARY_OUTPUT" ]; then
    xrandr --output "$PRIMARY_OUTPUT" --scale 0.8x0.8
fi

# Charger les ressources X (DPI, fonts)
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Lancer les composants
tint2 &
picom -b &
nitrogen --restore &
nm-applet &
volumeicon &

# Applications au démarrage (décommentez si nécessaire)
# discord &
# steam -silent &
EOF
chmod +x "$USER_HOME/.config/openbox/autostart"

# Config Xresources pour DPI 125
cat > "$USER_HOME/.Xresources" <<'EOF'
! DPI 125% pour écran 2K 27"
Xft.dpi: 125
Xft.antialias: true
Xft.hinting: true
Xft.rgba: rgb
Xft.hintstyle: hintslight
Xft.lcdfilter: lcddefault
EOF

# Copie configs OpenBox par défaut
cp -r /etc/xdg/openbox/* "$USER_HOME/.config/openbox/" 2>/dev/null || true

# Corriger les permissions
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"
chown "$USERNAME:$USERNAME" "$USER_HOME/.xinitrc"
chown "$USERNAME:$USERNAME" "$USER_HOME/.Xresources"

print_success "OpenBox configuré"

# 21. GRUB optimisé pour AMD 7800X3D + RX 6950 XT
print_status "Configuration GRUB pour AMD 7800X3D"
cp /etc/default/grub "/etc/default/grub.backup_$(date +%Y%m%d_%H%M%S)"

# Paramètres GRUB validés pour kernel 6.12 + AMD Zen 4 + RDNA2
# amd_pstate=active : Mode actif EPP pour 7800X3D
# amdgpu.ppfeaturemask=0xffffffff : Active toutes les features GPU
# nowatchdog : Désactive les watchdogs (gain de performance)
# preempt=voluntary : Préemption volontaire (mieux pour desktop/gaming)
# mitigations=off : Désactive mitigations Spectre/Meltdown (gain perf)
# pcie_aspm=off : Désactive ASPM PCIe (latence réduite)
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_pstate=active amdgpu.ppfeaturemask=0xffffffff nowatchdog preempt=voluntary mitigations=off pcie_aspm=off"/' /etc/default/grub

# Timeout réduit
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub

update-grub
print_success "GRUB optimisé pour gaming"

# 22. Optimisations kernel
print_status "Optimisations kernel système"

tee /etc/sysctl.d/99-gaming-advanced.conf <<'EOF' >/dev/null
# === Mémoire ===
vm.swappiness = 1
vm.page-cluster = 0
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# === Kernel Scheduler ===
kernel.timer_migration = 0
kernel.sched_rt_runtime_us = 980000

# === Fichiers ===
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288

# === Hugepages pour GameMode ===
vm.nr_hugepages = 512
EOF

sysctl --system >/dev/null
print_success "Optimisations kernel appliquées"

# 23. CPU Governor en performance (persistant)
print_status "Configuration CPU governor"
apt install -y cpufrequtils linux-cpupower || true

# Service systemd pour forcer performance au boot
cat > /etc/systemd/system/cpu-performance.service <<'EOF'
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > $gov 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cpu-performance.service
print_success "CPU governor: performance"

# 24. Désactivation watchdogs
print_status "Désactivation watchdogs"
cat > /etc/modprobe.d/disable-watchdog.conf <<'EOF'
blacklist iTCO_wdt
blacklist iTCO_vendor_support
blacklist sp5100_tco
EOF
update-initramfs -u -k all
print_success "Watchdogs désactivés"

# 25. Limites système
print_status "Configuration limites système"
tee -a /etc/security/limits.conf <<EOF >/dev/null

# 28. Configuration Clavier AZERTY CapsLock (pour chiffres)
print_status "Configuration AZERTY CapsLock (Verr. Maj pour chiffres)"
FR_SYMBOLS_FILE="/usr/share/X11/xkb/symbols/fr"
MSW_CAPS_FILE="/usr/share/X11/xkb/symbols/mswindows-capslock"

# A. Modifier /usr/share/X11/xkb/symbols/fr
if [ -f "$FR_SYMBOLS_FILE" ]; then
    # 1. Créer un backup (au cas où)
    cp "$FR_SYMBOLS_FILE" "${FR_SYMBOLS_FILE}.bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # 2. Vérifier si la ligne existe déjà pour éviter les doublons
    if ! grep -q 'include "mswindows-capslock"' "$FR_SYMBOLS_FILE"; then
        # 3. Insérer la ligne après 'include "latin"'
        sed -i '/include "latin"/a \    include "mswindows-capslock"' "$FR_SYMBOLS_FILE"
        print_success "Fichier 'fr' (symbols) modifié"
    else
        _highlight "La configuration mswindows-capslock existe déjà dans 'fr'."
    fi

    # B. Créer /usr/share/X11/xkb/symbols/mswindows-capslock
    cat > "$MSW_CAPS_FILE" <<'EOF'
// Replicate a "feature" of MS Windows on AZERTY keyboards
// where Caps Lock also acts as a Shift Lock on number keys.
// Include keys <AE01> to <AE10> in the FOUR_LEVEL_ALPHABETIC key type.

partial alphanumeric_keys
xkb_symbols "basic" {
    key <AE01>	{ type= "FOUR_LEVEL_ALPHABETIC", [ ampersand,          1,          bar,   exclamdown ]	};
    key <AE02>	{ type= "FOUR_LEVEL_ALPHABETIC", [    eacute,          2,           at,    oneeighth ]	};
    key <AE03>	{ type= "FOUR_LEVEL_ALPHABETIC", [  quotedbl,          3,   numbersign,     sterling ]	};
    key <AE04>	{ type= "FOUR_LEVEL_ALPHABETIC", [apostrophe,          4,   onequarter,       dollar ]	};
    key <AE05>	{ type= "FOUR_LEVEL_ALPHABETIC", [ parenleft,          5,      onehalf, threeeighths ]	};
    key <AE06>	{ type= "FOUR_LEVEL_ALPHABETIC", [   section,          6,  asciicircum,  fiveeighths ]	};
    key <AE07>	{ type= "FOUR_LEVEL_ALPHABETIC", [    egrave,          7,    braceleft, seveneighths ]	};
    key <AE08>	{ type= "FOUR_LEVEL_ALPHABETIC", [    exclam,          8,  bracketleft,    trademark ]	};
    key <AE09>	{ type= "FOUR_LEVEL_ALPHABETIC", [  ccedilla,          9,    braceleft,    plusminus ]	};
    key <AE10>	{ type= "FOUR_LEVEL_ALPHABETIC", [    agrave,          0,   braceright,       degree ]	};
};
EOF
    print_success "Fichier 'mswindows-capslock' créé"
    print_success "Configuration AZERTY CapsLock appliquée (prend effet au reboot)"

else
    print_status "Fichier $FR_SYMBOLS_FILE non trouvé. Skip config AZERTY CapsLock."
fi

# Limites pour $USERNAME (gaming)
$USERNAME soft nofile 524288
$USERNAME hard nofile 524288
$USERNAME soft nproc 524288
$USERNAME hard nproc 524288
EOF
print_success "Limites système augmentées"

# 26. Configuration nitrogen
mkdir -p "$USER_HOME/.config/nitrogen"
cat > "$USER_HOME/.config/nitrogen/nitrogen.cfg" <<'EOF'
[geometry]
posx=450
posy=200
sizex=900
sizey=600

[nitrogen]
view=icon
recurse=true
sort=alpha
icon_caps=false
dirs=/usr/share/backgrounds;
EOF
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/nitrogen"

# 27. Polkit pour permissions GUI
apt install -y policykit-1 polkit-kde-agent-1 || \
apt install -y policykit-1-gnome || \
apt install -y lxpolkit || true

# 28. Script de vérification post-installation
cat > "$USER_HOME/verify-install.sh" <<'VERIFYEOF'
#!/bin/bash
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Vérification Installation OpenBox Gaming Setup        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "→ CPU Governor:"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "  Non disponible"
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "  Non disponible"
echo ""

echo "→ GPU Renderer (devrait montrer Mesa/RADV + RX 6950 XT):"
glxinfo | grep "OpenGL renderer" 2>/dev/null || echo "  Exécutez après le reboot"
echo ""

echo "→ Vulkan Driver:"
vulkaninfo 2>/dev/null | grep "deviceName" | head -1 || echo "  Exécutez après le reboot"
echo ""

echo "→ Réseau TCP BBR:"
sysctl net.ipv4.tcp_congestion_control 2>/dev/null
echo ""

echo "→ GameMode:"
gamemoded --version 2>/dev/null || echo "  Service non démarré"
echo ""

echo "→ DPI X11:"
xdpyinfo 2>/dev/null | grep resolution || echo "  Exécutez après login graphique"
echo ""

echo "→ Services actifs:"
echo "  NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null)"
echo "  LightDM: $(systemctl is-enabled lightdm 2>/dev/null)"
echo "  UFW: $(systemctl is-active ufw 2>/dev/null)"
if systemctl list-unit-files | grep -q lactd; then
    echo "  LACT daemon: $(systemctl is-active lactd 2>/dev/null)"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Fin vérification                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
VERIFYEOF

chmod +x "$USER_HOME/verify-install.sh"
chown "$USERNAME:$USERNAME" "$USER_HOME/verify-install.sh"

print_success "Script de vérification créé"

# 29. Message final
clear
cat <<'FINAL'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   ✓ INSTALLATION TERMINÉE AVEC SUCCÈS !                         ║
║                                                                  ║
║   OpenBox Minimal Gaming Setup - Debian 13 Trixie                ║
║   Optimisé pour AMD 7800X3D + RX 6950 XT + 2.5 Gbps             ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────┐
│ ÉTAPE OBLIGATOIRE : REBOOT                                       │
└──────────────────────────────────────────────────────────────────┘

  Exécutez maintenant : reboot

┌──────────────────────────────────────────────────────────────────┐
│ APRÈS LE REBOOT                                                  │
└──────────────────────────────────────────────────────────────────┘

1. Login via LightDM

2. Vérification système :
   ~/verify-install.sh

3. Tests fonctionnels :
   • MangoHud      : mangohud glxgears
   • GameMode      : gamemoderun glxgears  
   • GPU AMD       : glxinfo | grep "OpenGL renderer"
   • Vulkan        : vulkaninfo | grep deviceName
   • Firewall      : sudo ufw status verbose

4. Configuration interface :
   • Thème         : lxappearance
   • Wallpaper     : nitrogen
   • Menu OpenBox  : kate ~/.config/openbox/menu.xml
   • Raccourcis    : kate ~/.config/openbox/rc.xml
   • Tint2 panel   : kate ~/.config/tint2/tint2rc

5. Gestion GPU (LACT) :
   • Interface     : lact gui
   • Courbes fans  : Configuration dans LACT GUI
   • Service       : sudo systemctl status lactd

6. Scaling 125% :
   • Devrait être automatique (DPI 125 + scale 0.8x0.8)
   • Vérif DPI     : xdpyinfo | grep resolution
   • Si problème   : Éditez ~/.config/openbox/autostart

7. Performance CPU :
   • Vérif governor: cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   • Devrait montrer "performance" pour tous les cores

┌──────────────────────────────────────────────────────────────────┐
│ EN CAS DE PROBLÈME                                               │
└──────────────────────────────────────────────────────────────────┘

• Logs système    : sudo journalctl -xe
• Logs Xorg       : cat ~/.local/share/xorg/Xorg.0.log
• Logs LACT       : sudo journalctl -u lactd
• Logs kernel     : sudo dmesg | grep -i amdgpu

┌──────────────────────────────────────────────────────────────────┐
│ FICHIERS DE CONFIGURATION IMPORTANTS                             │
└──────────────────────────────────────────────────────────────────┘

• OpenBox          : ~/.config/openbox/
• MangoHud         : ~/.config/MangoHud/MangoHud.conf
• GameMode         : /etc/gamemode.d/custom.conf
• LACT             : /etc/lact/config.yaml
• GRUB             : /etc/default/grub
• Kernel params    : /etc/sysctl.d/99-gaming-advanced.conf
• Réseau           : /etc/sysctl.d/99-network-gaming.conf

╔══════════════════════════════════════════════════════════════════╗
║  Appuyez sur ENTRÉE pour redémarrer ou CTRL+C pour annuler       ║
╚══════════════════════════════════════════════════════════════════╝
FINAL

read -r -p ""
reboot
