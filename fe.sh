#!/bin/bash

# Script de sécurisation et configuration pour Fedora 43
# Exécuter avec : sudo bash fedora_hardening.sh

set -e  # Arrêt en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo_error "Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

echo_info "=== Début de la configuration de sécurité Fedora 43 ==="

# ========================================
# 1. MISES À JOUR SYSTÈME
# ========================================
echo_info "Mise à jour du système..."
dnf update --refresh -y
fwupdmgr get-devices
fwupdmgr update -y || echo_warn "Aucune mise à jour firmware disponible"
dnf install -y dnf-automatic
systemctl enable --now dnf-automatic.timer

# ========================================
# 2. PILOTES AMD GPU
# ========================================
echo_info "Installation des pilotes AMD GPU..."
dnf install -y mesa-va-drivers libva libva-utils mesa-vulkan-drivers vulkan-tools

# ========================================
# 3. PARE-FEU
# ========================================
echo_info "Configuration du pare-feu..."
systemctl enable --now firewalld
firewall-cmd --set-default-zone=public
firewall-cmd --reload
systemctl disable --now dnf-makecache.timer

# ========================================
# 4. SÉCURISATION IPv6
# ========================================
echo_info "Configuration de la sécurisation IPv6..."
cat > /etc/sysctl.d/99-ipv6-hardening.conf << 'EOF'
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.all.disable_ipv6=0
EOF

# ========================================
# 5. DNS OVER TLS (Cloudflare)
# ========================================
echo_info "Configuration DNS over TLS..."
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/99-dns-over-tls.conf << 'EOF'
[Resolve]
DNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com
DNSOverTLS=yes
Domains=~.
EOF

systemctl enable --now systemd-resolved
systemctl disable --now NetworkManager-wait-online.service

# ========================================
# 6. DURCISSEMENT KERNEL
# ========================================
echo_info "Durcissement du kernel..."
grubby --update-kernel=ALL --args="module.sig_enforce=1"

# Configuration sysctl principale
cat > /etc/sysctl.d/99-sysctl.conf << 'EOF'
# Protection des fichiers système
fs.suid_dumpable=0
fs.protected_fifos=2
fs.protected_regular=2

# Restrictions kernel (VALEURS CORRIGÉES)
kernel.dmesg_restrict=1
dev.tty.ldisc_autoload=0
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=1
kernel.unprivileged_bpf_disabled=1
kernel.sysrq=0
kernel.perf_event_paranoid=2
kernel.core_pattern=|/bin/false
vm.unprivileged_userfaultfd=0
kernel.kexec_load_disabled=1
kernel.printk=4 4 1 7

# Sécurité réseau IPv4 (VALEURS CORRIGÉES)
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_synack_retries=5
net.core.bpf_jit_harden=1
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_rfc1337=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.ip_forward=0
net.ipv4.conf.all.forwarding=0
net.ipv4.conf.all.mc_forwarding=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_fack=1
net.ipv4.icmp_echo_ignore_all=0

# Sécurité réseau IPv6
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2
net.ipv6.conf.all.forwarding=0
net.ipv6.conf.all.mc_forwarding=0
net.ipv6.conf.all.accept_redirects=0
EOF

# Application des paramètres sysctl
sysctl -p /etc/sysctl.d/99-sysctl.conf
sysctl -p /etc/sysctl.d/99-ipv6-hardening.conf

# ========================================
# 7. BLACKLIST DES MODULES RÉSEAU
# ========================================
echo_info "Blacklist des modules réseau non utilisés..."
cat > /etc/modprobe.d/custom-blacklist.conf << 'EOF'
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
install n-hdlc /bin/false
install ax25 /bin/false
install netrom /bin/false
install x25 /bin/false
install rose /bin/false
install decnet /bin/false
install econet /bin/false
install af_802154 /bin/false
install ipx /bin/false
install appletalk /bin/false
install can /bin/false
install atm /bin/false
EOF

# ========================================
# 8. SÉCURISATION SYSTÈME
# ========================================
echo_info "Configuration des paramètres système de sécurité..."

# Vérification et création du fichier logind.conf si nécessaire
if [ ! -f /etc/systemd/logind.conf ]; then
    echo_info "Création du fichier logind.conf..."
    sudo touch /etc/systemd/logind.conf
fi

# Configuration de la gestion de session
sudo sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=lock/' /etc/systemd/logind.conf
sudo sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' /etc/systemd/logind.conf

# Si les lignes n'existent pas, les ajouter
if ! grep -q "^HandleLidSwitch=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitch=lock" | sudo tee -a /etc/systemd/logind.conf
fi

if ! grep -q "^HandleLidSwitchExternalPower=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitchExternalPower=lock" | sudo tee -a /etc/systemd/logind.conf
fi

# ========================================
# 9. DÉSACTIVATION DES SERVICES NON NÉCESSAIRES
# ========================================
echo_info "Désactivation des services non nécessaires..."
SERVICES_TO_DISABLE=(
    "pcscd.socket"
    "pcscd.service"
    "cups"
    "bluetooth.service"
    "avahi-daemon.service"
    "nis-domainname.service"
    "sssd.service"
    "sssd-kcm.service"
    "rpcbind.service"
    "gssproxy.service"
    "nfs-client.target"
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable --now "$service" 2>/dev/null || echo_warn "Service $service non trouvé"
done

SERVICES_TO_MASK=(
    "cups"
    "avahi-daemon.service"
    "bluetooth.service"
    "nis-domainname.service"
    "sssd.service"
    "sssd-kcm.service"
    "rpcbind.service"
    "gssproxy.service"
    "nfs-client.target"
    "rpc-gssd.service"
    "rpc-statd.service"
    "rpc-statd-notify.service"
    "nfsdcld.service"
    "nfs-mountd.service"
    "nfs-idmapd.service"
)

for service in "${SERVICES_TO_MASK[@]}"; do
    systemctl mask "$service" 2>/dev/null || echo_warn "Service $service non trouvé"
done

systemctl daemon-reload

# ========================================
# 10. SÉCURISATION CRON
# ========================================
echo_info "Sécurisation des répertoires cron..."
chmod 700 /etc/crontab 2>/dev/null || true
chmod 700 /etc/cron.monthly 2>/dev/null || true
chmod 700 /etc/cron.weekly 2>/dev/null || true
chmod 700 /etc/cron.daily 2>/dev/null || true
chmod 700 /etc/cron.hourly 2>/dev/null || true
chmod 700 /etc/cron.d 2>/dev/null || true

# ========================================
# 11. INSTALLATION FLATPAK ET APPLICATIONS
# ========================================
echo_info "Configuration Flatpak et installation des applications..."

# Ajout du dépôt Flathub
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Installation de Mullvad VPN
echo_info "Installation de Mullvad VPN..."
flatpak install -y flathub net.mullvad.MullvadVPN
flatpak override --user --filesystem=xdg-run/NetworkManager net.mullvad.MullvadVPN

# Installation de Brave Browser
echo_info "Installation de Brave Browser..."
flatpak install -y flathub com.brave.Browser
xdg-settings set default-web-browser com.brave.Browser.desktop

# Installation de Discord
echo_info "Installation de Discord..."
flatpak install -y flathub com.discordapp.Discord

# Installation de VLC
echo_info "Installation de VLC..."
flatpak install -y flathub org.videolan.VLC

# Installation de qBittorrent
echo_info "Installation de qBittorrent..."
flatpak install -y flathub org.qbittorrent.qBittorrent

# Installation de f.lux (Fluxgui)
echo_info "Installation de f.lux..."
flatpak install -y flathub com.justgetflux.flux

# Installation de Steam
echo_info "Installation de Steam..."
flatpak install -y flathub com.valvesoftware.Steam

# ========================================
# FINALISATION
# ========================================
echo_info "=== Configuration terminée ==="
echo_warn "Un redémarrage est FORTEMENT recommandé pour appliquer tous les changements."
echo_info "Vérification des modules blacklistés avec : modprobe --showconfig | grep blacklist"
echo ""
echo_info "Voulez-vous redémarrer maintenant? (o/n)"
read -r response
if [[ "$response" =~ ^([oO][uU][iI]|[oO])$ ]]; then
    echo_info "Redémarrage dans 5 secondes..."
    sleep 5
    reboot
else
    echo_info "N'oubliez pas de redémarrer manuellement."
fi
