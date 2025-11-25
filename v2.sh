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

echo "=== Début installation OpenBox Minimal - Optimisé Gaming sur Debian 13 Trixie ==="

# 1. Mises à jour et nettoyage
print_status "Mise à jour du système"
apt update && apt full-upgrade -y
apt autoremove -y && apt autoclean
print_success "Système à jour"

# 2. Activation contrib/non-free/non-free-firmware + Backports pour Mesa frais
print_status "Activation des dépôts contrib/non-free + backports"
cp /etc/apt/sources.list /etc/apt/sources.list.bak
sed -i 's/main$/main contrib non-free non-free-firmware/g' /etc/apt/sources.list || sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list

# Ajout backports pour Mesa 25.2.4 (Vulkan/RT optims RX 6950 XT)
echo "deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware" | tee /etc/apt/sources.list.d/backports.list
apt update
print_success "Dépôts + backports activés"

# 3. Outils de base
print_status "Installation outils de base"
apt install -y curl wget gnupg ca-certificates build-essential git htop \
    apt-transport-https libnotify-bin ethtool net-tools playerctl
apt install -y fastfetch || print_status "fastfetch non disponible (non critique)"
print_success "Outils de base installés"

# 4. GUI de base : Xorg + OpenBox
print_status "Installation Xorg + OpenBox"
apt install -y xorg openbox obconf lxappearance xinit xterm x11-utils pcmanfm \
    xdotool wmctrl
print_success "Environnement graphique installé"

# Configuration clavier AZERTY pour Verr. Maj sur chiffres
print_status "Configuration clavier AZERTY pour Verr. Maj sur chiffres"
if grep -q 'include "latin"' /usr/share/X11/xkb/symbols/fr 2>/dev/null; then
    sed -i '/include "latin"/a include "mswindows-capslock"' /usr/share/X11/xkb/symbols/fr
else
    echo "AVERTISSEMENT : Fichier /usr/share/X11/xkb/symbols/fr non standard, inclusion manuelle requise."
fi

cat > /usr/share/X11/xkb/symbols/mswindows-capslock <<'EOF'
// Replicate a "feature" of MS Windows on AZERTY keyboards
// where Caps Lock also acts as a Shift Lock on number keys.
// Include keys <AE01> to <AE10> in the FOUR_LEVEL_ALPHABETIC key type.

partial alphanumeric_keys
xkb_symbols "basic" {
key <AE01> { type= "FOUR_LEVEL_ALPHABETIC", [ ampersand, 1, bar, exclamdown ] };
key <AE02> { type= "FOUR_LEVEL_ALPHABETIC", [ eacute, 2, at, oneeighth ] };
key <AE03> { type= "FOUR_LEVEL_ALPHABETIC", [ quotedbl, 3, numbersign, sterling ] };
key <AE04> { type= "FOUR_LEVEL_ALPHABETIC", [apostrophe, 4, onequarter, dollar ] };
key <AE05> { type= "FOUR_LEVEL_ALPHABETIC", [ parenleft, 5, onehalf, threeeighths ] };
key <AE06> { type= "FOUR_LEVEL_ALPHABETIC", [ section, 6, asciicircum, fiveeighths ] };
key <AE07> { type= "FOUR_LEVEL_ALPHABETIC", [ egrave, 7, braceleft, seveneighths ] };
key <AE08> { type= "FOUR_LEVEL_ALPHABETIC", [ exclam, 8, bracketleft, trademark ] };
key <AE09> { type= "FOUR_LEVEL_ALPHABETIC", [ ccedilla, 9, braceleft, plusminus ] };
key <AE10> { type= "FOUR_LEVEL_ALPHABETIC", [ agrave, 0, braceright, degree ] };
};
EOF

print_success "Configuration clavier Verr. Maj activée (redémarrage X11 requis pour appliquer)"

# 5. Pilotes AMD pour RX 6950 XT (Mesa + Firmware) via backports
print_status "Installation pilotes AMD pour RX 6950 XT (RDNA2) via backports"
apt -t trixie-backports install -y mesa-vulkan-drivers mesa-utils libgl1-mesa-dri xserver-xorg-video-amdgpu \
    vulkan-tools libvulkan1 mesa-va-drivers mesa-vdpau-drivers firmware-amd-graphics \
    libglx-mesa0 libdrm-amdgpu1 || apt install -y mesa-vulkan-drivers mesa-utils libgl1-mesa-dri xserver-xorg-video-amdgpu \
    vulkan-tools libvulkan1 mesa-va-drivers mesa-vdpau-drivers firmware-amd-graphics \
    libglx-mesa0 libdrm-amdgpu1

mkdir -p /etc/environment.d

cat > /etc/environment.d/amd-gpu.conf <<'EOF'
# Optimisations RADV pour RX 6950 XT (RDNA2)
RADV_PERFTEST=rt
AMD_VULKAN_ICD=RADV
EOF

cat > /etc/modprobe.d/amdgpu.conf <<EOF
options amdgpu ppfeaturemask=0xffffffff
EOF

print_success "Pilotes AMD installés et configurés (Mesa 25.2.4 backports)"

# 6. LACT (gestion GPU AMD)
print_status "Installation LACT pour gestion GPU"
LACT_INSTALLED=false

if ! command -v lact &>/dev/null; then
    LACT_VERSION=$(curl -s https://api.github.com/repos/ilya-zlobintsev/LACT/releases/latest | grep -oP '"tag_name": "v?\K[0-9.]+' | head -1)
    
    if [ -z "$LACT_VERSION" ]; then
        LACT_VERSION="0.8.3"
        print_status "Version LACT par défaut : $LACT_VERSION"
    fi
    
    print_status "Téléchargement LACT version $LACT_VERSION"
    wget -q --show-progress -O /tmp/lact.deb \
        "https://github.com/ilya-zlobintsev/LACT/releases/download/v${LACT_VERSION}/lact_${LACT_VERSION}_amd64.deb" || true
    
    if [ -s /tmp/lact.deb ]; then
        apt install -y /tmp/lact.deb && LACT_INSTALLED=true
        rm -f /tmp/lact.deb
    fi
else
    LACT_INSTALLED=true
fi

if [ "$LACT_INSTALLED" = true ]; then
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
# TCP BBR Congestion Control
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

# 16. Thèmes
print_status "Installation thèmes"
apt install -y arc-theme papirus-icon-theme fonts-noto fonts-noto-color-emoji \
    fonts-liberation2 fonts-dejavu unzip
print_success "Thèmes installés"

# Installation et configuration thème OpenBox 'Umbra' + Tint2 'Repentance'
print_status "Installation et configuration thème OpenBox 'Umbra' + Tint2 'Repentance'"
mkdir -p "$USER_HOME/.themes"
git clone --depth=1 https://github.com/addy-dclxvi/openbox-theme-collections.git "$USER_HOME/.themes/openbox-themes" 2>/dev/null || print_status "Clone OpenBox themes échoué (téléchargement alternatif)"

if [ -d "$USER_HOME/.themes/openbox-themes" ]; then
    mv "$USER_HOME/.themes/openbox-themes"/* "$USER_HOME/.themes/" 2>/dev/null || true
    rm -rf "$USER_HOME/.themes/openbox-themes" "$USER_HOME/.themes/.git"
fi

# Extraction zip si présent dans Umbra
UMBRA_ZIP="$USER_HOME/.themes/Umbra/Umbra.zip"
if [ -f "$UMBRA_ZIP" ]; then
    unzip -q -o -d "$USER_HOME/.themes/Umbra/" "$UMBRA_ZIP" 2>/dev/null || print_status "Extraction Umbra zip échouée"
    rm -f "$UMBRA_ZIP"
fi

# Téléchargement et configuration Tint2 Repentance
mkdir -p "$USER_HOME/.config/tint2"
wget -q --show-progress --timeout=10 -O "$USER_HOME/.config/tint2/tint2rc" \
    "https://raw.githubusercontent.com/addy-dclxvi/tint2-theme-collections/master/repentance/repentance.tint2rc" 2>/dev/null || \
cat > "$USER_HOME/.config/tint2/tint2rc" <<'TINT2EOF'
# Tint2 config fallback (si download échoue)
panel_items = LTSC
panel_size = 100% 32
panel_position = bottom center horizontal
panel_background_id = 1
font_shadow = 0

background_color = #000000 90
border_width = 0

taskbar_mode = single_desktop
taskbar_padding = 4 0 4
taskbar_background_id = 0
taskbar_active_background_id = 0

task_icon = 1
task_text = 1
task_centered = 1
task_maximum_size = 140 32
task_padding = 6 3
task_background_id = 0
task_active_background_id = 2

clock_format = %H:%M
clock_padding = 10 0
TINT2EOF

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.themes" "$USER_HOME/.config/tint2"
print_success "Thème OpenBox 'Umbra' + Tint2 'Repentance' configuré"

# 17. Pipewire AVANT les applications
print_status "Installation Pipewire"
apt install -y pipewire pipewire-pulse wireplumber pipewire-alsa \
    pipewire-audio-client-libraries pipewire-bin
print_success "Pipewire installé"

# 18. Apps principales + Gaming Tools
print_status "Installation applications principales + Gaming Tools"

# Composants OpenBox
apt install -y picom nitrogen volumeicon-alsa lxterminal tint2 rofi || true

# Applications basiques
apt install -y vlc qbittorrent kate pavucontrol || true

# Network Manager
apt install -y network-manager network-manager-gnome
systemctl enable NetworkManager
systemctl start NetworkManager || true

# Lutris (gestion Wine/Proton non-Steam)
apt install -y lutris wine winetricks || true
usermod -aG wine "$USERNAME" 2>/dev/null || true

# Jgmenu (menu dynamique OpenBox)
apt install -y jgmenu || print_status "Jgmenu non disponible"

# Conky (monitoring overlay)
apt install -y conky-all || print_status "Conky non disponible"

# Brave Browser
print_status "Installation Brave Browser"
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | \
    tee /etc/apt/sources.list.d/brave-browser-release.list
apt update
apt install -y brave-browser

# Discord
if ! command -v discord &>/dev/null; then
    print_status "Installation Discord"
    wget -q --show-progress --timeout=30 -O /tmp/discord.deb \
        "https://discord.com/api/download?platform=linux&format=deb"
    if [ -s /tmp/discord.deb ]; then
        apt install -y /tmp/discord.deb || print_status "Discord installation échouée"
        rm -f /tmp/discord.deb
    fi
fi

# Flatpak Gaming : Steam + Bottles
print_status "Installation Flatpak Gaming Tools"
flatpak install -y flathub com.valvesoftware.Steam 2>/dev/null || print_status "Steam Flatpak échoué (installez manuellement)"
flatpak install -y flathub com.usebottles.bottles 2>/dev/null || print_status "Bottles Flatpak échoué (installez manuellement)"
print_success "Applications + Gaming Tools installés"

# 19. Configuration OpenBox ROBUSTE avec autostart PERFECTIONNÉ
print_status "Configuration OpenBox avec autostart robuste"
mkdir -p "$USER_HOME/.config/openbox"

# .xinitrc avec chargement complet environnement
cat > "$USER_HOME/.xinitrc" <<'EOF'
#!/bin/sh
# Chargement variables environnement AMD/Pipewire
[ -f /etc/environment ] && . /etc/environment
[ -f /etc/environment.d/amd-gpu.conf ] && export $(grep -v '^#' /etc/environment.d/amd-gpu.conf | xargs)

# Merge Xresources
[ -f ~/.Xresources ] && xrdb -merge ~/.Xresources

# Lancer OpenBox
exec openbox-session
EOF
chmod +x "$USER_HOME/.xinitrc"

# Copie configs OpenBox par défaut
cp -r /etc/xdg/openbox/* "$USER_HOME/.config/openbox/" 2>/dev/null || true

# Custom rc.xml avec keybinds gaming
cat > "$USER_HOME/.config/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
    <resistance>
        <strength>10</strength>
        <screen>5</screen>
    </resistance>
    <keyboard>
        <keybind key="W-F1">
            <action name="Desktop"><desktop>1</desktop></action>
        </keybind>
        <keybind key="W-F2">
            <action name="Desktop"><desktop>2</desktop></action>
        </keybind>
        <!-- Snapping/Tiling avec Super+flèches -->
        <keybind key="W-Left">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>100%</height>
                <x>0</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-Right">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>100%</height>
                <x>50%</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-Up">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>100%</width>
                <height>50%</height>
                <x>0</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-Down">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>100%</width>
                <height>50%</height>
                <x>0</x>
                <y>50%</y>
            </action>
        </keybind>
        <keybind key="W-1">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>0</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-2">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>50%</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-3">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>0</x>
                <y>50%</y>
            </action>
        </keybind>
        <keybind key="W-4">
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>50%</x>
                <y>50%</y>
            </action>
        </keybind>
        <!-- Multimedia PipeWire -->
        <keybind key="XF86AudioRaiseVolume">
            <action name="Execute">
                <command>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+</command>
            </action>
        </keybind>
        <keybind key="XF86AudioLowerVolume">
            <action name="Execute">
                <command>wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-</command>
            </action>
        </keybind>
        <keybind key="XF86AudioMute">
            <action name="Execute">
                <command>wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle</command>
            </action>
        </keybind>
        <keybind key="XF86AudioPlay">
            <action name="Execute">
                <command>playerctl play-pause</command>
            </action>
        </keybind>
        <keybind key="XF86AudioNext">
            <action name="Execute">
                <command>playerctl next</command>
            </action>
        </keybind>
        <keybind key="XF86AudioPrev">
            <action name="Execute">
                <command>playerctl previous</command>
            </action>
        </keybind>
        <!-- Hot-reload OpenBox -->
        <keybind key="W-F11">
            <action name="Reconfigure"/>
        </keybind>
    </keyboard>
    <theme>
        <name>Umbra</name>
    </theme>
    <desktops>
        <count>4</count>
    </desktops>
</openbox_config>
EOF

# Autostart PERFECTIONNÉ avec robustesse maximale
cat > "$USER_HOME/.config/openbox/autostart" <<'AUTOSTARTEOF'
#!/bin/bash
# OpenBox Autostart - Version ROBUSTE avec gestion d'erreurs complète

# Répertoire de logs
LOGDIR="$HOME/.local/share/openbox-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/autostart-$(date +%Y%m%d-%H%M%S).log"

# Fonction de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Fonction d'attente X11
wait_for_x11() {
    local max_attempts=30
    local attempt=0
    
    log "Attente de X11..."
    while [ $attempt -lt $max_attempts ]; do
        if xdpyinfo >/dev/null 2>&1; then
            log "✓ X11 prêt après $attempt secondes"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    log "✗ ERREUR: X11 non disponible après ${max_attempts}s"
    return 1
}

# Fonction de lancement avec retry
launch_with_retry() {
    local cmd="$1"
    local name="$2"
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if pgrep -x "$name" > /dev/null; then
            log "✓ $name déjà en cours d'exécution"
            return 0
        fi
        
        log "Lancement $name (tentative $((retry+1))/$max_retries)..."
        eval "$cmd" 2>>"$LOGDIR/${name}-error.log" &
        sleep 2
        
        if pgrep -x "$name" > /dev/null; then
            log "✓ $name démarré avec succès"
            return 0
        fi
        
        retry=$((retry + 1))
    done
    
    log "✗ ÉCHEC: $name n'a pas pu démarrer après $max_retries tentatives"
    return 1
}

# Début du script
log "=== Démarrage autostart OpenBox ==="

# Attendre X11
if ! wait_for_x11; then
    log "ERREUR CRITIQUE: Impossible de continuer sans X11"
    notify-send -u critical "Erreur OpenBox" "X11 non disponible - vérifiez $LOGFILE"
    exit 1
fi

# Charger les ressources X11
log "Chargement Xresources..."
if [ -f "$HOME/.Xresources" ]; then
    xrdb -merge "$HOME/.Xresources" 2>>"$LOGFILE" || log "⚠ Échec chargement Xresources"
else
    log "⚠ Fichier .Xresources non trouvé"
fi

# Configuration scaling X11 (125% = scale 0.8x0.8)
log "Configuration scaling X11 125%..."
PRIMARY_OUTPUT=$(xrandr --current 2>/dev/null | grep " connected primary" | cut -d' ' -f1)
if [ -z "$PRIMARY_OUTPUT" ]; then
    PRIMARY_OUTPUT=$(xrandr --current 2>/dev/null | grep " connected" | head -1 | cut -d' ' -f1)
fi

if [ -n "$PRIMARY_OUTPUT" ]; then
    if xrandr --output "$PRIMARY_OUTPUT" --scale 0.8x0.8 2>>"$LOGFILE"; then
        log "✓ Scaling appliqué sur $PRIMARY_OUTPUT"
    else
        log "⚠ Échec scaling sur $PRIMARY_OUTPUT"
    fi
else
    log "⚠ Aucun moniteur détecté pour scaling"
fi

# Délai stabilisation (drivers AMD + Pipewire)
log "Stabilisation système (7s)..."
sleep 7

# Lancement Tint2 (barre des tâches) - ROBUSTE
log "=== Lancement Tint2 ==="
TINT2_CONFIG="$HOME/.config/tint2/tint2rc"
if [ -f "$TINT2_CONFIG" ]; then
    launch_with_retry "tint2 -c '$TINT2_CONFIG'" "tint2"
else
    log "⚠ Config tint2 non trouvée, utilisation config par défaut"
    launch_with_retry "tint2" "tint2"
fi

# Si tint2 échoue toujours, essayer fallback panel alternatif
if ! pgrep -x tint2 > /dev/null; then
    log "⚠ Tentative fallback: lxpanel..."
    launch_with_retry "lxpanel" "lxpanel" || log "✗ Aucun panel disponible"
fi

# Picom (compositeur) - Experimental backends pour AMD sans stutter
log "=== Lancement Picom ==="
launch_with_retry "picom --experimental-backends -b" "picom"

# Nitrogen (wallpaper)
log "=== Lancement Nitrogen ==="
if command -v nitrogen >/dev/null 2>&1; then
    nitrogen --restore 2>>"$LOGFILE" &
    log "✓ Nitrogen wallpaper restauré"
else
    log "⚠ Nitrogen non installé"
fi

# NetworkManager Applet
log "=== Lancement nm-applet ==="
launch_with_retry "nm-applet" "nm-applet"

# VolumeIcon (contrôle volume)
log "=== Lancement VolumeIcon ==="
launch_with_retry "volumeicon" "volumeicon"

# Conky (monitoring overlay) - avec délai supplémentaire
log "=== Lancement Conky ==="
sleep 3
if command -v conky >/dev/null 2>&1; then
    if [ -f "$HOME/.conkyrc" ]; then
        conky -c "$HOME/.conkyrc" 2>>"$LOGFILE" &
        log "✓ Conky démarré avec config personnalisée"
    else
        conky 2>>"$LOGFILE" &
        log "✓ Conky démarré avec config par défaut"
    fi
else
    log "⚠ Conky non installé"
fi

# Discord (avec délai pour stabilité réseau)
log "=== Lancement Discord ==="
sleep 5
if command -v discord >/dev/null 2>&1; then
    discord --start-minimized 2>>"$LOGDIR/discord-error.log" &
    log "✓ Discord démarré en arrière-plan"
else
    log "⚠ Discord non installé"
fi

# Fin
log "=== Autostart terminé ==="
log "Consultez les logs dans: $LOGDIR"
notify-send "OpenBox" "Session démarrée avec succès" -t 3000
AUTOSTARTEOF
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

# Conkyrc basique si pas présent
if [ ! -f "$USER_HOME/.conkyrc" ]; then
    cat > "$USER_HOME/.conkyrc" <<'CONKYEOF'
conky.config = {
    alignment = 'top_right',
    background = false,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = 'white',
    default_outline_color = 'white',
    default_shade_color = 'white',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    gap_x = 20,
    gap_y = 60,
    maximum_width = 280,
    minimum_height = 5,
    minimum_width = 5,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_ncurses = false,
    out_to_stderr = false,
    out_to_x = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 180,
    show_graph_range = false,
    show_graph_scale = false,
    stippled_borders = 0,
    update_interval = 2.0,
    uppercase = false,
    use_spacer = 'none',
    use_xft = true,
    font = 'DejaVu Sans Mono:size=10',
}

conky.text = [[
${color grey}Info:$color ${scroll 32 Debian 13 Trixie - OpenBox Gaming}
${color grey}Uptime:$color $uptime
${color grey}Frequency (in MHz):$color $freq
${color grey}Frequency (in GHz):$color $freq_g
${color grey}RAM Usage:$color $mem/$memmax - $memperc% ${membar 4}
${color grey}CPU Usage:$color $cpu% ${cpubar 4}
${color grey}Processes:$color $processes  ${color grey}Running:$color $running_processes
$hr
${color grey}File systems:
 / $color${fs_used /}/${fs_size /} ${fs_bar 6 /}
${color grey}Networking:
Up:$color ${upspeed} ${color grey} - Down:$color ${downspeed}
$hr
${color grey}Name              PID     CPU%   MEM%
${color lightgrey} ${top name 1} ${top pid 1} ${top cpu 1} ${top mem 1}
${color lightgrey} ${top name 2} ${top pid 2} ${top cpu 2} ${top mem 2}
${color lightgrey} ${top name 3} ${top pid 3} ${top cpu 3} ${top mem 3}
]]
CONKYEOF
fi

# Corriger les permissions
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"
chown "$USERNAME:$USERNAME" "$USER_HOME/.xinitrc" "$USER_HOME/.Xresources" "$USER_HOME/.conkyrc" 2>/dev/null || true

print_success "OpenBox configuré avec autostart ROBUSTE et logging complet"
_highlight "Les logs de démarrage seront dans ~/.local/share/openbox-logs/"

# 20. GRUB optimisé
print_status "Configuration GRUB pour AMD 7800X3D"
cp /etc/default/grub "/etc/default/grub.backup_$(date +%Y%m%d_%H%M%S)"

sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_pstate=active amdgpu.ppfeaturemask=0xffffffff nowatchdog preempt=voluntary mitigations=off pcie_aspm=off"/' /etc/default/grub
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub

update-grub
print_success "GRUB optimisé pour gaming"

# 21. Compression initramfs zstd
print_status "Configuration initramfs zstd pour boot rapide"
echo 'COMPRESS=zstd' > /etc/initramfs-tools/initramfs.conf
update-initramfs -u -k all
print_success "Initramfs zstd configuré"

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

# zram
print_status "Configuration zram (swap compressé pour gaming)"
apt install -y zram-tools 2>/dev/null || apt install -y systemd-zram-generator 2>/dev/null || true
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/gaming.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swappiness = 100
EOF
systemctl daemon-reload
systemctl enable --now systemd-zram-setup@zram0 2>/dev/null || true
print_success "zram configuré"

# 23. CPU Governor
print_status "Configuration CPU governor"
apt install -y linux-cpupower || true

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

# Configuration polling rate souris 1000Hz
print_status "Configuration polling rate souris 1000Hz"

cat > /etc/modprobe.d/usbcore.conf <<EOF
options usbcore autosuspend=-1
EOF

cat > /etc/modprobe.d/usbhid.conf <<EOF
options usbhid mousepoll=1
EOF

modprobe -r usbhid usbcore 2>/dev/null || true
modprobe usbhid mousepoll=1 2>/dev/null || true
modprobe usbcore autosuspend=-1 2>/dev/null || true

print_success "Polling rate souris forcé à 1000Hz"

# 25. Limites système
print_status "Configuration limites système"
tee -a /etc/security/limits.conf <<EOF >/dev/null

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

# 27. Polkit
apt install -y policykit-1 polkit-kde-agent-1 2>/dev/null || \
apt install -y policykit-1-gnome 2>/dev/null || \
apt install -y lxpolkit 2>/dev/null || true

# 28. Script de vérification amélioré
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

echo "→ GPU Renderer:"
glxinfo 2>/dev/null | grep "OpenGL renderer" || echo "  Exécutez après le reboot"
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

echo "→ zram Status:"
zramctl 2>/dev/null || swapon --show | grep zram || echo "  zram non actif"
echo ""

echo "→ Polling rate souris:"
cat /sys/module/usbhid/parameters/mousepoll 2>/dev/null || echo "  Non disponible (reboot requis)"
echo ""

echo "→ Services actifs:"
echo "  NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null)"
echo "  UFW: $(systemctl is-active ufw 2>/dev/null)"
if systemctl list-unit-files | grep -q lactd; then
    echo "  LACT daemon: $(systemctl is-active lactd 2>/dev/null)"
fi
echo ""

echo "→ Logs autostart OpenBox:"
if [ -d "$HOME/.local/share/openbox-logs" ]; then
    LATEST_LOG=$(ls -t "$HOME/.local/share/openbox-logs/autostart-"*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_LOG" ]; then
        echo "  Log le plus récent: $LATEST_LOG"
        echo "  Dernières lignes:"
        tail -n 5 "$LATEST_LOG" | sed 's/^/    /'
    else
        echo "  Aucun log trouvé (pas encore de session X11)"
    fi
else
    echo "  Répertoire de logs non créé (première session requise)"
fi
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Fin vérification                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
VERIFYEOF

chmod +x "$USER_HOME/verify-install.sh"
chown "$USERNAME:$USERNAME" "$USER_HOME/verify-install.sh"

print_success "Script de vérification créé (étendu gaming)"

# 29. Message final
clear
cat <<'FINAL'
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   ✓ INSTALLATION TERMINÉE AVEC SUCCÈS !                         ║
║                                                                  ║
║   OpenBox Minimal Gaming Setup - Debian 13 Trixie (Optimisé 2025)║
║   AMD 7800X3D + RX 6950 XT + 2.5 Gbps + zram/Mesa 25.2.4        ║
║   VERSION CORRIGÉE - Autostart robuste avec logs                ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝

┌──────────────────────────────────────────────────────────────────┐
│ ÉTAPE OBLIGATOIRE : REBOOT                                       │
└──────────────────────────────────────────────────────────────────┘

  Exécutez maintenant : reboot

┌──────────────────────────────────────────────────────────────────┐
│ APRÈS LE REBOOT                                                  │
└──────────────────────────────────────────────────────────────────┘

1. Login via startx (ou installez LightDM si besoin : apt install lightdm)

2. Vérification système :
   ~/verify-install.sh

3. **NOUVEAU - Logs Autostart** :
   cat ~/.openbox-autostart.log
   → Vérifiez que tous les composants se sont lancés
   → Si Tint2 KO : erreurs dans ~/.tint2-errors.log

4. Tests fonctionnels :
   • MangoHud      : mangohud glxgears
   • GameMode      : gamemoderun glxgears  
   • GPU AMD       : glxinfo | grep "OpenGL renderer" (Mesa 25.2.4)
   • Vulkan        : vulkaninfo | grep deviceName
   • zram          : zramctl
   • Keybinds      : Super+flèches (snapping), XF86Audio (volume)

5. Configuration interface :
   • Thème         : lxappearance
   • Wallpaper     : nitrogen
   • Menu (Jgmenu) : jgmenu_run
   • Menu OpenBox  : kate ~/.config/openbox/menu.xml
   • Raccourcis    : kate ~/.config/openbox/rc.xml
   • Tint2 panel   : kate ~/.config/tint2/tint2rc
   • Conky         : conky (overlay monitoring)

6. Gestion GPU (LACT) :
   • Interface     : lact gui
   • Courbes fans  : Configuration dans LACT GUI
   • Service       : sudo systemctl status lactd

7. Gaming Setup :
   • Steam         : flatpak run com.valvesoftware.Steam
   • Lutris        : lutris (ajoutez jeux non-Steam)
   • Bottles       : flatpak run com.usebottles.bottles (Wine sandbox)
   • Proton        : Dans Steam, activez Proton Experimental

print_section
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║             VERSION 6.1 TERMINÉE – PARFAIT !              ║${NC}"
echo -e "${GREEN}║              V2 OPENBOX        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
print_section

echo -e "${YELLOW}Redémarre maintenant → sudo reboot${NC}"
echo -e "${MAGENTA}Après reboot : lance CoreCtrl ou LACT, et profite !${NC}"
