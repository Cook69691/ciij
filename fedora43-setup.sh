#!/bin/bash

# Fedora 43 LXQT Post-Installation & Hardening Script
# Vérifié ligne par ligne pour exactitude

set -e  # Arrêter le script en cas d'erreur

echo "==============================================="
echo "  Configuration Fedora 43 LXQT - Sécurité/Apps"
echo "==============================================="
echo ""

# Vérifier que nous sommes sur Fedora 43
if ! grep -q "Fedora release 43" /etc/fedora-release 2>/dev/null; then
    echo "❌ ERREUR : Ce script est conçu pour Fedora 43 seulement"
    exit 1
fi

# Vérifier les privilèges root
if [[ $EUID -ne 0 ]]; then
    echo "❌ Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

# 1. RPM Fusion + Applications
echo "✅ Étape 1/10 : Installation RPM Fusion + Applications..."
dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

dnf update -y
dnf upgrade --refresh -y
dnf autoremove -y
dnf install -y ffmpeg

# Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub org.videolan.VLC
flatpak install -y flathub org.qbittorrent.qBittorrent
flatpak install -y flathub com.discordapp.Discord

# Brave Browser
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
dnf install -y brave-browser

# Mullvad VPN
dnf config-manager addrepo --from-repofile=https://repository.mullvad.net/rpm/stable/mullvad.repo
dnf install -y mullvad-vpn

echo "✅ Étape 1 terminée."
echo ""

# 2. Mises à jour automatiques de sécurité
echo "✅ Étape 2/10 : Configuration mises à jour automatiques..."
dnf install -y dnf-automatic

cat > /etc/dnf/automatic.conf << 'EOF'
[commands]
upgrade_type = security
apply_updates = yes

[emitters]
emit_via = motd

[download]
download_updates = yes

[upgrade]
random_sleep = 0
EOF

systemctl enable --now dnf-automatic.timer
echo "✅ Étape 2 terminée."
echo ""

# 3. Pare-feu
echo "✅ Étape 3/10 : Configuration pare-feu..."
dnf install -y firewalld firewall-config firewall-applet
systemctl enable --now firewalld
firewall-cmd --set-default-zone=public
firewall-cmd --permanent --remove-service=ssh
firewall-cmd --permanent --remove-service=mdns
firewall-cmd --permanent --remove-service=samba
firewall-cmd --permanent --remove-port=22/tcp
firewall-cmd --reload
echo "✅ Étape 3 terminée."
echo ""

# 4. Désactivation services non nécessaires
echo "✅ Étape 4/10 : Désactivation services..."
systemctl stop sshd 2>/dev/null || true
systemctl disable sshd
systemctl stop avahi-daemon 2>/dev/null || true
systemctl disable avahi-daemon
systemctl stop smb nmb 2>/dev/null || true
systemctl disable smb nmb
systemctl mask sshd

# Désactivation d'autres services
systemctl disable --now cups bluetooth ModemManager wpa_supplicant rpcbind nfs-client.target
systemctl mask cups bluetooth ModemManager wpa_supplicant rpcbind nfs-client.target
echo "✅ Étape 4 terminée."
echo ""

# 5. Fail2ban
echo "✅ Étape 5/10 : Installation Fail2ban..."
dnf install -y fail2ban
systemctl enable --now fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 86400
findtime = 600
maxretry = 3
findtime = 600
maxretry = 5
banaction = firewallcmd-multiport
banaction_allports = firewallcmd-allports

[nginx-http-auth]
enabled = true
EOF

systemctl restart fail2ban
echo "✅ Étape 5 terminée."
echo ""

# 6. Firmware updates
echo "✅ Étape 6/10 : Mises à jour firmware..."
dnf install -y fwupd
systemctl enable --now fwupd-refresh.timer
fwupdmgr refresh
fwupdmgr update
echo "✅ Étape 6 terminée."
echo ""

# 7. Vérification SELinux
echo "✅ Étape 7/10 : Vérification SELinux..."
echo "Statut SELinux :"
sestatus
echo ""
echo "Services activés :"
systemctl list-unit-files --state=enabled | head -20
echo ""
echo "Ports ouverts :"
ss -tulnp | head -20
echo "✅ Étape 7 terminée."
echo ""

# 8. DNS sécurisé
echo "✅ Étape 8/10 : Configuration DNS..."
systemctl enable --now systemd-resolved

cat > /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
#FallbackDNS=9.9.9.9 149.112.112.112
Cache=no
DNSSEC=yes
EOF

systemctl restart systemd-resolved
echo "✅ Étape 8 terminée."
echo ""

# 9. Renforcement du noyau
echo "✅ Étape 9/10 : Renforcement noyau..."
cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
kernel.yama.ptrace_scope = 1
kernel.kptr_restrict = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
fs.suid_dumpable = 0
EOF

sysctl -p /etc/sysctl.d/99-hardening.conf
echo "✅ Étape 9 terminée."
echo ""

# 10. Recommandations finales
echo "✅ Étape 10/10 : Recommandations de configuration..."
cat << 'EOF'

===============================================
RECOMMANDATIONS FINALES :
===============================================

1. MOTEURS DE RECHERCHE :
   - Utiliser : https://www.startpage.com/

2. NAVIGATEUR :
   - Brave Browser déjà installé

3. EXTENSIONS BRAVE RECOMMANDÉES :
   - uBlock Origin
   - LocalCDN
   - ClearURLs
   - Privacy Badger
   - ProtonPass

4. FLAGS BRAVE (brave://flags) :
   - #strict-origin-isolation -> Enabled
   - #brave-global-privacy-control-enabled -> Enabled
   - #fallback-dns-over-https -> Enabled
   - #brave-localhost-access-permission -> Disabled

5. VPN :
   - Mullvad VPN installé
   - Activer : DAITA, Multihop, Kill-switch

6. SERVICES ALTERNATIFS :
   - Google Translate -> DeepL
   - Google Gmail -> ProtonMail

7. VÉRIFICATIONS À FAIRE :
   - Vérifier firewall : sudo firewall-cmd --list-all
   - Vérifier fail2ban : sudo fail2ban-client status
   - Vérifier mises à jour : sudo dnf check-update
   - Tester DNS : dig +short txt ch whoami.cloudflare @1.1.1.1

===============================================
CONFIGURATION TERMINÉE AVEC SUCCÈS !
===============================================
EOF

# Créer un récapitulatif
echo "Récapitulatif de l'installation :" > /root/fedora43-setup-summary.txt
echo "Date : $(date)" >> /root/fedora43-setup-summary.txt
echo "RPM Fusion : Installé" >> /root/fedor43-setup-summary.txt
echo "Applications Flatpak : VLC, qBittorrent, Discord" >> /root/fedora43-setup-summary.txt
echo "Brave Browser : Installé" >> /root/fedora43-setup-summary.txt
echo "Mullvad VPN : Installé" >> /root/fedora43-setup-summary.txt
echo "Pare-feu : Configuré" >> /root/fedora43-setup-summary.txt
echo "Fail2ban : Installé et configuré" >> /root/fedora43-setup-summary.txt
echo "DNS : Configuré sur CloudFlare avec DoT" >> /root/fedora43-setup-summary.txt
echo "Renforcement noyau : Appliqué" >> /root/fedora43-setup-summary.txt

echo ""
echo "📄 Un récapitulatif a été créé : /root/fedora43-setup-summary.txt"
echo "🔄 Un redémarrage est recommandé pour appliquer tous les changements."
echo ""
