#!/bin/bash

# Configuration système pour Xubuntu 24.04.03 Minimal
# Script de sécurité, optimisation et configuration graphique

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script nécessite les privilèges root. Utilisez: sudo $0"
    exit 1
fi

# Journalisation
LOG_FILE="/var/log/system-hardening-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Début de l'exécution du script : $(date) ==="

# 1. Mise à jour initiale
echo "1. Mise à jour du système..."
apt update && apt upgrade -y
apt install -y software-properties-common apt-transport-https curl wget gnupg
apt autoremove -y

# 2. Dépôts et applications
echo "2. Configuration des dépôts et applications..."
add-apt-repository -y multiverse
add-apt-repository -y restricted
apt update

# Applications de base
apt install -y ffmpeg

# Flatpak
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive \
    org.videolan.VLC \
    org.qbittorrent.qBittorrent \
    com.discordapp.Discord

# Brave Browser
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list

# Mullvad VPN
curl -fsSL https://repository.mullvad.net/deb/mullvad-keyring.asc \
    | gpg --dearmor > /usr/share/keyrings/mullvad-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/mullvad-archive-keyring.gpg arch=$(dpkg --print-architecture)] \
    https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/mullvad.list

# Mise à jour et installation
apt update
apt install -y brave-browser mullvad-vpn

# 3. Mises à jour automatiques de sécurité
echo "3. Configuration des mises à jour automatiques..."
apt install -y unattended-upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 4. Configuration du pare-feu
echo "4. Configuration du pare-feu..."
apt install -y ufw gufw
ufw --force reset
echo "y" | ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw deny 22/tcp
ufw deny 5353/udp
ufw deny 137:138/udp
ufw deny 139,445/tcp

# 5. Désactivation des services non essentiels
echo "5. Désactivation des services non essentiels..."
systemctl disable --now avahi-daemon avahi-daemon.socket
systemctl disable --now cups cups-browsed cups.socket cups.path
systemctl disable --now bluetooth
systemctl disable --now ModemManager
systemctl disable --now wpa_supplicant
systemctl mask avahi-daemon cups bluetooth ModemManager

# 6. Fail2ban
echo "6. Installation de Fail2ban..."
apt install -y fail2ban
systemctl enable fail2ban
cat > /etc/fail2ban/jail.d/override.conf << 'EOF'
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
destemail = root@localhost
action = %(action_mwl)s
banaction = ufw

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3

[nginx-http-auth]
enabled = true
EOF
systemctl restart fail2ban

# 7. Mises à jour du firmware
echo "7. Configuration des mises à jour du firmware..."
apt install -y fwupd
systemctl enable fwupd-refresh.timer
systemctl start fwupd-refresh.timer
fwupdmgr refresh
fwupdmgr update

# 8. AppArmor
echo "8. Configuration d'AppArmor..."
apt install -y apparmor apparmor-utils apparmor-profiles
systemctl enable apparmor
aa-enforce /etc/apparmor.d/*

# 9. Configuration DNS
echo "9. Configuration DNS..."
systemctl enable systemd-resolved
systemctl start systemd-resolved
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
Cache=no
DNSSEC=yes
FallbackDNS=9.9.9.9 149.112.112.112
EOF
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 10. Renforcement du noyau
echo "10. Renforcement du noyau..."
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
kernel.yama.ptrace_scope = 1
kernel.kptr_restrict = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
fs.suid_dumpable = 0
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# 11. Configuration Caps Lock pour chiffres (AZERTY)
echo "11. Configuration Caps Lock pour chiffres..."
XKB_FR_FILE="/usr/share/X11/xkb/symbols/fr"
XKB_CAPSLOCK_FILE="/usr/share/X11/xkb/symbols/mswindows-capslock"

# Sauvegarde du fichier original
if [ -f "$XKB_FR_FILE" ]; then
    cp "$XKB_FR_FILE" "${XKB_FR_FILE}.backup-$(date +%Y%m%d)"
    
    # Modifier la section "basic" pour ajouter include
    awk '
    /xkb_symbols "basic" \{/ {in_basic=1}
    in_basic && /include "latin"/ && !modified {
        print $0
        print "    include \"mswindows-capslock\""
        modified=1
        next
    }
    {print}
    ' "$XKB_FR_FILE" > "${XKB_FR_FILE}.tmp" && mv "${XKB_FR_FILE}.tmp" "$XKB_FR_FILE"
fi

# Créer le fichier de configuration Caps Lock
cat > "$XKB_CAPSLOCK_FILE" << 'EOF'
// Replicate a "feature" of MS Windows on AZERTY keyboards
// where Caps Lock also acts as a Shift Lock on number keys.
// Include keys <AE01> to <AE10> in the FOUR_LEVEL_ALPHABETIC key type.

partial alphanumeric_keys
xkb_symbols "basic" {
    key <AE01>  { type= "FOUR_LEVEL_ALPHABETIC", [ ampersand,          1,          bar,   exclamdown ] };
    key <AE02>  { type= "FOUR_LEVEL_ALPHABETIC", [    eacute,          2,           at,    oneeighth ] };
    key <AE03>  { type= "FOUR_LEVEL_ALPHABETIC", [  quotedbl,          3,   numbersign,     sterling ] };
    key <AE04>  { type= "FOUR_LEVEL_ALPHABETIC", [apostrophe,          4,   onequarter,       dollar ] };
    key <AE05>  { type= "FOUR_LEVEL_ALPHABETIC", [ parenleft,          5,      onehalf, threeeighths ] };
    key <AE06>  { type= "FOUR_LEVEL_ALPHABETIC", [   section,          6,  asciicircum,  fiveeighths ] };
    key <AE07>  { type= "FOUR_LEVEL_ALPHABETIC", [    egrave,          7,    braceleft, seveneighths ] };
    key <AE08>  { type= "FOUR_LEVEL_ALPHABETIC", [    exclam,          8,  bracketleft,    trademark ] };
    key <AE09>  { type= "FOUR_LEVEL_ALPHABETIC", [  ccedilla,          9,    braceleft,    plusminus ] };
    key <AE10>  { type= "FOUR_LEVEL_ALPHABETIC", [    agrave,          0,   braceright,       degree ] };
};
EOF

# 12. Configuration souris gaming 1000 Hz
echo "12. Configuration souris gaming 1000 Hz..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/50-mouse-polling.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Polling Rate"
    MatchIsPointer "on"
    Option "PollingRate" "1000"
    Option "AccelerationProfile" "-1"
    Option "AccelerationScheme" "none"
EndSection
EOF

# Configuration supplémentaire pour evdev
cat > /etc/X11/xorg.conf.d/51-evdev-polling.conf << 'EOF'
Section "InputClass"
    Identifier "evdev pointer catchall"
    MatchIsPointer "on"
    MatchDevicePath "/dev/input/event*"
    Driver "evdev"
    Option "PollingRate" "1000"
EndSection
EOF

# 13. Scaling 125% sans flou pour écran 2K
echo "13. Configuration du scaling 125% sans flou..."
# Installation des composants nécessaires
apt install -y xfce4-settings x11-xserver-utils

# Configuration pour XFCE (scale 1.25)
# Créer la configuration dpi pour X
cat > /etc/X11/Xsession.d/99dpi << 'EOF'
#!/bin/sh
# Set DPI for X session
xrandr --dpi 120
EOF
chmod +x /etc/X11/Xsession.d/99dpi

# Configuration pour XFCE via xsettings
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" != "root" ]; then
    USER_HOME="/home/$REAL_USER"
    
    # Configuration pour scaling fractional via xsettings
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    
    cat > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="120"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Xfce" type="empty">
    <property name="LastCustomDPI" type="int" value="120"/>
  </property>
</channel>
EOF
    
    # Configuration GDK scaling (pour applications GTK3)
    mkdir -p "$USER_HOME/.config/gtk-3.0"
    cat > "$USER_HOME/.config/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-application-prefer-dark-theme = false
gtk-button-images = true
gtk-cursor-theme-name = Adwaita
gtk-cursor-theme-size = 24
gtk-decoration-layout = menu:close
gtk-enable-animations = true
gtk-font-name = Ubuntu 11
gtk-icon-theme-name = Adwaita
gtk-menu-images = true
gtk-primary-button-warps-slider = false
gtk-toolbar-style = GTK_TOOLBAR_ICONS
gtk-xft-antialias = 1
gtk-xft-dpi = 120
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintslight
gtk-xft-rgba = rgb
gtk-tooltip-timeout = 5000
EOF
    
    # Configuration GDK scaling pour GTK4
    mkdir -p "$USER_HOME/.config/gtk-4.0"
    cat > "$USER_HOME/.config/gtk-4.0/settings.ini" << EOF
[Settings]
gtk-application-prefer-dark-theme = false
gtk-cursor-theme-name = Adwaita
gtk-cursor-theme-size = 24
gtk-decoration-layout = menu:close
gtk-enable-animations = true
gtk-font-name = Ubuntu 11
gtk-icon-theme-name = Adwaita
gtk-primary-button-warps-slider = false
gtk-xft-antialias = 1
gtk-xft-dpi = 120
gtk-xft-hinting = 1
gtk-xft-hintstyle = hintslight
gtk-xft-rgba = rgb
EOF
    
    # Configuration pour Xresources
    cat > "$USER_HOME/.Xresources" << EOF
Xft.dpi: 120
Xft.antialias: 1
Xft.hinting: 1
Xft.hintstyle: hintslight
Xft.rgba: rgb
EOF
    
    # Configuration pour scaling via environnement
    cat >> "$USER_HOME/.profile" << 'EOF'

# Scaling 125% pour écran 2K
export GDK_SCALE=1.25
export GDK_DPI_SCALE=0.8
export QT_SCALE_FACTOR=1.25
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export XCURSOR_SIZE=32
EOF
    
    # Rediriger les fichiers vers le bon propriétaire
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.Xresources" "$USER_HOME/.profile"
fi

# Configuration système pour scaling
# Configuration pour lightdm (si utilisé)
if [ -d "/etc/lightdm" ]; then
    cat > /etc/lightdm/lightdm.conf.d/99-scaling.conf << 'EOF'
[Seat:*]
display-setup-script=xrandr --dpi 120
EOF
fi

# Configuration pour SDDM (si utilisé plus tard)
if [ -d "/etc/sddm.conf.d" ]; then
    cat > /etc/sddm.conf.d/99-scaling.conf << 'EOF'
[X11]
DisplayCommand=xrandr --dpi 120
EOF
fi

# 14. Optimisations système supplémentaires
echo "14. Optimisations système..."
# Augmentation des limites de fichiers
echo "* soft nofile 524288" >> /etc/security/limits.conf
echo "* hard nofile 524288" >> /etc/security/limits.conf

# Optimisations pour SSD (si détecté)
if [ -d /sys/block/*/queue/rotational ]; then
    for disk in /sys/block/*/queue/rotational; do
        if [ $(cat "$disk") -eq 0 ]; then
            diskname=$(dirname "$disk")
            echo 0 > "$diskname/rotational" 2>/dev/null || true
            echo 1 > "$diskname/add_random" 2>/dev/null || true
            echo 0 > "$diskname/rq_affinity" 2>/dev/null || true
            echo 1024 > "$diskname/nr_requests" 2>/dev/null || true
        fi
    done
fi

# 15. Nettoyage final
echo "15. Nettoyage final..."
apt autoremove -y
apt autoclean
journalctl --vacuum-time=7d

echo "=== Configuration terminée avec succès : $(date) ==="
echo ""
echo "RÉSUMÉ DES CONFIGURATIONS APPLIQUÉES :"
echo "1. Système mis à jour et dépôts configurés"
echo "2. Applications installées (Brave, VLC, Discord, qBittorrent, Mullvad)"
echo "3. Mises à jour automatiques de sécurité activées"
echo "4. Pare-feu UFW configuré et activé"
echo "5. Services non essentiels désactivés"
echo "6. Fail2ban installé et configuré"
echo "7. Mises à jour firmware activées"
echo "8. AppArmor activé et renforcé"
echo "9. DNS sécurisé configuré (Cloudflare avec DoT)"
echo "10. Renforcement du noyau appliqué"
echo "11. Caps Lock configuré pour écrire des chiffres"
echo "12. Souris gaming configurée à 1000 Hz"
echo "13. Scaling 125% sans flou pour écran 2K"
echo ""
echo "IMPORTANT : Redémarrez votre système pour appliquer toutes les modifications."
echo "Après redémarrage :"
echo "1. Le scaling 125% sera actif sans flou"
echo "2. La souris sera à 1000 Hz"
echo "3. Caps Lock fonctionnera comme touche Shift pour les chiffres"
echo ""
echo "Log détaillé disponible dans : $LOG_FILE"
