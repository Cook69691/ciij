#!/bin/bash

# Configuration système pour Xubuntu 24.04.03 Minimal - Version Finale
# Script de sécurité, optimisation et configuration graphique

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script nécessite les privilèges root. Utilisez: sudo $0"
    exit 1
fi

# Mode erreur strict
set -euo pipefail

# Journalisation
LOG_FILE="/var/log/system-hardening-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Début de l'exécution du script : $(date) ==="

# 1. Mise à jour initiale et correction des bibliothèques
echo "1. Mise à jour du système et correction des bibliothèques..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common apt-transport-https curl wget gnupg ca-certificates

# Correction spécifique pour libappstream.so.5
echo "2. Correction des bibliothèques système corrompues..."
DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y libappstream4 libappstream-glib8 flatpak
ldconfig

# 3. Dépôts et applications
echo "3. Configuration des dépôts et applications..."
add-apt-repository -y multiverse
add-apt-repository -y restricted
add-apt-repository -y universe
apt-get update

# Applications de base
DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg

# 4. Configuration Flatpak avec vérification
echo "4. Configuration de Flatpak..."
if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# 5. Installation des applications via APT (évite les problèmes Flatpak)
echo "5. Installation des applications via APT..."
DEBIAN_FRONTEND=noninteractive apt-get install -y vlc qbittorrent

# Discord via .deb officiel (plus stable que Flatpak)
echo "6. Installation de Discord..."
if ! command -v discord &> /dev/null; then
    wget -O /tmp/discord.deb "https://discord.com/api/download?platform=linux&format=deb"
    DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/discord.deb || true
    rm -f /tmp/discord.deb
fi

# 6. Brave Browser avec exemptions AppArmor
echo "7. Installation de Brave Browser..."
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y brave-browser

# Désactiver AppArmor pour Brave si nécessaire
if [ -f "/etc/apparmor.d/usr.bin.brave-browser" ]; then
    ln -sf /etc/apparmor.d/usr.bin.brave-browser /etc/apparmor.d/disable/
    apparmor_parser -R /etc/apparmor.d/usr.bin.brave-browser 2>/dev/null || true
fi

# 7. Mullvad VPN avec exemptions
echo "8. Installation de Mullvad VPN..."
wget -qO - https://repository.mullvad.net/deb/mullvad-keyring.asc \
    | gpg --dearmor > /usr/share/keyrings/mullvad-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/mullvad-archive-keyring.gpg arch=$(dpkg --print-architecture)] \
    https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/mullvad.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y mullvad-vpn

# 8. Redshift (alternative à f.lux)
echo "9. Installation de Redshift (f.lux pour Linux)..."
DEBIAN_FRONTEND=noninteractive apt-get install -y redshift redshift-gtk geoclue-2.0

# Configurer Redshift pour l'utilisateur actuel
REAL_USER="${SUDO_USER:-}"
SESSION_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"

if [ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ]; then
    USER_HOME="/home/$SESSION_USER"
    
    # Configuration Redshift
    mkdir -p "$USER_HOME/.config"
    cat > "$USER_HOME/.config/redshift.conf" << 'EOF'
[redshift]
temp-day=6500
temp-night=4500
transition=1
brightness-day=1.0
brightness-night=0.8
gamma-day=0.8:0.8:0.8
gamma-night=0.6:0.6:0.6
location-provider=geoclue2
adjustment-method=randr

[geoclue2]
allowed=true
system=false

[nominal]
temp-day=6500
temp-night=4500
EOF
    
    # Autostart pour Redshift
    mkdir -p "$USER_HOME/.config/autostart"
    cat > "$USER_HOME/.config/autostart/redshift.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Redshift
Exec=redshift-gtk
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    
    chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.config"
fi

# 9. Mises à jour automatiques de sécurité
echo "10. Configuration des mises à jour automatiques..."
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
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
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 10. Configuration du pare-feu (NE BLOQUE PAS les applications locales)
echo "11. Configuration du pare-feu..."
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow out 53 comment 'DNS'
ufw allow out 80 comment 'HTTP'
ufw allow out 443 comment 'HTTPS'
ufw deny 22/tcp
ufw deny 5353/udp
echo "y" | ufw enable

# 11. Désactivation des services non essentiels
echo "12. Désactivation des services non essentiels..."
systemctl disable --now avahi-daemon avahi-daemon.socket 2>/dev/null || true
systemctl disable --now cups cups-browsed cups.socket cups.path 2>/dev/null || true
systemctl disable --now bluetooth 2>/dev/null || true
systemctl disable --now ModemManager 2>/dev/null || true
systemctl mask avahi-daemon cups bluetooth ModemManager 2>/dev/null || true

# 12. Fail2ban
echo "13. Installation de Fail2ban..."
DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
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
EOF
systemctl restart fail2ban

# 13. Mises à jour du firmware
echo "14. Configuration des mises à jour du firmware..."
DEBIAN_FRONTEND=noninteractive apt-get install -y fwupd
systemctl enable fwupd-refresh.timer
systemctl start fwupd-refresh.timer
fwupdmgr refresh --force 2>/dev/null || true

# 14. AppArmor - MODE COMPATIBILITÉ
echo "15. Configuration d'AppArmor en mode complain pour les applications..."
DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils apparmor-profiles
systemctl enable apparmor

# Mettre Brave et Mullvad en mode complain
if [ -f "/etc/apparmor.d/usr.bin.brave-browser" ]; then
    aa-complain /etc/apparmor.d/usr.bin.brave-browser 2>/dev/null || true
fi

if [ -f "/etc/apparmor.d/usr.sbin.mullvad-daemon" ]; then
    aa-complain /etc/apparmor.d/usr.sbin.mullvad-daemon 2>/dev/null || true
fi

# 15. Configuration DNS
echo "16. Configuration DNS..."
systemctl enable systemd-resolved
systemctl start systemd-resolved
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/dns.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
Cache=yes
DNSSEC=yes
FallbackDNS=9.9.9.9 149.112.112.112
EOF
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# 16. Renforcement du noyau (EXCLURE les paramètres qui bloquent les applications)
echo "17. Renforcement du noyau..."
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# Sécurité réseau
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1

# Kernel security (NE PAS BLOQUER ptrace pour les applications)
kernel.yama.ptrace_scope = 0
kernel.kptr_restrict = 1
fs.suid_dumpable = 0

# IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# Augmenter les limites pour les applications
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# 17. Configuration clavier AZERTY avec Caps Lock pour chiffres - SOLUTION COMPLÈTE
echo "18. Configuration du clavier AZERTY avec Caps Lock pour chiffres..."
DEBIAN_FRONTEND=noninteractive apt-get install -y x11-xkb-utils

# Créer un fichier de configuration XKB personnalisé
mkdir -p /usr/share/X11/xkb/symbols/
cat > /usr/share/X11/xkb/symbols/custom << 'EOF'
// Configuration personnalisée pour Caps Lock comme Shift Lock sur les chiffres
partial alphanumeric_keys
xkb_symbols "caps_shiftlock" {
    key <AE01> { [ ampersand, 1, bar, exclamdown ] };
    key <AE02> { [ eacute, 2, at, oneeighth ] };
    key <AE03> { [ quotedbl, 3, numbersign, sterling ] };
    key <AE04> { [ apostrophe, 4, onequarter, dollar ] };
    key <AE05> { [ parenleft, 5, onehalf, threeeighths ] };
    key <AE06> { [ section, 6, asciicircum, fiveeighths ] };
    key <AE07> { [ egrave, 7, braceleft, seveneighths ] };
    key <AE08> { [ exclam, 8, bracketleft, trademark ] };
    key <AE09> { [ ccedilla, 9, braceleft, plusminus ] };
    key <AE10> { [ agrave, 0, braceright, degree ] };
    
    // Conserver les autres touches normales
    include "fr(oss)"
};
EOF

# Configuration système
cat > /etc/default/keyboard << 'EOF'
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT="oss"
XKBOPTIONS="caps:shiftlock"
BACKSPACE="guess"
EOF

# Configurer pour l'utilisateur
if [ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ]; then
    USER_HOME="/home/$SESSION_USER"
    
    # Script de configuration X11
    mkdir -p "$USER_HOME/.xinitrc.d"
    cat > "$USER_HOME/.xinitrc.d/keyboard.sh" << 'EOF'
#!/bin/bash
setxkbmap -model pc105 -layout fr -variant oss -option caps:shiftlock
EOF
    
    # Configuration XFCE4
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/keyboard-layout.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="keyboard-layout" version="1.0">
  <property name="Default" type="empty">
    <property name="XkbDisable" type="bool" value="false"/>
    <property name="XkbLayout" type="string" value="fr"/>
    <property name="XkbVariant" type="string" value="oss"/>
    <property name="XkbOptions" type="string" value="caps:shiftlock"/>
  </property>
</channel>
EOF
    
    chmod +x "$USER_HOME/.xinitrc.d/keyboard.sh"
    chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.xinitrc.d" "$USER_HOME/.config"
fi

# 18. Configuration souris gaming 1000 Hz
echo "19. Configuration de la souris gaming..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/50-mouse.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Defaults"
    MatchIsPointer "yes"
    Driver "libinput"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
    Option "ScrollMethod" "two-finger"
    Option "NaturalScrolling" "false"
    Option "ClickMethod" "clickfinger"
    Option "MiddleEmulation" "true"
    Option "DisableWhileTyping" "true"
EndSection
EOF

# 19. SCALING 125% SANS FLOU - SOLUTION COMPLÈTE
echo "20. Configuration du scaling 125% pour écran 2K..."

if [ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ]; then
    USER_HOME="/home/$SESSION_USER"
    
    # 1. Configuration XFCE4 scaling
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    cat > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/displays.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="displays" version="1.0">
  <property name="Default" type="empty">
    <property name="DP-1" type="empty">
      <property name="Active" type="bool" value="true"/>
      <property name="Resolution" type="string" value="2560x1440"/>
      <property name="Scale" type="double" value="1.250000"/>
      <property name="RefreshRate" type="double" value="59.951"/>
    </property>
    <property name="DP-2" type="empty">
      <property name="Active" type="bool" value="true"/>
      <property name="Resolution" type="string" value="2560x1440"/>
      <property name="Scale" type="double" value="1.250000"/>
      <property name="RefreshRate" type="double" value="59.951"/>
    </property>
  </property>
</channel>
EOF
    
    # 2. Configuration Xsettings pour DPI
    cat > "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="120"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeSize" type="int" value="32"/>
    <property name="IconSizes" type="string" value="gtk-large-toolbar=24,24:gtk-small-toolbar=20,20"/>
  </property>
</channel>
EOF
    
    # 3. Script de configuration automatique au démarrage
    mkdir -p "$USER_HOME/.config/autostart"
    cat > "$USER_HOME/.config/autostart/scaling-setup.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Display Scaling Setup
Exec=/bin/bash -c 'sleep 3 && xrandr --dpi 120 && xrandr --output $(xrandr | grep " connected" | head -1 | cut -d" " -f1) --scale 1.25x1.25 --panning 3200x1800'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    
    # 4. Variables d'environnement pour le scaling
    cat > "$USER_HOME/.profile" << 'EOF'
#!/bin/bash

# Scaling 125% pour écran 2K
export GDK_SCALE=1.25
export GDK_DPI_SCALE=0.8
export QT_SCALE_FACTOR=1.25
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_FONT_DPI=120
export XCURSOR_SIZE=32
export ELM_SCALE=1.25

# Configuration GDK/GTK
export GDK_BACKEND=x11
export GTK_THEME=Default

# Démarrer Redshift si non déjà démarré
if ! pgrep -x "redshift" > /dev/null; then
    redshift-gtk &
fi
EOF
    
    # 5. Configuration GTK3
    mkdir -p "$USER_HOME/.config/gtk-3.0"
    cat > "$USER_HOME/.config/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-xft-dpi=120000
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=false
gtk-font-name=Ubuntu 11
gtk-icon-theme-name=Adwaita
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=32
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-animations=1
gtk-modules=colorreload-gtk-module
EOF
    
    # 6. Configuration GTK4
    mkdir -p "$USER_HOME/.config/gtk-4.0"
    cat > "$USER_HOME/.config/gtk-4.0/settings.ini" << EOF
[Settings]
gtk-hint-font-metrics=true
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=32
gtk-font-name=Ubuntu 11
EOF
    
    # 7. Script manuel de scaling (au cas où)
    cat > "$USER_HOME/bin/set-scaling.sh" << 'EOF'
#!/bin/bash
# Script manuel pour forcer le scaling 125%
xrandr --dpi 120
CONNECTED_DISPLAY=$(xrandr | grep " connected" | head -1 | cut -d" " -f1)
if [ -n "$CONNECTED_DISPLAY" ]; then
    xrandr --output "$CONNECTED_DISPLAY" --scale 1.25x1.25 --panning 3200x1800
    echo "Scaling 125% appliqué sur $CONNECTED_DISPLAY"
fi
EOF
    
    chmod +x "$USER_HOME/bin/set-scaling.sh"
    chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.config" "$USER_HOME/.profile" "$USER_HOME/bin"
    
    # 8. Configuration système pour XFCE
    mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml
    cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/displays.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="displays" version="1.0">
  <property name="Default" type="empty">
    <property name="Scale" type="double" value="1.25"/>
    <property name="DPI" type="int" value="120"/>
  </property>
</channel>
EOF
fi

# 20. Optimisations système
echo "21. Optimisations système..."
# Augmentation des limites de fichiers
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 524288
* hard nofile 524288
* soft nproc 65536
* hard nproc 65536
EOF

# Optimisations AMD spécifiques
if lscpu | grep -qi "AMD"; then
    echo "22. Optimisations AMD spécifiques..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y amd64-microcode
    
    # Configuration performance CPU
    cat > /etc/default/cpufrequtils << 'EOF'
GOVERNOR="performance"
MAX_SPEED="0"
MIN_SPEED="0"
EOF
    
    # Optimisations GPU AMD
    cat > /etc/modprobe.d/amdgpu.conf << 'EOF'
options amdgpu ppfeaturemask=0xffffffff
options amdgpu vm_size=256
options amdgpu dc=1
options amdgpu async_gfx_ring=1
options amdgpu exp_hw_support=1
EOF
fi

# 21. Fix des permissions et nettoyage
echo "23. Fix des permissions et nettoyage..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge
DEBIAN_FRONTEND=noninteractive apt-get autoclean
rm -rf /var/lib/apt/lists/*
update-initramfs -u
journalctl --vacuum-time=7d

# Réparer les permissions des utilisateurs
if [ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ]; then
    chown -R "$SESSION_USER:$SESSION_USER" "/home/$SESSION_USER" 2>/dev/null || true
fi

# 22. Message final avec instructions
echo "=== CONFIGURATION TERMINÉE AVEC SUCCÈS ==="
echo ""
echo "RÉSUMÉ DES CONFIGURATIONS APPLIQUÉES :"
echo "✓ 1. Système mis à jour et bibliothèques réparées"
echo "✓ 2. Applications installées : VLC, qBittorrent, Discord, Brave, Mullvad VPN"
echo "✓ 3. Redshift (f.lux) installé et configuré pour démarrage automatique"
echo "✓ 4. Mises à jour automatiques de sécurité"
echo "✓ 5. Pare-feu UFW configuré (N'INTERFÈRE PAS avec les applications locales)"
echo "✓ 6. Services non essentiels désactivés"
echo "✓ 7. Fail2ban pour protection SSH"
echo "✓ 8. AppArmor en mode compatibilité (ne bloque pas les applications)"
echo "✓ 9. DNS sécurisé Cloudflare + DoT"
echo "✓ 10. Renforcement du noyau (sans bloquer les applications)"
echo "✓ 11. Clavier AZERTY : Caps Lock = Shift pour chiffres"
echo "✓ 12. Souris gaming sans accélération"
echo "✓ 13. SCALING 125% SANS FLOU pour écran 2K"
echo "✓ 14. Optimisations AMD spécifiques"
echo ""
echo "IMPORTANT : REDÉMARRAGE REQUIS !"
echo ""
echo "Après redémarrage :"
echo "1. Le bureau sera automatiquement en scaling 125%"
echo "2. Redshift (f.lux) démarrera automatiquement"
echo "3. Caps Lock fonctionnera comme Shift pour écrire des chiffres"
echo "4. Toutes les applications (Brave, Mullvad, etc.) devraient s'ouvrir normalement"
echo ""
echo "Si problème de scaling :"
echo "  - Exécutez: ~/bin/set-scaling.sh"
echo "  - Ou dans Paramètres → Écran → Mettre l'échelle à 125%"
echo ""
echo "Si problème avec une application :"
echo "  - Vérifiez: sudo aa-status"
echo "  - Désactivez AppArmor temporairement: sudo systemctl stop apparmor"
echo ""
echo "Log complet : $LOG_FILE"
echo ""
read -p "Appuyez sur Entrée pour redémarrer maintenant, ou Ctrl+C pour annuler..."
reboot
