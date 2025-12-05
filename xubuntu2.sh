#!/bin/bash

# Configuration système pour Xubuntu 24.04.03 Minimal
# Script de sécurité et optimisation

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script nécessite les privilèges root. Utilisez: sudo $0"
    exit 1
fi

# Journalisation
exec > >(tee /var/log/system-hardening-$(date +%Y%m%d-%H%M%S).log) 2>&1

# 1. Mise à jour initiale
apt update && apt upgrade -y
apt install -y software-properties-common apt-transport-https curl wget gnupg
apt autoremove -y

# 2. Dépôts et applications
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
apt install -y ufw gufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw deny 22/tcp
ufw deny 5353/udp
ufw deny 137:138/udp
ufw deny 139,445/tcp
ufw --force enable

# 5. Désactivation des services non essentiels
systemctl disable --now avahi-daemon avahi-daemon.socket
systemctl disable --now cups cups-browsed cups.socket cups.path
systemctl disable --now bluetooth
systemctl disable --now ModemManager
systemctl disable --now wpa_supplicant
systemctl mask avahi-daemon cups bluetooth ModemManager

# 6. Fail2ban
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
apt install -y fwupd
systemctl enable fwupd-refresh.timer
systemctl start fwupd-refresh.timer
fwupdmgr refresh
fwupdmgr update

# 8. AppArmor (alternative à SELinux)
apt install -y apparmor apparmor-utils apparmor-profiles
systemctl enable apparmor
aa-enforce /etc/apparmor.d/*

# 9. Configuration DNS
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
# Créer la configuration X11 pour le taux de poll
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/50-mouse-polling.conf << 'EOF'
Section "InputClass"
    Identifier "Mouse Polling Rate"
    MatchIsPointer "on"
    Option "PollingRate" "1000"
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

# 13. Optimisations système supplémentaires
# Désactivation de swap si non utilisé (commenté par défaut)
# swapoff -a
# sed -i '/swap/d' /etc/fstab

# Augmentation des limites de fichiers
echo "* soft nofile 524288" >> /etc/security/limits.conf
echo "* hard nofile 524288" >> /etc/security/limits.conf

# Optimisations pour SSD (si détecté)
if [ -d /sys/block/*/queue/rotational ]; then
    for disk in /sys/block/*/queue/rotational; do
        if [ $(cat $disk) -eq 0 ]; then
            diskname=$(dirname $disk)
            echo 0 > "$diskname/rotational"
            echo 1 > "$diskname/add_random"
            echo 0 > "$diskname/rq_affinity"
            echo 1024 > "$diskname/nr_requests"
        fi
    done
fi

# 14. Nettoyage final
apt autoremove -y
apt autoclean
journalctl --vacuum-time=7d

echo "=== Configuration terminée avec succès ==="
echo "Redémarrage recommandé pour appliquer toutes les modifications."
echo "Log détaillé disponible dans /var/log/system-hardening-*.log"
