#!/bin/bash

# Proxmox Post-Install Setup Script
# Author: ChatGPT
# Description: Automatically configures Proxmox after fresh install

set -euo pipefail

echo "✅ Starting Proxmox post-install setup..."

### 1. Choose APT Repo
echo
echo "🧾 Choose your Proxmox APT repository:"
echo "1) Enterprise (requires license)"
echo "2) No-Subscription (free/community)"
read -rp "Enter choice [1-2]: " REPO_CHOICE

PVE_VERSION=$(pveversion | cut -d'-' -f2)

case "$REPO_CHOICE" in
  1)
    echo "📦 Enabling Enterprise repository..."
    echo "deb https://enterprise.proxmox.com/debian/pve $PVE_VERSION pve-enterprise" > /etc/apt/sources.list.d/pve-enterprise.list
    rm -f /etc/apt/sources.list.d/pve-no-subscription.list || true
    ;;
  2)
    echo "📦 Enabling No-Subscription repository..."
    sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list || true
    echo "deb http://download.proxmox.com/debian/pve $PVE_VERSION pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
    ;;
  *)
    echo "❌ Invalid selection. Exiting."
    exit 1
    ;;
esac

### 2. Update System
echo "📥 Updating packages..."
apt update && apt -y full-upgrade

### 3. Install Tools
echo "🔧 Installing helpful utilities..."
apt install -y \
  vim htop iftop curl wget gnupg2 software-properties-common \
  lsof net-tools zfs-zed nfs-common smartmontools unzip

### 4. Download VirtIO Drivers
echo "📦 Downloading VirtIO drivers ISO..."
mkdir -p /var/lib/vz/template/iso
wget -q --show-progress -O /var/lib/vz/template/iso/virtio-win.iso \
  https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso

### 5. ZFS ARC Tuning (Manual Selection of ARC Size)
if grep -q "zfs" /proc/filesystems; then
  echo "🧠 Configuring ZFS ARC max size..."

  # Get total RAM in bytes
  TOTAL_RAM_BYTES=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')

  # Convert bytes to GB using awk
  TOTAL_RAM_GB=$(awk "BEGIN {print $TOTAL_RAM_BYTES/1024/1024/1024}")

  echo "📏 Total RAM in the system: $TOTAL_RAM_GB GB"

  echo "🔧 ARC size recommendations based on total RAM:"
  echo "  - For servers with 8GB RAM or less: Set ARC to 1-2 GB"
  echo "  - For servers with 16GB RAM: Set ARC to 3-4 GB"
  echo "  - For servers with 32GB RAM or more: Set ARC to 6-8 GB"
  echo "  - For pure storage servers with ZFS only: You can go up to 50% of RAM, but this is not recommended for VM-heavy hosts."
  echo "🧮 Enter your desired ARC max size in GB (e.g., 2 for 2GB):"
  
  read -rp "Enter ARC size in GB: " ARC_GB
  
  if [[ ! "$ARC_GB" =~ ^[0-9]+$ ]] || [ "$ARC_GB" -le 0 ]; then
    echo "❌ Invalid ARC size entered. Exiting."
    exit 1
  fi

  # Convert ARC size from GB to bytes
  ARC_MAX_BYTES=$(( ARC_GB * 1024 * 1024 * 1024 ))

  echo "📐 Setting ZFS ARC max size to $ARC_GB GB ($ARC_MAX_BYTES bytes)..."
  
  # Set the ARC max size in the system
  echo "options zfs zfs_arc_max=$ARC_MAX_BYTES" > /etc/modprobe.d/zfs.conf
  update-initramfs -u
fi

### 6. System Tuning
echo "⚙️ Applying system performance settings..."
cat <<EOF > /etc/sysctl.d/99-proxmox.conf
fs.inotify.max_user_watches=1048576
vm.swappiness=10
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF

sysctl -p /etc/sysctl.d/99-proxmox.conf

### 7. Create Backup Directory
echo "💾 Creating backup directory..."
mkdir -p /mnt/pve/backups
echo "📝 Reminder: mount your NFS/USB/disk storage to /mnt/pve/backups and add it via Proxmox GUI."

### 8. Disable Subscription Nag (No-Sub Only)
if [[ "$REPO_CHOICE" == "2" ]]; then
  echo "🚫 Disabling Proxmox subscription popup..."
  JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
  if [[ -f "$JS_FILE" ]]; then
    cp "$JS_FILE" "${JS_FILE}.bak"
    sed -i "s/Ext.Msg.show({/void({/g" "$JS_FILE"
  fi
fi

### 9. Cleanup
echo "🧹 Cleaning up..."
apt autoremove -y

echo "✅ All done! Reboot is recommended."
