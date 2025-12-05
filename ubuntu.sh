#!/bin/bash
# post-install & hardening + disable SSH + disable WiFi & Bluetooth + firewall locking
# Pour Ubuntu 25.10 — lancer avec un utilisateur sudo
set -euo pipefail

echo "### Mise à jour du système"
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

echo "### Installation de Flatpak / paquets utiles"
sudo apt install -y flatpak gnome-software-plugin-flatpak ubuntu-restricted-extras || true

echo "### Ajout de Flathub"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true

echo "### Installation applications (VLC, qBittorrent, Discord, Brave)"
sudo flatpak install -y flathub org.videolan.VLC \
                             flathub org.qbittorrent.qBittorrent \
                             flathub com.discordapp.Discord \
                             flathub com.brave.Browser || true

echo "### Installation / configuration pare‑feu (UFW)"
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Bloquer explicitement SSH
sudo ufw deny ssh
# (tu peux bloquer d'autres ports si besoin)
sudo ufw --force enable
sudo ufw status verbose

echo "### Désactivation complète du service SSH"
sudo systemctl stop ssh.service 2>/dev/null || true
sudo systemctl disable ssh.service 2>/dev/null || true
sudo systemctl mask ssh.service 2>/dev/null || true
# Au cas où OpenSSH s'appelle sshd
sudo systemctl stop sshd.service 2>/dev/null || true
sudo systemctl disable sshd.service 2>/dev/null || true
sudo systemctl mask sshd.service 2>/dev/null || true

echo "### Désactivation Wi‑Fi & Bluetooth"
# Installer rfkill si pas présent
sudo apt install -y rfkill || true

# Bloquer WiFi et Bluetooth immédiatement
sudo rfkill block wifi
sudo rfkill block bluetooth

# Désactiver les services associés
sudo systemctl stop bluetooth.service 2>/dev/null || true
sudo systemctl disable bluetooth.service 2>/dev/null || true
sudo systemctl mask bluetooth.service 2>/dev/null || true

# Si tu utilises NetworkManager ou wpa_supplicant — stopper / désactiver
sudo systemctl stop NetworkManager.service 2>/dev/null || true
sudo systemctl disable NetworkManager.service 2>/dev/null || true
sudo systemctl mask NetworkManager.service 2>/dev/null || true

echo "### Désactivation de services inutiles (avahi, cups, rpcbind …)"
sudo systemctl disable --now avahi-daemon cups rpcbind 2>/dev/null || true

echo "### Installation et activation Fail2Ban"
sudo apt install -y fail2ban || true
sudo systemctl enable --now fail2ban || true

echo "### Kernel hardening via sysctl"
sudo tee /etc/sysctl.d/99-hardening.conf <<'EOF'
kernel.yama.ptrace_scope = 1
kernel.kptr_restrict = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
fs.suid_dumpable = 0
EOF
sudo sysctl -p /etc/sysctl.d/99-hardening.conf

echo "### Désactivation permanente d'IPv6"
sudo tee /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

echo "### Configuration DNS + DNS over TLS (systemd-resolved)"
sudo apt install -y systemd-resolved || true
sudo systemctl enable --now systemd-resolved

sudo tee /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
Cache=no
EOF

sudo systemctl restart systemd-resolved.service 2>/dev/null || true
sudo systemctl restart systemd-networkd.service 2>/dev/null || true

echo "### Mises à jour automatiques (facultatif)"
sudo apt install -y unattended-upgrades || true
sudo dpkg-reconfigure --priority=low unattended-upgrades || true

echo "### Nettoyage final"
sudo apt autoremove -y
sudo apt autoclean -y

echo "### FIN — redémarrer le système pour appliquer tous les changements."
