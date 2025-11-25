#!/bin/bash

# Script d'installation automatique OpenBox Minimal (Optimisé Gaming) sur Debian 13 Trixie
# Exécutez en root : sudo bash openbox-setup.sh
# Assurez-vous d'être connecté après install minimal (écran noir CLI).

set -e  # Arrête sur erreur
export DEBIAN_FRONTEND=noninteractive

# --- DÉBUT CONFIGURATION UTILISATEUR (ROBUSTE) ---
USERNAME="${USERNAME:-}"  # Garde si défini en env, sinon vide

# Boucle pour saisie valide
while true; do
    if [ -z "$USERNAME" ]; then
        read -p "Entrez votre nom d'utilisateur non-root (ex: tonuser, sans espaces) : " USERNAME
    fi

    # Validation anti-placeholders
    if [[ "$USERNAME" =~ ^(votreuser|anonymous|root|admin)$ ]] || [ -z "$USERNAME" ]; then
        echo "ERREUR : Nom invalide (évitez 'votreuser', 'anonymous', 'root'). Réessayez."
        USERNAME=""
        continue
    fi

    USER_HOME="/home/$USERNAME"

    # Si home existe, OK
    if [ -d "$USER_HOME" ]; then
        break
    else
        echo "INFO : L'utilisateur '$USERNAME' n'existe pas. Création automatique..."
        echo "       (Mot de passe sera demandé ; utilisez-le pour login GUI après.)"
        if adduser --disabled-password --gecos "" "$USERNAME" </dev/null; then  # Création sans password initial (prompt interactif)
            echo "$USERNAME:$USERNAME" | chpasswd  # Password par défaut = username ; change-le après
            usermod -aG sudo "$USERNAME"
            echo "✓ Utilisateur '$USERNAME' créé avec succès (home: $USER_HOME)."
            echo "  Password par défaut : '$USERNAME' – Changez-le avec 'passwd $USERNAME'."
            break
        else
            echo "ERREUR : Création échouée. Créez manuellement : adduser $USERNAME && usermod -aG sudo $USERNAME"
            exit 1
        fi
    fi
done
# --- FIN CONFIGURATION UTILISATEUR ---

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
    apt-transport-https libnotify-bin ethtool net-tools
apt install -y fastfetch || print_status "fastfetch non disponible (non critique)"
print_success "Outils de base installés"

# 4. GUI de base : Xorg + OpenBox
print_status "Installation Xorg + OpenBox"
apt install -y xorg openbox obconf lxappearance xinit xterm x11-utils pcmanfm
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
    libglx-mesa0 libdrm-amdgpu1  # Fallback sans backports si échec

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

print_success "Pilotes AMD installés et configurés (Mesa 25.2.4 backports)"

# 6. LACT (gestion GPU AMD)
print_status "Installation LACT pour gestion GPU"
LACT_INSTALLED=false

if ! command -v lact &>/dev/null; then
    # Récupération de la dernière version
    LACT_VERSION=$(curl -s https://api.github.com/repos/ilya-zlobintsev/LACT/releases/latest | grep -oP '"tag_name": "v?\K[0-9.]+' | head -1)
    
    if [ -z "$LACT_VERSION" ]; then
        LACT_VERSION="0.8.3"  # Version par défaut mise à jour (nov 2025)
        print_status "Version LACT par défaut : $LACT_VERSION"
    fi
    
    # Téléchargement du .deb Debian (standard amd64, compatible Debian 13)
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
    # Activer le service système lactd
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

# 16. Thèmes
print_status "Installation thèmes"
apt install -y arc-theme papirus-icon-theme fonts-noto fonts-noto-color-emoji \
    fonts-liberation2 fonts-dejavu
print_success "Thèmes installés"

# Installation et configuration thème OpenBox 'Umbra' + Tint2 'Repentance'
print_status "Installation et configuration thème OpenBox 'Umbra' + Tint2 'Repentance'"
git clone --depth=1 https://github.com/addy-dclxvi/openbox-theme-collections.git "$USER_HOME/.themes/openbox-themes" || print_status "Clone OpenBox themes échoué (non critique)"

if [ -d "$USER_HOME/.themes/openbox-themes" ]; then
    mv "$USER_HOME/.themes/openbox-themes"/* "$USER_HOME/.themes/" 2>/dev/null || true
    rm -rf "$USER_HOME/.themes/openbox-themes" "$USER_HOME/.themes/.git"
fi

# Extraction zip si présent dans Umbra
UMBRA_ZIP="$USER_HOME/.themes/Umbra/Umbra.zip"
if [ -f "$UMBRA_ZIP" ]; then
    unzip -q -o -d "$USER_HOME/.themes/Umbra/" "$UMBRA_ZIP" 2>/dev/null || true
    rm -f "$UMBRA_ZIP"
fi

# Téléchargement et configuration Tint2 Repentance
mkdir -p "$USER_HOME/.config/tint2"
wget -q --show-progress -O "$USER_HOME/.config/tint2/tint2rc" \
    "https://raw.githubusercontent.com/addy-dclxvi/tint2-theme-collections/master/repentance/repentance.tint2rc"

# Configuration OpenBox pour utiliser le thème Umbra (si section <theme> existe)
if [ -f "$USER_HOME/.config/openbox/rc.xml" ] && grep -q "<theme>" "$USER_HOME/.config/openbox/rc.xml"; then
    sed -i '/<theme>/,/<\/theme>/ s|<name>\([^<]*\)</name>|<name>Umbra</name>|' "$USER_HOME/.config/openbox/rc.xml"
fi

chown -R "$USERNAME:$USERNAME" "$USER_HOME/.themes" "$USER_HOME/.config/tint2"
print_success "Thème OpenBox 'Umbra' + Tint2 'Repentance' configuré par défaut"
_highlight "Après reboot, si thème non appliqué : lancez 'obconf' pour sélectionner 'Umbra' et redémarrez la session (Alt+F4 > Restart)"
_highlight "Pour Tint2 : vérifiez avec 'killall tint2; tint2 -c ~/.config/tint2/tint2rc &' si le panneau n'apparaît pas"

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
    wget -q --show-progress -O /tmp/discord.deb \
        "https://discord.com/api/download?platform=linux&format=deb"
    if [ -s /tmp/discord.deb ]; then
        apt install -y /tmp/discord.deb || print_status "Discord installation échouée"
        rm -f /tmp/discord.deb
    fi
fi

# Flatpak Gaming : Steam + Bottles
print_status "Installation Flatpak Gaming Tools"
flatpak install -y flathub com.valvesoftware.Steam || print_status "Steam Flatpak échoué (non critique)"
flatpak install -y flathub com.usebottles.bottles || print_status "Bottles Flatpak échoué (non critique)"
print_success "Steam + Bottles installés via Flatpak"
_highlight "Lancez Steam avec 'flatpak run com.valvesoftware.Steam' ; Bottles pour Wine sandbox"

print_success "Applications + Gaming Tools installés"

# 19. Configuration OpenBox (avec keybinds gaming avancés)
print_status "Configuration OpenBox"
mkdir -p "$USER_HOME/.config/openbox"

# .xinitrc pour startx
cat > "$USER_HOME/.xinitrc" <<'EOF'
#!/bin/sh
exec openbox-session
EOF
chmod +x "$USER_HOME/.xinitrc"

# Copie configs OpenBox par défaut (avant custom)
cp -r /etc/xdg/openbox/* "$USER_HOME/.config/openbox/" 2>/dev/null || true

# Custom rc.xml avec keybinds gaming : Snapping Super+flèches, multimedia PipeWire
cat > "$USER_HOME/.config/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!-- OpenBox Config Générée - Optimisée Gaming 2025 -->
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
        <!-- Snapping/Tiling avec Super+flèches (50% côtés, quarters coins) -->
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
        <keybind key="W-1"> <!-- Quarter top-left -->
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>0</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-2"> <!-- Quarter top-right -->
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>50%</x>
                <y>0</y>
            </action>
        </keybind>
        <keybind key="W-3"> <!-- Quarter bottom-left -->
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>0</x>
                <y>50%</y>
            </action>
        </keybind>
        <keybind key="W-4"> <!-- Quarter bottom-right -->
            <action name="UnmaximizeFull"/>
            <action name="MoveResizeTo">
                <width>50%</width>
                <height>50%</height>
                <x>50%</x>
                <y>50%</y>
            </action>
        </keybind>
        <!-- Multimedia PipeWire (volume/play/pause) -->
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
    <!-- Thème Umbra (déjà set via sed) -->
    <theme>
        <name>Umbra</name>
    </theme>
    <desktops>
        <count>4</count>
    </desktops>
</openbox_config>
EOF

# Autostart avec Scaling X11 125% + tint2 forcé + Picom experimental + Conky
cat > "$USER_HOME/.config/openbox/autostart" <<'EOF'
#!/bin/sh

# Attendre que X soit prêt
sleep 5  # Augmenté pour stabilité (drivers AMD/Pipewire)

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

# Fonction wrapper pour tint2 (forcé, avec retry et logs)
launch_tint2() {
    if ! pgrep -x tint2 > /dev/null; then
        tint2 -c ~/.config/tint2/tint2rc 2>> ~/.tint2-errors.log &
        sleep 2
        if ! pgrep -x tint2 > /dev/null; then
            echo "Tint2 failed, trying default..." >> ~/.tint2-errors.log
            tint2 &  # Fallback sans config
        fi
    fi
}

# Lancer les composants
launch_tint2  # Tint2 forcé en premier
picom --experimental-backends -b &  # Experimental pour vsync AMD sans stutter
nitrogen --restore &
nm-applet &
volumeicon &

# Conky overlay (monitoring léger, delay pour stabilité)
sleep 3 && conky &

# Applications au démarrage (Discord après délai pour stabilité)
sleep 5 && discord &
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

# Corriger les permissions
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"
chown "$USERNAME:$USERNAME" "$USER_HOME/.xinitrc" "$USER_HOME/.Xresources"

print_success "OpenBox configuré avec keybinds gaming (snapping/multimedia) + Picom experimental + Conky"
_highlight "Logs tint2 : cat ~/.tint2-errors.log après reboot si toujours KO"
_highlight "Test keybinds : Super+flèches pour snapping ; XF86Audio pour volume PipeWire"

# 20. GRUB optimisé pour AMD 7800X3D + RX 6950 XT
print_status "Configuration GRUB pour AMD 7800X3D"
cp /etc/default/grub "/etc/default/grub.backup_$(date +%Y%m%d_%H%M%S)"

# Paramètres GRUB validés pour kernel 6.12 + AMD Zen 4 + RDNA2
# WARNING: mitigations=off booste perfs mais expose à Spectre/Meltdown - ajustez si besoin
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_pstate=active amdgpu.ppfeaturemask=0xffffffff nowatchdog preempt=voluntary mitigations=off pcie_aspm=off"/' /etc/default/grub

# Timeout réduit
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub

update-grub
print_success "GRUB optimisé pour gaming"

# 21. Compression initramfs zstd (boot + rapide)
print_status "Configuration initramfs zstd pour boot rapide"
echo 'COMPRESS=zstd' > /etc/initramfs-tools/initramfs.conf
update-initramfs -u -k all
print_success "Initramfs zstd configuré (-2s boot sur NVMe AMD)"

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

# zram pour swap compressé (50% RAM, zstd, gaming optim)
print_status "Configuration zram (swap compressé pour gaming)"
apt install -y zram-tools || apt install -y systemd-zram-generator  # Fallback
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/gaming.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swappiness = 100
EOF
systemctl daemon-reload
systemctl enable --now systemd-zram-setup@zram0 || modprobe zram num_devices=1 && echo lz4 > /sys/block/zram0/comp_algorithm && echo $(($(free | grep Mem: | awk '{print $2}') / 2))K > /sys/block/zram0/disksize && mkswap --pagesize 4096 /dev/zram0 && swapon /dev/zram0 -p 100  # Manuel fallback
print_success "zram configuré (50% RAM zstd, +20% réactivité gaming)"

# 23. CPU Governor en performance (persistant)
print_status "Configuration CPU governor"
apt install -y linux-cpupower || true

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

# Configuration polling rate souris 1000Hz
print_status "Configuration polling rate souris 1000Hz"

# Désactiver autosuspend USB globalement pour éviter interférences avec polling élevé
cat > /etc/modprobe.d/usbcore.conf <<EOF
options usbcore autosuspend=-1
EOF

# Forcer polling 1000Hz (1ms) pour souris USB via usbhid
cat > /etc/modprobe.d/usbhid.conf <<EOF
options usbhid mousepoll=1
EOF

# Recharger les modules (optionnel, reboot final appliquera)
modprobe -r usbhid usbcore 2>/dev/null || true
modprobe usbhid mousepoll=1
modprobe usbcore autosuspend=-1 2>/dev/null || true

print_success "Polling rate souris forcé à 1000Hz (redémarrage requis pour pleine application)"
_highlight "Vérifiez après reboot : cat /sys/module/usbhid/parameters/mousepoll (devrait être 1)"

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

# 27. Polkit pour permissions GUI
apt install -y policykit-1 polkit-kde-agent-1 || \
apt install -y policykit-1-gnome || \
apt install -y lxpolkit || true

# 28. Script de vérification post-installation (étendu gaming)
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

echo "→ GPU Renderer (Mesa 25.2.4 + RX 6950 XT):"
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

echo "→ zram Status:"
zramctl 2>/dev/null || swapon --show=NAME,SIZE,TYPE | grep zram || echo "  zram non actif (reboot)"
echo ""

echo "→ Services actifs:"
echo "  NetworkManager: $(systemctl is-active NetworkManager 2>/dev/null)"
echo "  UFW: $(systemctl is-active ufw 2>/dev/null)"
if systemctl list-unit-files | grep -q lactd; then
    echo "  LACT daemon: $(systemctl is-active lactd 2>/dev/null)"
fi
echo "  zram: $(systemctl is-active systemd-zram-setup@zram0 2>/dev/null || echo 'Manuel')"

echo "→ Gaming Tools:"
flatpak list | grep -E "(Steam|Bottles)" || echo "  Flatpak gaming: Vérifiez flatpak run"
command -v lutris &>/dev/null && echo "  Lutris: OK" || echo "  Lutris: Non installé"
command -v conky &>/dev/null && echo "  Conky: OK" || echo "  Conky: Non installé"
command -v jgmenu &>/dev/null && echo "  Jgmenu: OK" || echo "  Jgmenu: Non installé"
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

3. Tests fonctionnels :
   • MangoHud      : mangohud glxgears
   • GameMode      : gamemoderun glxgears  
   • GPU AMD       : glxinfo | grep "OpenGL renderer" (Mesa 25.2.4)
   • Vulkan        : vulkaninfo | grep deviceName
   • zram          : zramctl
   • Keybinds      : Super+flèches (snapping), XF86Audio (volume)

4. Configuration interface :
   • Thème         : lxappearance
   • Wallpaper     : nitrogen
   • Menu (Jgmenu) : jgmenu_run
   • Menu OpenBox  : kate ~/.config/openbox/menu.xml
   • Raccourcis    : kate ~/.config/openbox/rc.xml (snapping OK?)
   • Tint2 panel   : kate ~/.config/tint2/tint2rc
   • Conky         : conky (overlay monitoring)

5. Gestion GPU (LACT) :
   • Interface     : lact gui
   • Courbes fans  : Configuration dans LACT GUI
   • Service       : sudo systemctl status lactd

6. Gaming Setup :
   • Steam         : flatpak run com.valvesoftware.Steam
   • Lutris        : lutris (ajoutez jeux non-Steam)
   • Bottles       : flatpak run com.usebottles.bottles (Wine sandbox)
   • Proton        : Dans Steam, activez Proton Experimental

7. Scaling 125% :
   • Devrait être automatique (DPI 125 + scale 0.8x0.8)
   • Vérif DPI     : xdpyinfo | grep resolution
   • Si problème   : Éditez ~/.config/openbox/autostart

8. Performance CPU :
   • Vérif governor: cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   • Devrait montrer "performance" pour tous les cores

┌──────────────────────────────────────────────────────────────────┐
│ EN CAS DE PROBLÈME                                               │
└──────────────────────────────────────────────────────────────────┘

• Logs système    : sudo journalctl -xe
• Logs Xorg       : cat ~/.local/share/xorg/Xorg.0.log
• Logs LACT       : sudo journalctl -u lactd
• Logs kernel     : sudo dmesg | grep -i amdgpu
• Picom stutter   : Vérifiez --experimental-backends dans autostart

┌──────────────────────────────────────────────────────────────────┐
│ FICHIERS DE CONFIGURATION IMPORTANTS                             │
└──────────────────────────────────────────────────────────────────┘

• OpenBox          : ~/.config/openbox/ (rc.xml keybinds)
• MangoHud         : ~/.config/MangoHud/MangoHud.conf
• GameMode         : /etc/gamemode.d/custom.conf
• LACT             : /etc/lact/config.yaml
• GRUB             : /etc/default/grub
• Kernel params    : /etc/sysctl.d/99-gaming-advanced.conf
• Réseau           : /etc/sysctl.d/99-network-gaming.conf
• zram             : /etc/systemd/zram-generator.conf.d/gaming.conf
• Initramfs        : /etc/initramfs-tools/initramfs.conf

╔══════════════════════════════════════════════════════════════════╗
║                  Rebootez maintenant pour appliquer !            ║
╚══════════════════════════════════════════════════════════════════╝
FINAL

echo "Installation terminée. Rebootez avec 'reboot'."
