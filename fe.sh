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

# NE PAS redémarrer systemd-resolved pendant l'exécution
systemctl enable systemd-resolved
systemctl disable NetworkManager-wait-online.service
echo_info "systemd-resolved sera activé au prochain redémarrage"

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

# Restrictions kernel
kernel.dmesg_restrict=1
dev.tty.ldisc_autoload=0
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=2
kernel.unprivileged_bpf_disabled=1
kernel.sysrq=0
kernel.perf_event_paranoid=3
kernel.core_pattern=|/bin/false
vm.unprivileged_userfaultfd=0
kernel.kexec_load_disabled=1
kernel.printk=3 3 3 3

# Sécurité réseau IPv4
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=3
net.core.bpf_jit_harden=2
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

# NE PAS appliquer sysctl immédiatement - sera actif après redémarrage
echo_info "Les paramètres sysctl seront appliqués au prochain redémarrage"

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
    touch /etc/systemd/logind.conf
fi

# Configuration de la gestion de session
sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=lock/' /etc/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' /etc/systemd/logind.conf

# Si les lignes n'existent pas, les ajouter
if ! grep -q "^HandleLidSwitch=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitch=lock" | tee -a /etc/systemd/logind.conf
fi

if ! grep -q "^HandleLidSwitchExternalPower=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitchExternalPower=lock" | tee -a /etc/systemd/logind.conf
fi

# NE PAS REDÉMARRER systemd-logind ici (cela tue les sessions actives)
# Les changements seront appliqués au prochain redémarrage système
echo_info "Les paramètres logind seront appliqués au prochain redémarrage"

# ========================================
# 9. DÉSACTIVATION DES SERVICES NON NÉCESSAIRES
# ========================================
echo_info "Désactivation des services non nécessaires..."
SERVICES_TO_DISABLE=(
    "pcscd.socket"
    "pcscd.service"
    "cups"
    "wpa_supplicant.service"
    "ModemManager.service"
    "bluetooth.service"
    "avahi-daemon.service"
    "nis-domainname.service"
    "sssd.service"
    "sssd-kcm.service"
    "rpcbind.service"
    "gssproxy.service"
    "nfs-client.target"
)

# Désactiver SANS arrêter immédiatement (enlever --now)
for service in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable "$service" 2>/dev/null || echo_warn "Service $service non trouvé"
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
    "wpa_supplicant.service"
    "ModemManager.service"
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

# Installation de Brave Browser
echo_info "Installation de Brave Browser..."
flatpak install -y --noninteractive flathub com.brave.Browser
xdg-settings set default-web-browser com.brave.Browser.desktop 2>/dev/null || true

# Installation de Discord
echo_info "Installation de Discord..."
flatpak install -y --noninteractive flathub com.discordapp.Discord

# Installation de VLC
echo_info "Installation de VLC..."
flatpak install -y --noninteractive flathub org.videolan.VLC

# Installation de qBittorrent
echo_info "Installation de qBittorrent..."
flatpak install -y --noninteractive flathub org.qbittorrent.qBittorrent

# Installation de Redshift (alternative à f.lux)
echo_info "Installation de Redshift (filtre lumière bleue)..."
dnf install -y redshift redshift-gtk

# Installation de Steam
echo_info "Installation de Steam..."
flatpak install -y --noninteractive flathub com.valvesoftware.Steam

echo_info "Installation des applications terminée !"

# ========================================
# 12. Keyboard Tweaks FR
# ========================================

# --- Keyboard tweaks for Fedora KDE (safe Fedora-compatible version) ---
print_status "Configuration clavier AZERTY personnalisée (méthode Fedora)"

# Répertoire override XKB pour Fedora (persistance, sans toucher aux fichiers RPM)
XKB_OVERRIDE_DIR="/etc/X11/xkb/symbols"
CUSTOM_FILE="$XKB_OVERRIDE_DIR/mswindows-capslock"

# 1. Créer le dossier si nécessaire
if [ ! -d "$XKB_OVERRIDE_DIR" ]; then
    mkdir -p "$XKB_OVERRIDE_DIR" || { print_error "Impossible de créer $XKB_OVERRIDE_DIR"; exit 1; }
fi

# 2. Installer le layout personnalisé
cat > "$CUSTOM_FILE" <<'EOF'
// Fedora-safe custom AZERTY tweaks (preserve system integrity)
partial alphanumeric_keys
xkb_symbols "basic" {
    key <AE01> { type= "FOUR_LEVEL_ALPHABETIC", [ ampersand, 1, bar, exclamdown ] };
    key <AE02> { type= "FOUR_LEVEL_ALPHABETIC", [ eacute, 2, at, oneeighth ] };
    key <AE03> { type= "FOUR_LEVEL_ALPHABETIC", [ quotedbl, 3, numbersign, sterling ] };
    key <AE04> { type= "FOUR_LEVEL_ALPHABETIC", [ apostrophe, 4, onequarter, dollar ] };
};
EOF

print_success "Fichier XKB personnalisé installé dans $CUSTOM_FILE"

# 3. Appliquer le nouveau layout avec localectl
if localectl set-x11-keymap fr "" "" mswindows-capslock 2>/dev/null; then
    print_success "Layout XKB appliqué via localectl (Fedora KDE)"
else
    print_warn "localectl n'a pas pu appliquer le layout, tentative via fichier xorg.conf.d"
    
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
    Option "XkbVariant" "mswindows-capslock"
EndSection
EOF
    print_success "Configuration alternative installée : /etc/X11/xorg.conf.d/00-keyboard.conf"
fi

print_status "Redémarrage de la session graphique nécessaire"

# ========================================
# 12.1 NETWORK OPTIMISATION
# ========================================

# --- Network tuning optimized for Fedora 43 (BBR + fq_codel + latency tweaks) ---
print_status "Optimisation réseau Fedora 43 (BBR + fq_codel + faible latence)"

# Charger BBR proprement (inutile mais safe)
modprobe tcp_bbr 2>/dev/null || true
echo "tcp_bbr" > /etc/modules-load.d/bbr.conf || true

# Créer le fichier sysctl optimisé Fedora
cat > /etc/sysctl.d/99-fedora-network.conf <<'EOF'
# --- Congestion control + queue discipline ---
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq_codel

# --- TCP performance & latency ---
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1

# --- Buffers optimisés pour latence stable (pas énorme pour éviter le bufferbloat) ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216

# --- Amélioration files d’attente kernel ---
net.core.netdev_max_backlog = 25000
net.core.somaxconn = 1024
EOF

sysctl --system || print_warn "sysctl --system échoué (non critique)"

# --- Optimisation buffers NIC ---
NIC="$(ip route | awk '/default/ {print $5; exit}')"
if [ -n "$NIC" ]; then
    ethtool -G "$NIC" rx 4096 tx 4096 2>/dev/null \
        || print_warn "Impossible de modifier les buffers NIC (non critique)"
fi

print_success "Optimisations réseau Fedora 43 appliquées"

# ========================================
# 12. OPTIMISATIONS MATÉRIELLES AMD
# ========================================
echo_info "=== Optimisations pour AMD Ryzen 7800X3D + RX 6950 XT ==="

# Vérification que le système est bien AMD
if ! lscpu | grep -q "AMD"; then
    echo_warn "Ce script est optimisé pour processeurs AMD uniquement"
    read -p "Continuer quand même ? (o/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        echo_info "Optimisations AMD ignorées"
        exit 0
    fi
fi

# ========================================
# 12.1 OPTIMISATIONS GRUB ET KERNEL
# ========================================
echo_info "Sauvegarde et modification de GRUB..."

# Backup compressé avec horodatage
if [ -f /etc/default/grub ]; then
    cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)
    echo_info "Backup créé: /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)"
fi

# Paramètres kernel optimisés et SÉCURISÉS pour 7800X3D + 6950 XT
KERNEL_PARAMS="amd_pstate=active amd_pstate.shared_mem=1 amdgpu.dc=1 amdgpu.dpm=1 nowatchdog split_lock_detect=off"

# Vérifier si les paramètres sont déjà présents
if ! grep -q 'amd_pstate=active' /etc/default/grub; then
    echo_info "Ajout des paramètres kernel AMD optimisés..."
    
    # Modifier GRUB_CMDLINE_LINUX de manière sécurisée
    sed -i.bak "s/^\(GRUB_CMDLINE_LINUX=\"[^\"]*\)/\1 $KERNEL_PARAMS/" /etc/default/grub
    
    echo_info "Paramètres ajoutés: $KERNEL_PARAMS"
else
    echo_warn "Paramètres AMD déjà présents dans GRUB"
fi

# Réduire le timeout GRUB (optionnel mais pratique)
if ! grep -q '^GRUB_TIMEOUT=2' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
    echo_info "Timeout GRUB réduit à 2 secondes"
fi

# Régénération de la configuration GRUB (Fedora utilise grub2)
echo_info "Régénération de la configuration GRUB..."
if [ -d /sys/firmware/efi ]; then
    # Système UEFI
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
    echo_info "Configuration GRUB UEFI mise à jour"
else
    # Système BIOS Legacy
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo_info "Configuration GRUB BIOS mise à jour"
fi

# ========================================
# 12.2 OPTIMISATIONS SYSCTL
# ========================================
echo_info "Configuration des paramètres système (sysctl)..."

cat > /etc/sysctl.d/99-amd-performance.conf << 'EOF'
# ========================================
# Optimisations pour AMD Ryzen 7800X3D + 32GB RAM 6000MHz
# ========================================

# === Gestion mémoire (32GB RAM) ===
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500

# === Limites système ===
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
fs.inotify.max_queued_events = 32768

# === Performance réseau (2.5 Gbps) ===
net.core.netdev_max_backlog = 5000
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq

# === Optimisations scheduler ===
kernel.sched_autogroup_enabled = 1
kernel.sched_child_runs_first = 0

# === Hugepages (gaming - optionnel) ===
# Décommentez si nécessaire pour certains jeux
# vm.nr_hugepages = 512
# vm.hugetlb_shm_group = 1000

# === Watchdog désactivé (déjà dans kernel params) ===
kernel.nmi_watchdog = 0
EOF

# Application des paramètres sysctl
sysctl --system
echo_info "Paramètres sysctl appliqués"

# ========================================
# 12.3 CONFIGURATION ZRAM (optionnel mais recommandé)
# ========================================
echo_info "Configuration de zram (swap compressé en RAM)..."

# Installation de zram-generator s'il n'est pas présent
if ! rpm -q zram-generator-defaults >/dev/null 2>&1; then
    dnf install -y zram-generator-defaults
fi

# Configuration zram optimisée pour 32GB RAM
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram-size.conf << 'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

systemctl daemon-reload
echo_info "zram configuré (actif au prochain redémarrage)"

# ========================================
# 12.4 OPTIMISATIONS AMD GPU (6950 XT)
# ========================================
echo_info "Configuration des paramètres AMD GPU..."

# Créer le fichier de configuration pour amdgpu
cat > /etc/modprobe.d/amdgpu.conf << 'EOF'
# Optimisations pour RX 6950 XT
options amdgpu dc=1
options amdgpu dpm=1
options amdgpu audio=1
options amdgpu freesync_video=1
EOF

# Vérifier la présence du firmware AMDGPU
if ! rpm -q amdgpu-firmware >/dev/null 2>&1; then
    echo_info "Installation du firmware AMD GPU..."
    dnf install -y amdgpu-firmware
fi

# ========================================
# 12.5 TUNED PROFILE (optionnel)
# ========================================
echo_info "Configuration du profil tuned pour gaming..."

if ! rpm -q tuned >/dev/null 2>&1; then
    dnf install -y tuned
fi

systemctl enable --now tuned

# Profil throughput-performance est optimal pour gaming
tuned-adm profile throughput-performance
echo_info "Profil tuned activé: throughput-performance"

# ========================================
# 12.6 IRQBALANCE (distribution optimale des IRQ)
# ========================================
echo_info "Configuration d'irqbalance..."

if ! rpm -q irqbalance >/dev/null 2>&1; then
    dnf install -y irqbalance
fi

systemctl enable --now irqbalance
echo_info "irqbalance activé pour distribution optimale des interruptions"

# ========================================
# 12.7 CPUPOWER (OPTIONNEL - à utiliser avec précaution)
# ========================================
echo_info "Installation de cpupower (contrôle CPU)..."

if ! rpm -q kernel-tools >/dev/null 2>&1; then
    dnf install -y kernel-tools
fi

# NOTE: Avec amd_pstate=active, le mode performance est déjà optimal
# Ne pas forcer le governor à moins de savoir ce que vous faites
echo_warn "Note: amd_pstate=active gère déjà les performances CPU de manière optimale"
echo_warn "Ne forcez pas le governor 'performance' sauf si nécessaire"

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
