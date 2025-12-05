#!/bin/bash

# Ubuntu Post-Installation & Hardening Script
# Compatible avec Ubuntu, Kubuntu, Xubuntu, Lubuntu, etc.

set -e  # Arrêter le script en cas d'erreur

echo "==============================================="
echo "  Configuration Ubuntu - Sécurité & Applications"
echo "==============================================="
echo ""

# Vérifier que nous sommes sur une distribution basée sur Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "kubuntu" && "$ID" != "xubuntu" && "$ID" != "lubuntu" && "$ID" != "ubuntu-mate" && "$ID" != "ubuntu-budgie" ]]; then
        echo "⚠️  ATTENTION : Ce script est conçu pour Ubuntu et ses variantes"
        echo "Vous utilisez : $ID"
        read -p "Voulez-vous continuer quand même ? (o/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "❌ ERREUR : Impossible de détecter la distribution"
    exit 1
fi

# Vérifier les privilèges root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

# Mise à jour complète du système AVANT tout
echo "🔄 Mise à jour complète du système..."
apt update
apt full-upgrade -y
apt dist-upgrade -y
apt autoremove -y --purge
apt autoclean
apt clean

# 1. Dépôts supplémentaires + Applications
echo "✅ Étape 1/10 : Installation des dépôts + Applications..."

# Ajouter les dépôts universe et multiverse s'ils ne sont pas déjà présents
if ! grep -q "^deb.*universe" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository universe -y
fi

if ! grep -q "^deb.*multiverse" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository multiverse -y
fi

# Mettre à jour après ajout des dépôts
apt update

# Installer les dépendances multimédias
apt install -y ubuntu-restricted-extras libavcodec-extra ffmpeg

# Flatpak
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.videolan.VLC
flatpak install -y flathub org.qbittorrent.qBittorrent
flatpak install -y flathub com.discordapp.Discord

# Brave Browser
apt install -y curl apt-transport-https gnupg
curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" > /etc/apt/sources.list.d/brave-browser-release.list
apt update
apt install -y brave-browser

# Mullvad VPN
curl -fsSL https://repository.mullvad.net/deb/mullvad-keyring.asc | gpg --dearmor -o /usr/share/keyrings/mullvad-archive-keyring.gpg
CODENAME=$(lsb_release -cs)
echo "deb [signed-by=/usr/share/keyrings/mullvad-archive-keyring.gpg arch=amd64] https://repository.mullvad.net/deb/stable $CODENAME main" > /etc/apt/sources.list.d/mullvad.list
apt update
apt install -y mullvad-vpn

echo "✅ Étape 1 terminée."
echo ""

# 2. Mises à jour automatiques de sécurité
echo "✅ Étape 2/10 : Configuration mises à jour automatiques..."
apt install -y unattended-upgrades

# Configurer les mises à jour automatiques
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable unattended-upgrades
systemctl start unattended-upgrades

echo "✅ Étape 2 terminée."
echo ""

# 3. Pare-feu (UFW)
echo "✅ Étape 3/10 : Configuration pare-feu..."
apt install -y ufw

# Activer UFW avec des règles par défaut strictes
ufw --force enable
ufw default deny incoming
ufw default allow outgoing

# Fermer les ports communs non nécessaires
ufw deny 22/tcp   # SSH
ufw deny 23/tcp   # Telnet
ufw deny 69/udp   # TFTP
ufw deny 111/tcp  # RPC
ufw deny 111/udp  # RPC
ufw deny 137/udp  # NetBIOS
ufw deny 138/udp  # NetBIOS
ufw deny 139/tcp  # SMB
ufw deny 445/tcp  # SMB
ufw deny 512/tcp  # Rexec
ufw deny 513/tcp  # Rlogin
ufw deny 514/tcp  # Rshell

ufw reload

echo "✅ Étape 3 terminée."
echo ""

# 4. Désactivation services non nécessaires
echo "✅ Étape 4/10 : Désactivation services..."

# Fonction pour désactiver un service en toute sécurité
disable_service() {
    local service=$1
    if systemctl list-unit-files | grep -q "^$service.service"; then
        systemctl stop $service 2>/dev/null || true
        systemctl disable $service 2>/dev/null || true
        systemctl mask $service 2>/dev/null || true
        echo "  - $service désactivé"
    fi
}

# Liste des services à désactiver (sécurité)
echo "Désactivation des services non essentiels..."

disable_service ssh
disable_service sshd
disable_service avahi-daemon
disable_service avahi-dnsconfd
disable_service smbd
disable_service nmbd
disable_service winbind
disable_service cups
disable_service cups-browsed
disable_service bluetooth
disable_service ModemManager
disable_service wpa_supplicant
disable_service rpcbind
disable_service nfs-common
disable_service nfs-client.target
disable_service nfs-server
disable_service rpcbind.socket
disable_service rsync
disable_service telnet
disable_service rsh
disable_service rexec
disable_service nis
disable_service tftp
disable_service xinetd

# Services spécifiques aux environnements de bureau
disable_service apport  # Rapports d'erreurs
disable_service whoopsie  # Rapports d'erreurs
disable_service kerneloops  # Rapports d'erreurs

echo "✅ Étape 4 terminée."
echo ""

# 5. Fail2ban
echo "✅ Étape 5/10 : Installation Fail2ban..."
apt install -y fail2ban

# Créer la configuration jail.local
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 5
banaction = ufw
ignoreip = 127.0.0.1/8 ::1
backend = auto

[sshd]
enabled = false

[ufw]
enabled = true
filter = ufw
action = ufw
logpath = /var/log/ufw.log

[nginx-http-auth]
enabled = true

[apache-auth]
enabled = false

[recidive]
enabled = true
bantime = 604800
findtime = 86400
maxretry = 3
EOF

systemctl enable fail2ban
systemctl start fail2ban

echo "✅ Étape 5 terminée."
echo ""

# 6. Mises à jour firmware
echo "✅ Étape 6/10 : Mises à jour firmware..."
apt install -y fwupd

# Créer le timer si nécessaire
if [ ! -f /usr/lib/systemd/system/fwupd-refresh.timer ]; then
    cat > /etc/systemd/system/fwupd-refresh.timer << 'EOF'
[Unit]
Description=Refresh fwupd metadata regularly

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF
fi

systemctl daemon-reload
systemctl enable fwupd-refresh.timer
systemctl start fwupd-refresh.timer

fwupdmgr refresh --force
fwupdmgr update

echo "✅ Étape 6 terminée."
echo ""

# 7. Vérification AppArmor
echo "✅ Étape 7/10 : Vérification AppArmor..."
echo "Statut AppArmor :"
if command -v apparmor_status &> /dev/null; then
    apparmor_status
else
    echo "AppArmor non installé, installation..."
    apt install -y apparmor apparmor-utils
    apparmor_status
fi

echo ""
echo "Services activés :"
systemctl list-unit-files --state=enabled | head -15

echo ""
echo "Ports ouverts :"
ss -tuln | head -15

echo "✅ Étape 7 terminée."
echo ""

# 8. DNS sécurisé
echo "✅ Étape 8/10 : Configuration DNS..."

# S'assurer que systemd-resolved est installé
apt install -y systemd-resolved

# Arrêter le service résolu temporairement
systemctl stop systemd-resolved 2>/dev/null || true

# Créer la configuration
mkdir -p /etc/systemd/resolved.conf.d/
cat > /etc/systemd/resolved.conf.d/99-cloudflare.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
FallbackDNS=9.9.9.9 149.112.112.112
Cache=no
DNSSEC=yes
EOF

# Mettre à jour le lien symbolique resolv.conf
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Démarrer et activer le service
systemctl enable systemd-resolved
systemctl start systemd-resolved

# Vérification
echo "Configuration DNS appliquée :"
resolvectl status | grep -A10 "Global"

echo "✅ Étape 8 terminée."
echo ""

# 9. Renforcement du noyau avec désactivation IPv6
echo "✅ Étape 9/10 : Renforcement noyau et désactivation IPv6..."

# Installer les outils système nécessaires
apt install -y procps

# Désactiver IPv6 au niveau du noyau
cat > /etc/sysctl.d/99-disable-ipv6.conf << 'EOF'
# Désactivation complète d'IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.eth0.disable_ipv6 = 1
net.ipv6.conf.wlan0.disable_ipv6 = 1
EOF

# Configuration de sécurité du noyau
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# Protection contre les attaques par débordement
kernel.yama.ptrace_scope = 1
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3

# Protection mémoire
vm.mmap_rnd_bits = 32
vm.mmap_rnd_compat_bits = 16
vm.swappiness = 10

# Protection réseau IPv4
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_sack = 0
net.ipv4.tcp_dsack = 0

# Protection contre les attaques de prédiction d'adresse
kernel.randomize_va_space = 2

# Désactiver les core dumps pour les processus SUID
fs.suid_dumpable = 0

# Limites de fichiers
fs.file-max = 65535
fs.protected_fifos = 2
fs.protected_regular = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF

# Appliquer les configurations sysctl immédiatement
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
sysctl -p /etc/sysctl.d/99-hardening.conf

# Désactiver IPv6 également dans le grub
if [ -f /etc/default/grub ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&ipv6.disable=1 /' /etc/default/grub
    update-grub
fi

echo "✅ Étape 9 terminée."
echo ""

# 10. Optimisations finales et nettoyage
echo "✅ Étape 10/10 : Optimisations finales..."

# Installer quelques outils utiles pour la sécurité
apt install -y \
    htop \
    neofetch \
    curl \
    wget \
    git \
    gnupg \
    software-properties-common \
    net-tools \
    nmap \
    tree \
    mlocate \
    sudo

# Configurer les performances (optimisation des limites)
cat > /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
root soft nofile 65536
root hard nofile 65536
EOF

# Optimiser la configuration de apt
cat > /etc/apt/apt.conf.d/99optimize << 'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::AutoRemove::RecommendsImportant "false";
APT::AutoRemove::SuggestsImportant "false";
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::CompressionTypes::Order:: "gz";
EOF

# Nettoyage final
echo "🧹 Nettoyage final du système..."
apt autoremove -y --purge
apt autoclean
apt clean
flatpak uninstall --unused -y

# Mise à jour de la base de données mlocate
if command -v updatedb &> /dev/null; then
    updatedb
fi

# Vérifications finales
echo ""
echo "🔍 VÉRIFICATION FINALE DES CONFIGURATIONS :"
echo "=========================================="

# Vérifier UFW
UFW_STATUS=$(ufw status | grep -i status)
echo "✅ Pare-feu UFW : $UFW_STATUS"

# Vérifier Fail2ban
if systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2ban : ACTIF"
else
    echo "⚠️  Fail2ban : INACTIF"
fi

# Vérifier DNS
DNS_SERVERS=$(resolvectl status | grep "DNS Servers" || echo "Non disponible")
echo "✅ DNS configurés : $DNS_SERVERS"

# Vérifier IPv6
if ip -6 addr show | grep -q "inet6"; then
    echo "⚠️  IPv6 : TOUJOURS ACTIF (redémarrage nécessaire)"
else
    echo "✅ IPv6 : DÉSACTIVÉ"
fi

# Vérifier mises à jour automatiques
if systemctl is-active --quiet unattended-upgrades; then
    echo "✅ Mises à jour automatiques : ACTIVES"
else
    echo "⚠️  Mises à jour automatiques : INACTIVES"
fi

# Vérifier AppArmor
if aa-status 2>/dev/null | grep -q "profiles are loaded"; then
    echo "✅ AppArmor : ACTIF"
else
    echo "⚠️  AppArmor : INACTIF"
fi

# Afficher les recommandations finales
cat << 'EOF'

===============================================
RECOMMANDATIONS FINALES :
===============================================

1. NAVIGATEUR BRAVE :
   - Activer les flags :
     brave://flags/#strict-origin-isolation → Enabled
     brave://flags/#brave-global-privacy-control-enabled → Enabled
     brave://flags/#fallback-dns-over-https → Enabled
     brave://flags/#brave-localhost-access-permission → Disabled

2. EXTENSIONS ESSENTIELLES :
   - uBlock Origin (filtrage)
   - LocalCDN (protection tracking)
   - ClearURLs (nettoyage URLs)
   - Privacy Badger (vie privée)
   - ProtonPass (mots de passe)

3. VPN MULLVAD :
   - Créer un compte sur mullvad.net
   - Configurer le kill-switch
   - Activer DAITA et Multihop

4. SERVICES ALTERNATIFS :
   - Google Translate → DeepL
   - Google Gmail → ProtonMail
   - Google Drive → Nextcloud/Proton Drive

5. VÉRIFICATIONS MANUELLES :
   - sudo ufw status verbose
   - sudo fail2ban-client status
   - resolvectl status
   - sudo aa-status

6. REDÉMARRAGE NÉCESSAIRE :
   - Pour appliquer : désactivation IPv6
   - Pour appliquer : renforcement noyau
   - Pour appliquer : toutes les règles de sécurité

===============================================
⚠️  RAPPELS IMPORTANTS :
===============================================

1. SSH a été DÉSACTIVÉ
   Pour le réactiver : sudo systemctl unmask ssh && sudo systemctl enable ssh

2. Wi-Fi a été DÉSACTIVÉ (wpa_supplicant)
   Pour le réactiver : sudo systemctl unmask wpa_supplicant && sudo systemctl enable wpa_supplicant

3. IPv6 a été DÉSACTIVÉ au niveau du noyau
   Redémarrage requis pour l'application complète

4. Accès administrateur requis pour certaines modifications
   Utilisez 'sudo' pour les commandes nécessitant des privilèges

===============================================
🎉 CONFIGURATION TERMINÉE AVEC SUCCÈS !
===============================================

Exécutez la commande suivante pour redémarrer :
sudo reboot
EOF

echo ""
echo "🔄 Un redémarrage IMMÉDIAT est REQUIS pour appliquer tous les changements !"
echo ""
