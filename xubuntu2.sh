#!/bin/bash

# Configuration système pour Xubuntu 24.04.03 Minimal - Version Finale Corrigée
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

# Correction des bibliothèques système
echo "2. Correction des bibliothèques système..."
# Vérifier et installer les paquets nécessaires pour Ubuntu 24.04
if ! dpkg -l | grep -q "libappstream5"; then
    apt-get install -y libappstream5
fi

if ! dpkg -l | grep -q "libappstream-glib8"; then
    apt-get install -y libappstream-glib8
fi

# Réinstaller flatpak si nécessaire
if dpkg -l | grep -q "flatpak"; then
    apt-get install --reinstall -y flatpak
else
    apt-get install -y flatpak
fi

ldconfig

# 3. Dépôts et applications
echo "3. Configuration des dépôts et applications..."
add-apt-repository -y multiverse
add-apt-repository -y restricted
add-apt-repository -y universe
apt-get update

# Applications de base
DEBIAN_FRONTEND=noninteractive apt-get install -y ffmpeg

# 4. Configuration Flatpak
echo "4. Configuration de Flatpak..."
if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# 5. Installation des applications via APT (évite les problèmes Flatpak)
echo "5. Installation des applications via APT..."
DEBIAN_FRONTEND=noninteractive apt-get install -y vlc qbittorrent

# Discord via .deb officiel
echo "6. Installation de Discord..."
if ! command -v discord &> /dev/null; then
    wget -O /tmp/discord.deb "https://discord.com/api/download?platform=linux&format=deb"
    dpkg -i /tmp/discord.deb 2>/dev/null || apt-get install -f -y
    rm -f /tmp/discord.deb
fi

# 6. Brave Browser
echo "7. Installation de Brave Browser..."
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y brave-browser

# 7. Mullvad VPN
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

# 10. Configuration du pare-feu
echo "11. Configuration du pare-feu..."
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow out 53 comment 'DNS'
ufw allow out 80 comment 'HTTP'
ufw allow out 443 comment 'HTTPS'
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

# 14. AppArmor - Configuration permissive pour compatibilité
echo "15. Configuration d'AppArmor..."
DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor apparmor-utils
systemctl enable apparmor

# Mettre AppArmor en mode complain pour éviter les blocages
aa-complain /etc/apparmor.d/* 2>/dev/null || true

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

# 16. Configuration du noyau
echo "17. Configuration du noyau..."
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

# Kernel security
kernel.yama.ptrace_scope = 0
kernel.kptr_restrict = 1
fs.suid_dumpable = 0

# IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
EOF
sysctl -p /etc/sysctl.d/99-hardening.conf

# 17. Configuration clavier AZERTY avec Caps Lock pour chiffres
echo "18. Configuration du clavier AZERTY avec Caps Lock pour chiffres..."
DEBIAN_FRONTEND=noninteractive apt-get install -y x11-xkb-utils

# Configuration système
cat > /etc/default/keyboard << 'EOF'
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS="caps:shiftlock"
BACKSPACE="guess"
EOF

# 18. Configuration souris
echo "19. Configuration de la souris..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/50-mouse.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Defaults"
    MatchIsPointer "yes"
    Driver "libinput"
    Option "AccelProfile" "flat"
    Option "AccelSpeed" "0"
EndSection
EOF

# 19. SCALING 125% - SOLUTION SIMPLIFIÉE ET FONCTIONNELLE
echo "20. Configuration du scaling 125% pour écran 2K..."

if [ -n "$SESSION_USER" ] && [ "$SESSION_USER" != "root" ]; then
    USER_HOME="/home/$SESSION_USER"
    
    # 1. Installation des outils nécessaires
    DEBIAN_FRONTEND=noninteractive apt-get install -y xrandr arandr
    
    # 2. Script de configuration automatique
    mkdir -p "$USER_HOME/.config/autostart"
    cat > "$USER_HOME/.config/autostart/scaling.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Display Scaling
Exec=/bin/bash -c 'sleep 5 && xrandr --output $(xrandr | grep " connected" | head -1 | cut -d" " -f1) --scale 1.25x1.25 && xrandr --dpi 120'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
    
    # 3. Configuration XFCE4
    mkdir -p "$USER_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
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
</channel>
EOF
    
    # 4. Variables d'environnement
    cat >> "$USER_HOME/.profile" << 'EOF'

# Configuration scaling 125%
export GDK_SCALE=1.25
export GDK_DPI_SCALE=0.8
export QT_SCALE_FACTOR=1.25
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export XCURSOR_SIZE=32
EOF
    
    # 5. Script manuel de secours
    mkdir -p "$USER_HOME/bin"
    cat > "$USER_HOME/bin/fix-scaling.sh" << 'EOF'
#!/bin/bash
# Script pour forcer le scaling 125%
export GDK_SCALE=1.25
export GDK_DPI_SCALE=0.8
export QT_SCALE_FACTOR=1.25
DISPLAY=$(xrandr | grep " connected" | head -1 | cut -d" " -f1)
if [ -n "$DISPLAY" ]; then
    xrandr --output "$DISPLAY" --scale 1.25x1.25
    xrandr --dpi 120
    echo "Scaling 125% appliqué sur $DISPLAY"
fi
EOF
    
    chmod +x "$USER_HOME/bin/fix-scaling.sh"
    chown -R "$SESSION_USER:$SESSION_USER" "$USER_HOME/.config" "$USER_HOME/.profile" "$USER_HOME/bin"
fi

# 20. Optimisations système
echo "21. Optimisations système..."
# Augmentation des limites de fichiers
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 524288
* hard nofile 524288
EOF

# 21. Nettoyage final
echo "22. Nettoyage final..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge
DEBIAN_FRONTEND=noninteractive apt-get autoclean
rm -rf /var/lib/apt/lists/*
journalctl --vacuum-time=7d

# 22. Message final
echo "=== CONFIGURATION TERMINÉE AVEC SUCCÈS ==="
echo ""
echo "RÉSUMÉ :"
echo "✓ 1. Système mis à jour et bibliothèques corrigées"
echo "✓ 2. Applications installées : VLC, qBittorrent, Discord, Brave, Mullvad VPN"
echo "✓ 3. Redshift (f.lux) installé et configuré"
echo "✓ 4. Mises à jour automatiques de sécurité"
echo "✓ 5. Pare-feu UFW configuré"
echo "✓ 6. Services non essentiels désactivés"
echo "✓ 7. Fail2ban pour protection SSH"
echo "✓ 8. AppArmor en mode compatibilité"
echo "✓ 9. DNS sécurisé Cloudflare + DoT"
echo "✓ 10. Configuration du noyau"
echo "✓ 11. Clavier AZERTY : Caps Lock = Shift pour chiffres"
echo "✓ 12. Souris sans accélération"
echo "✓ 13. SCALING 125% pour écran 2K"
echo ""
echo "IMPORTANT :"
echo "1. Redémarrez pour appliquer toutes les modifications"
echo "2. Après redémarrage, le scaling 125% sera automatique"
echo "3. Si le scaling ne s'applique pas, exécutez: ~/bin/fix-scaling.sh"
echo "4. Redshift démarrera automatiquement (icône dans la barre système)"
echo ""
echo "Log complet : $LOG_FILE"
echo ""
read -p "Appuyez sur Entrée pour redémarrer maintenant, ou Ctrl+C pour annuler..."
reboot
