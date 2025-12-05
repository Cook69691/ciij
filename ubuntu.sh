#!/bin/bash
# post-install, durcissement + IPv6 off + DNS over TLS pour Ubuntu 25.10
# À lancer avec un utilisateur ayant les droits sudo
set -euo pipefail

echo "### Mise à jour du système"
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
sudo apt autoclean

echo "### Installation de Flatpak / paquets utiles"
sudo apt install -y flatpak gnome-software-plugin-flatpak ubuntu-restricted-extras

echo "### Ajout du dépôt Flathub"
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "### Installation des applications : VLC, qBittorrent, Discord, Brave"
sudo flatpak install -y flathub org.videolan.VLC \
                              flathub org.qbittorrent.qBittorrent \
                              flathub com.discordapp.Discord \
                              flathub com.brave.Browser

echo "### Installation / configuration pare-feu (UFW)"
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
# Si tu utilises SSH légitimement, tu peux autoriser SSH : uncomment next line
# sudo ufw allow ssh
sudo ufw enable

echo "### Désactivation de services peu utilisés"
sudo systemctl disable --now avahi-daemon cups rpcbind || true

echo "### Installation et activation Fail2Ban"
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

echo "### Kernel hardening via sysctl"
sudo tee /etc/sysctl.d/99-hardening.conf <<'EOF'
# Hardening kernel & réseau
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
# Disable IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo sysctl -p /etc/sysctl.d/99-disable-ipv6.conf

echo "### Configuration DNS + DNS over TLS (systemd-resolved)"
sudo apt install -y systemd-resolved
sudo systemctl enable --now systemd-resolved

sudo tee /etc/systemd/resolved.conf <<'EOF'
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=9.9.9.9 149.112.112.112
DNSOverTLS=yes
#DNSSEC=yes    # attention : DNSSEC + DoT peut poser des soucis selon votre resolver
Cache=no
EOF

sudo systemctl restart systemd-resolved.service
# Si tu utilises NetworkManager, il est souhaitable de redémarrer aussi NetworkManager
sudo systemctl restart NetworkManager || true

echo "### Optionnel : activer mises à jour automatiques de sécurité"
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

echo "### Nettoyage final"
sudo apt autoremove -y
sudo apt autoclean -y

echo "### Fin du script. Redémarre le système pour appliquer tous les changements."
