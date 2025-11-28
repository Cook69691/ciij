#!/bin/bash

# Script de sécurisation et optimisation complet pour Fedora 43
# Configuration: AMD Ryzen 7800X3D + RX 6950 XT + 32GB RAM 6000MHz + 2.5Gbps
# Exécuter avec : sudo bash fedora_43_complete_optimized.sh

set -e  # Arrêt en cas d'erreur

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Vérification root
if [ "$EUID" -ne 0 ]; then 
    echo_error "Ce script doit être exécuté en tant que root (sudo)"
    exit 1
fi

echo_section "DÉBUT DE LA CONFIGURATION FEDORA 43"
echo_info "Configuration détectée: AMD Ryzen + RX 6950 XT + 32GB RAM"

# ========================================
# 1. MISES À JOUR SYSTÈME
# ========================================
echo_section "1. MISES À JOUR SYSTÈME"
echo_info "Mise à jour complète du système..."
dnf update --refresh -y
fwupdmgr get-devices 2>/dev/null || true
fwupdmgr update -y 2>/dev/null || echo_warn "Aucune mise à jour firmware disponible"
dnf install -y dnf-automatic
systemctl enable --now dnf-automatic.timer
echo_info "✓ Système mis à jour"

# ========================================
# 2. PILOTES AMD GPU
# ========================================
echo_section "2. PILOTES AMD GPU (RX 6950 XT)"
echo_info "Installation des pilotes AMD GPU..."
dnf install -y mesa-va-drivers libva libva-utils mesa-vulkan-drivers vulkan-tools
echo_info "✓ Pilotes AMD GPU installés"

# ========================================
# 3. PARE-FEU
# ========================================
echo_section "3. PARE-FEU"
echo_info "Configuration du pare-feu..."
systemctl enable --now firewalld
firewall-cmd --set-default-zone=public 2>/dev/null || true
firewall-cmd --reload
systemctl disable dnf-makecache.timer 2>/dev/null || true
echo_info "✓ Pare-feu configuré"

# ========================================
# 4. SÉCURISATION IPv6
# ========================================
echo_section "4. SÉCURISATION IPv6"
echo_info "Configuration de la sécurisation IPv6..."
cat > /etc/sysctl.d/99-ipv6-hardening.conf << 'EOF'
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.all.disable_ipv6=0
EOF
echo_info "✓ IPv6 sécurisé"

# ========================================
# 5. DNS OVER TLS (Cloudflare)
# ========================================
echo_section "5. DNS OVER TLS"
echo_info "Configuration DNS over TLS (Cloudflare Malware Blocking)..."
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/99-dns-over-tls.conf << 'EOF'
[Resolve]
DNS=1.1.1.2#security.cloudflare-dns.com 1.0.0.2#security.cloudflare-dns.com 2606:4700:4700::1112#security.cloudflare-dns.com 2606:4700:4700::1002#security.cloudflare-dns.com
DNSOverTLS=yes
Domains=~.
EOF
systemctl enable systemd-resolved
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
echo_info "✓ DNS over TLS configuré (appliqué après redémarrage)"

# ========================================
# 6. DURCISSEMENT KERNEL
# ========================================
echo_section "6. DURCISSEMENT KERNEL"
echo_info "Application des paramètres de sécurité kernel..."
grubby --update-kernel=ALL --args="module.sig_enforce=1" 2>/dev/null || true

cat > /etc/sysctl.d/99-security-hardening.conf << 'EOF'
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

echo_info "✓ Paramètres de sécurité kernel configurés (appliqués après redémarrage)"

# ========================================
# 7. BLACKLIST DES MODULES RÉSEAU
# ========================================
echo_section "7. BLACKLIST MODULES RÉSEAU"
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
echo_info "✓ Modules réseau obsolètes blacklistés"

# ========================================
# 8. SÉCURISATION SYSTÈME
# ========================================
echo_section "8. SÉCURISATION SYSTÈME"
echo_info "Configuration des paramètres système de sécurité..."

if [ ! -f /etc/systemd/logind.conf ]; then
    touch /etc/systemd/logind.conf
fi

sed -i 's/#HandleLidSwitch=.*/HandleLidSwitch=lock/' /etc/systemd/logind.conf
sed -i 's/#HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=lock/' /etc/systemd/logind.conf

if ! grep -q "^HandleLidSwitch=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitch=lock" >> /etc/systemd/logind.conf
fi

if ! grep -q "^HandleLidSwitchExternalPower=" /etc/systemd/logind.conf; then
    echo "HandleLidSwitchExternalPower=lock" >> /etc/systemd/logind.conf
fi

echo_info "✓ Verrouillage automatique configuré"

# ========================================
# 9. DÉSACTIVATION DES SERVICES NON NÉCESSAIRES
# ========================================
echo_section "9. DÉSACTIVATION SERVICES"
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

for service in "${SERVICES_TO_DISABLE[@]}"; do
    systemctl disable "$service" 2>/dev/null || true
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
    systemctl mask "$service" 2>/dev/null || true
done

systemctl daemon-reload
echo_info "✓ Services inutiles désactivés"

# ========================================
# 10. SÉCURISATION CRON
# ========================================
echo_section "10. SÉCURISATION CRON"
echo_info "Sécurisation des répertoires cron..."
chmod 700 /etc/crontab 2>/dev/null || true
chmod 700 /etc/cron.monthly 2>/dev/null || true
chmod 700 /etc/cron.weekly 2>/dev/null || true
chmod 700 /etc/cron.daily 2>/dev/null || true
chmod 700 /etc/cron.hourly 2>/dev/null || true
chmod 700 /etc/cron.d 2>/dev/null || true
echo_info "✓ Répertoires cron sécurisés"

# ========================================
# 11. INSTALLATION FLATPAK ET APPLICATIONS
# ========================================
echo_section "11. INSTALLATION APPLICATIONS"
echo_info "Configuration Flatpak et installation des applications..."

flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# Mullvad VPN via RPM
echo_info "Installation de Mullvad VPN (RPM)..."
MULLVAD_URL="https://mullvad.net/download/app/rpm/latest"
curl -LO "$MULLVAD_URL" 2>/dev/null || echo_warn "Échec téléchargement Mullvad"
if [ -f mullvad-vpn*.rpm ]; then
    dnf install -y ./mullvad-vpn*.rpm
    rm -f ./mullvad-vpn*.rpm
    systemctl enable mullvad-daemon 2>/dev/null || true
    echo_info "✓ Mullvad VPN installé"
else
    echo_warn "Mullvad VPN non installé (téléchargement manuel requis)"
fi

# Brave Browser
echo_info "Installation de Brave Browser..."
flatpak install -y --noninteractive flathub com.brave.Browser
xdg-settings set default-web-browser com.brave.Browser.desktop 2>/dev/null || true
echo_info "✓ Brave Browser installé"

# Discord
echo_info "Installation de Discord..."
flatpak install -y --noninteractive flathub com.discordapp.Discord
echo_info "✓ Discord installé"

# VLC
echo_info "Installation de VLC..."
flatpak install -y --noninteractive flathub org.videolan.VLC
echo_info "✓ VLC installé"

# qBittorrent
echo_info "Installation de qBittorrent..."
flatpak install -y --noninteractive flathub org.qbittorrent.qBittorrent
echo_info "✓ qBittorrent installé"

# Redshift (alternative à f.lux)
echo_info "Installation de Redshift (filtre lumière bleue)..."
dnf install -y redshift redshift-gtk
echo_info "✓ Redshift installé (alternative open-source à f.lux)"

# Steam
echo_info "Installation de Steam..."
flatpak install -y --noninteractive flathub com.valvesoftware.Steam
echo_info "✓ Steam installé"

# ========================================
# 12. OPTIMISATIONS MATÉRIELLES AMD
# ========================================
echo_section "12. OPTIMISATIONS AMD (7800X3D + RX 6950 XT)"

# Vérification architecture AMD
if ! lscpu | grep -q "AMD"; then
    echo_warn "⚠ Processeur non-AMD détecté, certaines optimisations peuvent ne pas s'appliquer"
fi

# 12.1 OPTIMISATIONS GRUB
echo_info "Configuration GRUB pour AMD..."

if [ -f /etc/default/grub ]; then
    cp /etc/default/grub /etc/default/grub.backup.$(date +%Y%m%d-%H%M%S)
fi

KERNEL_PARAMS="amd_pstate=active amd_pstate.shared_mem=1 amdgpu.dc=1 amdgpu.dpm=1 nowatchdog split_lock_detect=off"

if ! grep -q 'amd_pstate=active' /etc/default/grub; then
    sed -i.bak "s/^\(GRUB_CMDLINE_LINUX=\"[^\"]*\)/\1 $KERNEL_PARAMS/" /etc/default/grub
    echo_info "✓ Paramètres kernel AMD ajoutés"
else
    echo_warn "Paramètres AMD déjà présents dans GRUB"
fi

# Réduire timeout GRUB
if ! grep -q '^GRUB_TIMEOUT=2' /etc/default/grub; then
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
fi

# Régénération GRUB
if [ -d /sys/firmware/efi ]; then
    grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null || echo_warn "Erreur régénération GRUB UEFI"
    echo_info "✓ Configuration GRUB UEFI mise à jour"
else
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null || echo_warn "Erreur régénération GRUB BIOS"
    echo_info "✓ Configuration GRUB BIOS mise à jour"
fi

# 12.2 OPTIMISATIONS SYSCTL
echo_info "Configuration des paramètres système avancés..."

cat > /etc/sysctl.d/99-amd-performance.conf << 'EOF'
# ========================================
# Optimisations AMD Ryzen 7800X3D + 32GB RAM 6000MHz + 2.5Gbps
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

# === Watchdog désactivé ===
kernel.nmi_watchdog = 0
EOF

echo_info "✓ Paramètres sysctl performance configurés"

# 12.3 ZRAM CONFIGURATION
echo_info "Configuration zram (swap compressé en RAM)..."

if ! rpm -q zram-generator-defaults >/dev/null 2>&1; then
    dnf install -y zram-generator-defaults
fi

mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/zram-size.conf << 'EOF'
[zram0]
zram-size = min(ram / 2, 16384)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

systemctl daemon-reload
echo_info "✓ zram configuré (16GB max, zstd)"

# 12.4 OPTIMISATIONS AMD GPU
echo_info "Configuration AMD GPU (RX 6950 XT)..."

cat > /etc/modprobe.d/amdgpu.conf << 'EOF'
# Optimisations pour RX 6950 XT
options amdgpu dc=1
options amdgpu dpm=1
options amdgpu audio=1
options amdgpu freesync_video=1
EOF

echo_info "✓ AMD GPU optimisé (DPM, FreeSync activés)"

# 12.5 TUNED PROFILE
echo_info "Configuration du profil tuned pour gaming..."

if ! rpm -q tuned >/dev/null 2>&1; then
    dnf install -y tuned
fi

systemctl enable --now tuned
tuned-adm profile throughput-performance
echo_info "✓ Profil tuned: throughput-performance"

# 12.6 IRQBALANCE
echo_info "Configuration irqbalance..."

if ! rpm -q irqbalance >/dev/null 2>&1; then
    dnf install -y irqbalance
fi

systemctl enable --now irqbalance
echo_info "✓ irqbalance activé"

# 12.7 CPUPOWER
echo_info "Installation cpupower..."

if ! rpm -q kernel-tools >/dev/null 2>&1; then
    dnf install -y kernel-tools
fi

echo_info "✓ cpupower installé (amd_pstate gère déjà les performances CPU)"

# ========================================
# 13. CONFIGURATION CLAVIER AZERTY PERSONNALISÉ (TKL - CapsLock = chiffres)
# ========================================
echo_info "Configuration clavier AZERTY pour TKL (CapsLock active les chiffres)..."

# SOLUTION 1 : Modification XKB personnalisée (recommandée)
if [ -f /usr/share/X11/xkb/symbols/fr ]; then
    
    echo_info "Installation du layout clavier mswindows-capslock..."
    cat > /usr/share/X11/xkb/symbols/mswindows-capslock <<'EOF'
// TKL-compatible AZERTY: CapsLock enables numbers (Windows behavior)
partial alphanumeric_keys
xkb_symbols "basic" {
    // Type FOUR_LEVEL_ALPHABETIC makes CapsLock work on these keys
    key <AE01> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ ampersand, 1, bar, exclamdown ] };
    key <AE02> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ eacute, 2, at, oneeighth ] };
    key <AE03> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ quotedbl, 3, numbersign, sterling ] };
    key <AE04> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ apostrophe, 4, onequarter, dollar ] };
    key <AE05> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ parenleft, 5, braceleft, threequarters ] };
    key <AE06> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ minus, 6, asciicircum, threequarters ] };
    key <AE07> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ egrave, 7, grave, fiveeighths ] };
    key <AE08> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ underscore, 8, backslash, trademark ] };
    key <AE09> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ ccedilla, 9, asciicircum, plusminus ] };
    key <AE10> { type[Group1]= "FOUR_LEVEL_ALPHABETIC", symbols[Group1]= [ agrave, 0, at, degree ] };
};
EOF
    
    # Ajouter l'inclusion dans le fichier fr (si pas déjà présente)
    if ! grep -q 'include "mswindows-capslock"' /usr/share/X11/xkb/symbols/fr; then
        echo_info "Ajout de l'inclusion dans le fichier /usr/share/X11/xkb/symbols/fr..."
        # Trouver la ligne avec include "latin" et ajouter notre include juste après
        sed -i '/include "latin"/a \    include "mswindows-capslock"' /usr/share/X11/xkb/symbols/fr
    else
        echo_info "Le layout mswindows-capslock est déjà inclus"
    fi
    
    # Configuration permanente via localectl (Fedora KDE 43)
    echo_info "Application de la configuration clavier via localectl..."
    if localectl set-x11-keymap fr pc105 "" "" 2>/dev/null; then
        echo_info "✓ Configuration appliquée via localectl"
    else
        echo_warn "localectl a échoué, utilisation de la méthode alternative..."
    fi
    
    # Configuration via xorg.conf.d (méthode de secours)
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "fr"
    Option "XkbModel" "pc105"
EndSection
EOF
    echo_info "✓ Fichier xorg.conf.d créé"
    
    echo_info "✓ Configuration clavier TKL installée"
    echo_info "  → CapsLock activé = chiffres 1234567890"
    echo_info "  → Shift + touche = chiffres 1234567890"
    echo_warn "⚠️  Redémarrage de la session X nécessaire (ou reboot)"
    
else
    echo_error "Fichier /usr/share/X11/xkb/symbols/fr introuvable !"
    echo_warn "Impossible de configurer le clavier AZERTY TKL"
fi

# SOLUTION 2 (Alternative si Solution 1 ne fonctionne pas) : Option XKB caps:shiftlock
echo ""
echo_info "--- Solution alternative disponible ---"
echo_info "Si le layout personnalisé ne fonctionne pas, essayez :"
echo_info "  1. Ouvrez Paramètres système KDE"
echo_info "  2. Clavier → Avancé → Comportement de la touche Verr. Maj."
echo_info "  3. Cochez : 'Verr. Maj. agit comme Maj Verr.' (caps:shiftlock)"
echo_warn "  ⚠️  ATTENTION : Cette option affecte TOUTES les touches (lettres + chiffres)"

# ========================================
# 14. CONFIGURATION SOURIS GAMING (1000 Hz)
# ========================================
echo_info "Configuration du polling rate souris gaming à 1000 Hz..."

# 1. Créer le fichier de configuration udev pour le polling rate
echo_info "Création de la règle udev pour le polling rate..."
cat > /etc/udev/rules.d/99-mouse-polling-rate.conf <<'EOF'
# Set 1000Hz polling rate for gaming mice
ACTION=="add", SUBSYSTEM=="usb", DRIVER=="usbhid", ATTR{bInterval}=="*", ATTR{bInterval}="1"
EOF

# 2. Créer un module de configuration pour usbhid
echo_info "Configuration du module usbhid..."
cat > /etc/modprobe.d/usbhid.conf <<'EOF'
# Force 1000Hz polling rate for USB mice
options usbhid mousepoll=1
EOF

# 3. Recharger les règles udev
echo_info "Rechargement des règles udev..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb

# 4. Vérifier la configuration actuelle
echo_info "Configuration souris appliquée :"
if [ -f /sys/module/usbhid/parameters/mousepoll ]; then
    CURRENT_POLL=$(cat /sys/module/usbhid/parameters/mousepoll)
    echo_info "  → Polling rate actuel : ${CURRENT_POLL} ms"
else
    echo_warn "  → Impossible de lire le polling rate actuel"
fi

echo_info "✓ Configuration 1000 Hz activée"
echo_warn "⚠️  Redémarrage nécessaire pour appliquer le polling rate de manière permanente"
echo_info "   Après redémarrage, vérifiez avec : cat /sys/module/usbhid/parameters/mousepoll"

# ========================================
# FINALISATION
# ========================================
echo_section "CONFIGURATION TERMINÉE"
echo_info ""
echo_info "========================================="
echo_info "✅ RÉSUMÉ DES CONFIGURATIONS APPLIQUÉES"
echo_info "========================================="
echo_info ""
echo_info "🔒 SÉCURITÉ:"
echo_info "  ✓ Système mis à jour"
echo_info "  ✓ Pare-feu configuré"
echo_info "  ✓ DNS over TLS (Cloudflare malware blocking)"
echo_info "  ✓ Kernel durci (sysctl security)"
echo_info "  ✓ Services inutiles désactivés"
echo_info "  ✓ Modules réseau obsolètes blacklistés"
echo_info ""
echo_info "⚡ PERFORMANCES AMD:"
echo_info "  ✓ AMD P-State activé (7800X3D)"
echo_info "  ✓ AMD GPU optimisé (6950 XT - DPM, FreeSync)"
echo_info "  ✓ Sysctl optimisé (32GB RAM + 2.5Gbps)"
echo_info "  ✓ zram configuré (16GB max, zstd)"
echo_info "  ✓ Tuned profile: throughput-performance"
echo_info "  ✓ TCP BBR + FQ activé"
echo_info ""
echo_info "📦 APPLICATIONS INSTALLÉES:"
echo_info "  ✓ Mullvad VPN"
echo_info "  ✓ Brave Browser"
echo_info "  ✓ Discord"
echo_info "  ✓ VLC"
echo_info "  ✓ qBittorrent"
echo_info "  ✓ Redshift (filtre lumière bleue)"
echo_info "  ✓ Steam"
echo_info ""
echo_warn "⚠️  REDÉMARRAGE OBLIGATOIRE pour appliquer:"
echo_warn "   - Paramètres kernel GRUB (AMD P-State)"
echo_warn "   - Optimisations sysctl"
echo_warn "   - Modules GPU"
echo_warn "   - DNS over TLS"
echo_info ""
echo_info "📋 Vérifications post-redémarrage:"
echo_info "   - CPU scaling: cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
echo_info "   - AMD P-State: cat /sys/devices/system/cpu/amd_pstate/status"
echo_info "   - zram: swapon --show"
echo_info "   - Modules blacklistés: modprobe --showconfig | grep blacklist"
echo_info ""

read -p "Voulez-vous redémarrer maintenant? (o/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[OoYy]$ ]]; then
    echo_info "Redémarrage dans 5 secondes..."
    sleep 5
    reboot
else
    echo_info "N'oubliez pas de redémarrer manuellement!"
fi
