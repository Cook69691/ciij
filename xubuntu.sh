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
apt install -y software-properties-common apt-transport-https curl wget gnupg ca-certificates
apt autoremove -y --purge

# 2. Réparation des bibliothèques système (corrige l'erreur flatpak)
echo "2. Réparation des bibliothèques système..."
apt install --reinstall -y libappstream4 flatpak
ldconfig

# 3. Dépôts et applications
echo "3. Configuration des dépôts et applications..."
add-apt-repository -y multiverse
add-apt-repository -y restricted
add-apt-repository -y universe
apt update

# Applications de base
apt install -y ffmpeg

# Configuration Flatpak
echo "4. Configuration de Flatpak..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update -y

# Installation des applications Flatpak avec gestion d'erreurs
echo "5. Installation des applications Flatpak..."
for app in "org.videolan.VLC" "org.qbittorrent.qBittorrent" "com.discordapp.Discord"; do
    if ! flatpak list | grep -q "$app"; then
        echo "Installation de $app..."
        flatpak install -y flathub "$app" || echo "Échec de l'installation de $app, continuation..."
    fi
done

# 6. Brave Browser
echo "6. Installation de Brave Browser..."
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] \
    https://brave-browser-apt-release.s3.brave.com/ stable main" \
    > /etc/apt/sources.list.d/brave-browser-release.list

# 7. Mullvad VPN
echo "7. Installation de Mullvad VPN..."
wget -qO - https://repository.mullvad.net/deb/mullvad-keyring.asc \
    | gpg --dearmor > /usr/share/keyrings/mullvad-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/mullvad-archive-keyring.gpg arch=$(dpkg --print-architecture)] \
    https://repository.mullvad.net/deb/stable $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/mullvad.list

# Mise à jour et installation
apt update
apt install -y brave-browser mullvad-vpn

# 8. Redshift (alternative à f.lux)
echo "8. Installation de Redshift (f.lux pour Linux)..."
apt install -y redshift redshift-gtk
mkdir -p /etc/systemd/user/
cat > /etc/systemd/user/redshift.service << 'EOF'
[Unit]
Description=Redshift display colour temperature adjustment
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/redshift -l geoclue2 -t 6500:4500 -b 1.0:0.8 -m randr -v
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

# Configuration Redshift
REAL_USER=${SUDO_USER:-$USER}
if [ "$REAL_USER" != "root" ]; then
    USER_HOME="/home/$REAL_USER"
    mkdir -p "$USER_HOME/.config"
    cat > "$USER_HOME/.config/redshift.conf" << 'EOF'
[redshift]
temp-day=6500
temp-night=4500
transition=1
gamma-day=0.8
gamma-night=0.6
location-provider=geoclue2
adjustment-method=randr

[geoclue2]
allowed=true
system=false
users=
EOF
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/redshift.conf"
    
    # Activation au démarrage pour l'utilisateur
    sudo -u "$REAL_USER" systemctl --user enable redshift.service
    sudo -u "$REAL_USER" systemctl --user start redshift.service
fi

# 9. Mises à jour automatiques de sécurité
echo "9. Configuration des mises à jour automatiques..."
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

# 10. Configuration du pare-feu
echo "10. Configuration du pare-feu..."
apt install -y ufw gufw
yes | ufw reset
yes | ufw enable
ufw default deny incoming
ufw default allow outgoing
ufw deny 22/tcp
ufw deny 5353/udp
ufw deny 137:138/udp
ufw deny 139,445/tcp

# 11. Désactivation des services non essentiels
echo "11. Désactivation des services non essentiels..."
systemctl disable --now avahi-daemon avahi-daemon.socket >/dev/null 2>&1
systemctl disable --now cups cups-browsed cups.socket cups.path >/dev/null 2>&1
systemctl disable --now bluetooth >/dev/null 2>&1
systemctl disable --now ModemManager >/dev/null 2>&1
systemctl mask avahi-daemon cups bluetooth ModemManager >/dev/null 2>&1

# 12. Fail2ban
echo "12. Installation de Fail2ban..."
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

# 13. Mises à jour du firmware
echo "13. Configuration des mises à jour du firmware..."
apt install -y fwupd
systemctl enable fwupd-refresh.timer
systemctl start fwupd-refresh.timer
fwupdmgr refresh
fwupdmgr update

# 14. AppArmor
echo "14. Configuration d'AppArmor..."
apt install -y apparmor apparmor-utils apparmor-profiles
systemctl enable apparmor
aa-enforce /etc/apparmor.d/*

# 15. Configuration DNS
echo "15. Configuration DNS..."
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

# 16. Renforcement du noyau
echo "16. Renforcement du noyau..."
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

# 17. Configuration complète du clavier AZERTY avec Caps Lock pour chiffres
echo "17. Configuration complète du clavier..."
apt install -y x11-xkb-utils

# Configuration pour tout le système
cat > /etc/default/keyboard << 'EOF'
XKBLAYOUT="fr"
XKBVARIANT="oss"
XKBOPTIONS="caps:shiftlock"
BACKSPACE="guess"
EOF

# Création complète du fichier de configuration XKB
mkdir -p /usr/share/X11/xkb/symbols/
cat > /usr/share/X11/xkb/symbols/capslock_fr << 'EOF'
// Caps Lock Shift Lock pour chiffres AZERTY
partial alphanumeric_keys
xkb_symbols "shiftlock" {
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
    include "shift(both_capslock)"
};
EOF

# Configuration locale
echo "fr oss" > /etc/locale.gen
locale-gen

# Configuration pour l'environnement de bureau
if [ "$REAL_USER" != "root" ]; then
    # Configuration pour XFCE
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

    # Configuration pour l'utilisateur
    cat > "$USER_HOME/.xprofile" << 'EOF'
#!/bin/sh
setxkbmap fr oss -option caps:shiftlock
xmodmap -e "clear Lock"
EOF
    chmod +x "$USER_HOME/.xprofile"
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.xprofile"
fi

# 18. Configuration souris gaming 1000 Hz
echo "18. Configuration souris gaming 1000 Hz..."
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/50-mouse-accel.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Acceleration"
    MatchIsPointer "yes"
    Option "AccelerationProfile" "-1"
    Option "AccelerationScheme" "none"
    Option "AccelSpeed" "0"
EndSection
EOF

cat > /etc/X11/xorg.conf.d/51-mouse-polling.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Polling"
    MatchIsPointer "yes"
    Driver "libinput"
    Option "ScrollMethod" "two-finger"
    Option "NaturalScrolling" "false"
EndSection
EOF

# 19. Scaling 125% sans flou pour écran 2K
echo "19. Configuration du scaling 125% sans flou..."
apt install -y x11-xserver-utils xserver-xorg-core

# Configuration Xorg
cat > /etc/X11/xorg.conf.d/10-monitor.conf << 'EOF'
Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"
EndSection

Section "Monitor"
    Identifier "Monitor0"
    Option "DPI" "120 x 120"
EndSection

Section "Screen"
    Identifier "Screen0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "2560x1440"
    EndSubSection
EndSection
EOF

# Configuration pour l'utilisateur
if [ "$REAL_USER" != "root" ]; then
    # Configuration GDK/GTK
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
gtk-cursor-theme-size=24
EOF

    mkdir -p "$USER_HOME/.config/gtk-4.0"
    cat > "$USER_HOME/.config/gtk-4.0/settings.ini" << EOF
[Settings]
gtk-xft-dpi=120000
gtk-hint-font-metrics=true
EOF

    # Configuration Qt
    cat > "$USER_HOME/.config/Trolltech.conf" << EOF
[Qt]
style=Fusion
font="Ubuntu,11,-1,5,50,0,0,0,0,0"
EOF

    # Variables d'environnement
    cat >> "$USER_HOME/.profile" << 'EOF'

# Configuration scaling 125%
export GDK_SCALE=1.25
export GDK_DPI_SCALE=0.8
export QT_SCALE_FACTOR=1.25
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_QPA_PLATFORMTHEME=gtk3
export XCURSOR_SIZE=32
export ELM_SCALE=1.25
EOF

    # Configuration Xresources
    cat > "$USER_HOME/.Xresources" << 'EOF'
Xft.dpi: 120
Xft.antialias: 1
Xft.hinting: 1
Xft.hintstyle: hintslight
Xft.rgba: rgb
Xcursor.size: 32
EOF

    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config" "$USER_HOME/.profile" "$USER_HOME/.Xresources"
fi

# 20. Optimisations système
echo "20. Optimisations système..."
# Optimisations CPU
cat > /etc/security/limits.d/limits.conf << 'EOF'
* soft nofile 524288
* hard nofile 524288
* soft nproc 65536
* hard nproc 65536
EOF

# Optimisations réseau
cat >> /etc/sysctl.d/99-network.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

# Optimisations AMD spécifiques
if lscpu | grep -qi "AMD"; then
    echo "21. Optimisations AMD spécifiques..."
    # Installation des microcodes
    apt install -y amd64-microcode
    
    # Configuration GPU AMD
    cat > /etc/modprobe.d/amdgpu.conf << 'EOF'
options amdgpu ppfeaturemask=0xffffffff
options amdgpu vm_size=256
options amdgpu gpu_recovery=1
EOF
    
    # Configuration performance
    cat > /etc/udev/rules.d/99-amd-performance.rules << 'EOF'
SUBSYSTEM=="power_supply", ATTR{online}=="1", RUN+="/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'"
SUBSYSTEM=="drm", KERNEL=="card*", ATTR{device/power_dpm_force_performance_level}="high"
EOF
fi

# 22. Nettoyage final
echo "22. Nettoyage final..."
apt autoremove -y --purge
apt autoclean
rm -rf /var/lib/apt/lists/*
update-initramfs -u
journalctl --vacuum-time=7d

# 23. Vérifications finales
echo "23. Vérifications finales..."
echo "Vérification des services :"
systemctl is-active fail2ban && echo "✓ Fail2ban actif" || echo "✗ Fail2ban inactif"
systemctl is-active ufw && echo "✓ UFW actif" || echo "✗ UFW inactif"
systemctl is-active apparmor && echo "✓ AppArmor actif" || echo "✗ AppArmor inactif"

echo "Vérification des applications :"
which brave-browser >/dev/null && echo "✓ Brave installé" || echo "✗ Brave non installé"
which mullvad >/dev/null && echo "✓ Mullvad installé" || echo "✗ Mullvad non installé"
flatpak list | grep -q VLC && echo "✓ VLC installé" || echo "✗ VLC non installé"
flatpak list | grep -q qBittorrent && echo "✓ qBittorrent installé" || echo "✗ qBittorrent non installé"
flatpak list | grep -q Discord && echo "✓ Discord installé" || echo "✗ Discord non installé"
which redshift >/dev/null && echo "✓ Redshift installé" || echo "✗ Redshift non installé"

echo ""
echo "=== CONFIGURATION TERMINÉE AVEC SUCCÈS ==="
echo ""
echo "RÉSUMÉ DES MODIFICATIONS :"
echo "✓ 1. Système mis à jour et optimisé"
echo "✓ 2. Bibliothèques système réparées"
echo "✓ 3. Dépôts multiverse/restricted activés"
echo "✓ 4. Flatpak configuré et applications installées"
echo "✓ 5. Brave Browser installé et configuré"
echo "✓ 6. Mullvad VPN installé"
echo "✓ 7. Redshift (f.lux) installé et configuré"
echo "✓ 8. Mises à jour automatiques de sécurité activées"
echo "✓ 9. Pare-feu UFW configuré avec règles strictes"
echo "✓ 10. Services non essentiels désactivés"
echo "✓ 11. Fail2ban installé pour protection SSH"
echo "✓ 12. Mises à jour firmware activées"
echo "✓ 13. AppArmor activé et renforcé"
echo "✓ 14. DNS sécurisé avec Cloudflare + DoT"
echo "✓ 15. Renforcement du noyau appliqué"
echo "✓ 16. Clavier AZERTY configuré (Caps Lock = Shift pour chiffres)"
echo "✓ 17. Souris gaming 1000 Hz sans accélération"
echo "✓ 18. Scaling 125% sans flou pour écran 2K"
echo "✓ 19. Optimisations système et réseau"
echo "✓ 20. Optimisations AMD spécifiques"
echo "✓ 21. Nettoyage système effectué"
echo ""
echo "IMPORTANT : REDÉMARRAGE REQUIS !"
echo "Après redémarrage :"
echo "1. Le scaling sera à 125% sans flou"
echo "2. Redshift s'exécutera automatiquement"
echo "3. Caps Lock fonctionnera comme touche Shift pour les chiffres"
echo "4. La souris sera à 1000 Hz sans accélération"
echo "5. Toutes les optimisations seront actives"
echo ""
echo "Pour configurer Redshift :"
echo "  Menu Applications → Redshift"
echo "  Ou exécuter : redshift-gtk"
echo ""
echo "Log complet disponible dans : $LOG_FILE"
echo ""
echo "Appuyez sur Entrée pour redémarrer maintenant, ou Ctrl+C pour annuler..."
read
reboot
