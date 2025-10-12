#!/bin/bash

SCRIPT_SOURCE="$0"
SCRIPT_NAME=$(basename "$SCRIPT_SOURCE")
if ! TEMP_SCRIPT_PATH=$(mktemp /tmp/arch_installer_XXXXXX.sh); then
    error "Failed to create temporary script"
    exit 1
fi

if [[ "$(dirname "$(realpath "$0")")" == "/mnt"* ]]; then
    echo "Detected running from /mnt directory, automatically switching to /tmp..."
    if cp "$SCRIPT_SOURCE" "$TEMP_SCRIPT_PATH" && chmod +x "$TEMP_SCRIPT_PATH"; then
        cd /tmp
        exec "$TEMP_SCRIPT_PATH" "$@"
    else
        echo "Error: Failed to copy script to /tmp"
        exit 1
    fi
fi

cleanup_script() {
    if [[ -f "$TEMP_SCRIPT_PATH" ]]; then
        rm -f "$TEMP_SCRIPT_PATH"
    fi
}

trap cleanup_script EXIT

echo "========================================"
echo "    Arch Linux Installer - v1.00"
echo "    WARNING: DATA LOSS RISK"
echo "========================================"
echo "This script will FORMAT disks and DESTROY data."
echo "You could lose your files, operating systems, etc."
echo ""
echo "BEFORE CONTINUING:"
echo "Backup all important data"
echo "Test in virtual machine first" 
echo "Verify target disk selection"
echo "Understand that you use at your own risk"
echo "The authors are not responsible for any loss"
echo ""
echo "By continuing, you accept all risks and responsibilities."
echo "Full disclaimer: https://github.com/SZ-XY/AIFC/blob/main/DISCLAIMER.md"
echo "========================================"
echo ""


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

validate_and_unmount_partition() {
    local partition=$1
    local purpose=$2
    
    if [[ ! -b "$partition" ]]; then
        error "$partition is not a valid block device for $purpose"
        return 1
    fi
    
    # 检查分区是否已被挂载，如果是则尝试卸载
    if findmnt "$partition" &> /dev/null; then
        warn "Partition $partition is currently mounted, attempting to unmount..."
        
        # 首先尝试正常卸载
        if umount "$partition" 2>/dev/null; then
            success "Successfully unmounted $partition"
        else
            # 如果正常卸载失败，尝试强制卸载
            warn "Normal unmount failed, trying force unmount..."
            if umount -f "$partition" 2>/dev/null; then
                success "Force unmount successful for $partition"
            else
                # 如果强制卸载也失败，尝试递归卸载
                warn "Force unmount failed, trying recursive unmount..."
                if umount -R "$partition" 2>/dev/null; then
                    success "Recursive unmount successful for $partition"
                else
                    error "Failed to unmount $partition - it may be in use by system processes"
                    info "You can check what's using it with: fuser -mv $partition"
                    info "Or try manually: lsof $partition"
                    return 1
                fi
            fi
        fi
    fi
    
    # 对于交换分区，还需要确保它没有被激活
    if [ "$purpose" = "swap" ]; then
        if swapon --show | grep -q "$partition"; then
            warn "Swap partition $partition is active, turning off..."
            if swapoff "$partition"; then
                success "Swap disabled for $partition"
            else
                error "Failed to disable swap on $partition"
                return 1
            fi
        fi
    fi
    
    return 0
}

check_network_connection() {
    info "Checking network connection..."
    
    local test_hosts=("archlinux.org" "baidu.com")
    local connection_ok=false
    local retry_count=0
    local max_retries=2
    
    while [ $retry_count -lt $max_retries ] && [ "$connection_ok" = false ]; do
        for host in "${test_hosts[@]}"; do
            if ping -c 3 -W 3 "$host" &> /dev/null; then
                connection_ok=true
                break
            fi
        done
        
        if [ "$connection_ok" = false ]; then
            ((retry_count++))
            if [ $retry_count -lt $max_retries ]; then
                info "Network check failed, retrying in 3 seconds... ($retry_count/$max_retries)"
                sleep 3
            fi
        fi
    done
    
    if ! $connection_ok; then
        # 尝试 HTTP 连接作为后备
        info "Trying HTTP connection as fallback..."
        if curl -s --connect-timeout 10 --max-time 15 http://www.baidu.com > /dev/null || \
           curl -s --connect-timeout 10 --max-time 15 http://captive.apple.com > /dev/null; then
            connection_ok=true
            warn "HTTP connection works but ping may be blocked"
        fi
    fi
    
    if $connection_ok; then
        success "Network connection verified"
        return 0
    else
        warn "No reliable network connection detected"
        return 1
    fi
}

cleanup_on_error() {
    error "Installation failed! Performing cleanup..."
    
    if mountpoint -q /mnt; then
        warn "Unmounting partitions..."
        umount -R /mnt 2>/dev/null || true
    fi
    
    swapoff -a 2>/dev/null || true
    cleanup_script
}

set -e
trap cleanup_on_error ERR

check_uefi_support() {
    info "Checking UEFI support..."
    
    if [[ -d /sys/firmware/efi ]]; then
        info "UEFI mode detected"
        
        if ! mount | grep -q efivarfs; then
            info "Mounting efivarfs..."
            if mount -t efivarfs efivarfs /sys/firmware/efi/efivars; then
                success "efivarfs mounted"
            else
                error "Failed to mount efivarfs"
                return 1
            fi
        else
            info "efivarfs already mounted"
        fi
        return 0
    else
        warn "UEFI mode not detected - BIOS/Legacy mode"
        return 1
    fi
}

connect_wifi() {
    if confirm "Do you want to connect to WiFi?"; then
        info "Connecting to WiFi"
        
        local max_retries=3
        local retry_count=0
        
        while [ $retry_count -lt $max_retries ]; do
            read -p "Enter WiFi SSID: " wifi_name
            read -s -p "Enter WiFi password: " wifi_password
            echo
            
            info "Connecting to $wifi_name..."
            
            if iwctl --passphrase "$wifi_password" station wlan0 connect "$wifi_name"; then
                info "Waiting for connection..."
                sleep 5
                
                if check_network_connection; then
                    success "Network connected!"
                    return 0
                fi
            fi
            
            ((retry_count++))
            warn "Connection failed (attempt $retry_count/$max_retries)"
        done
        
        error "Failed to connect to WiFi after $max_retries attempts"
        if confirm "Continue without network?"; then
            warn "Continuing without network"
            return 0
        else
            exit 1
        fi
    else
        info "Skipping WiFi"
        if ! check_network_connection; then
            warn "No network connection"
            if ! confirm "Continue without network?"; then
                exit 1
            fi
        fi
    fi
}

check_and_format_partition() {
    local partition=$1
    local expected_fs=$2
    local mount_point=$3
    
    info "Checking partition $partition..."
    
    local current_fs=$(blkid -s TYPE -o value "$partition" 2>/dev/null)
    
    if [ -n "$current_fs" ]; then
        info "Partition $partition filesystem: $current_fs"
        
        if [ "$expected_fs" = "fat32" ]; then
            expected_fs="vfat"
        fi
        
        if [ "$current_fs" != "$expected_fs" ]; then
            warn "Wrong filesystem ($current_fs), expected $expected_fs"
            if confirm "Format $partition as $expected_fs? (ERASES ALL DATA!)"; then
                case $expected_fs in
                    "vfat")
                        info "Formatting as FAT32..."
                        if ! mkfs.fat -F32 "$partition"; then
                            error "Failed to format as FAT32"
                            return 1
                        fi
                        ;;
                    "btrfs")
                        info "Formatting as Btrfs..."
                        if ! mkfs.btrfs -f "$partition"; then
                            error "Failed to format as Btrfs"
                            return 1
                        fi
                        ;;
                    "swap")
                        info "Formatting as swap..."
                        if ! mkswap "$partition"; then
                            error "Failed to format as swap"
                            return 1
                        fi
                        ;;
                    *)
                        error "Unknown filesystem: $expected_fs"
                        return 1
                        ;;
                esac
                success "Partition formatted as $expected_fs"
            else
                warn "Using incorrect filesystem $current_fs"
            fi
        else
            info "Correct filesystem: $expected_fs"
        fi
    else
        warn "No filesystem detected"
        if confirm "Format $partition as $expected_fs?"; then
            if [ "$expected_fs" = "fat32" ]; then
                expected_fs="vfat"
            fi
            
            case $expected_fs in
                "vfat")
                    info "Formatting as FAT32..."
                    if ! mkfs.fat -F32 "$partition"; then
                        error "Failed to format as FAT32"
                        return 1
                    fi
                    ;;
                "btrfs")
                    info "Formatting as Btrfs..."
                    if ! mkfs.btrfs -f "$partition"; then
                        error "Failed to format as Btrfs"
                        return 1
                    fi
                    ;;
                "swap")
                    info "Formatting as swap..."
                    if ! mkswap "$partition"; then
                        error "Failed to format as swap"
                        return 1
                    fi
                    ;;
            esac
            success "Partition formatted as $expected_fs"
        else
            error "Cannot use unformatted partition"
            return 1
        fi
    fi
    
    return 0
}

setup_disk() {
    info "Disk partitioning and mounting"
    echo "Current disk layout:"
    lsblk -p
    
    echo "Note: Please use existing partitions only"
    echo "You need to manually create partitions before running this script"
    
    # 获取根分区
    while true; do
        read -p "Enter ROOT partition (e.g., /dev/sda1): " ROOT_PARTITION
        if [ -e "$ROOT_PARTITION" ]; then
            if ! validate_and_unmount_partition "$ROOT_PARTITION" "root"; then
                error "Cannot use root partition $ROOT_PARTITION"
                if ! confirm "Try again with different partition?"; then
                    exit 1
                fi
            else
                break
            fi
        else
            error "Partition $ROOT_PARTITION doesn't exist!"
            if ! confirm "Try again?"; then
                exit 1
            fi
        fi
    done
    
    # 获取交换分区
    while true; do
        read -p "Enter SWAP partition (e.g., /dev/sda2, or leave empty for no swap): " SWAP_PARTITION
        if [ -z "$SWAP_PARTITION" ]; then
            info "No swap partition specified"
            break
        elif [ -e "$SWAP_PARTITION" ]; then
            if ! validate_and_unmount_partition "$SWAP_PARTITION" "swap"; then
                error "Cannot use swap partition $SWAP_PARTITION"
                if confirm "Continue without swap?"; then
                    SWAP_PARTITION=""
                    break
                fi
            else
                break
            fi
        else
            error "Partition $SWAP_PARTITION doesn't exist!"
            if confirm "Continue without swap?"; then
                SWAP_PARTITION=""
                break
            fi
        fi
    done
    
    # 获取EFI分区（如果是UEFI模式）
    if check_uefi_support; then
        while true; do
            read -p "Enter EFI partition (e.g., /dev/sda1): " EFI_PARTITION
            EFI_REQUIRED=true
            if [ -e "$EFI_PARTITION" ]; then
                if ! validate_and_unmount_partition "$EFI_PARTITION" "EFI"; then
                    error "Cannot use EFI partition $EFI_PARTITION"
                    if ! confirm "Try again with different partition?"; then
                        exit 1
                    fi
                else
                    break
                fi
            else
                error "Partition $EFI_PARTITION doesn't exist!"
                if ! confirm "Try again?"; then
                    exit 1
                fi
            fi
        done
    else
        info "BIOS mode - no EFI partition needed"
        EFI_REQUIRED=false
    fi
    
    # 显示分区选择
    info "Partition selection:"
    info "Root: $ROOT_PARTITION"
    info "Swap: ${SWAP_PARTITION:-none}"
    if [ "$EFI_REQUIRED" = true ]; then
        info "EFI: $EFI_PARTITION"
    fi
    
    if ! confirm "Proceed with formatting and mounting?"; then
        error "Cancelled"
        exit 1
    fi
    
    # 准备根分区
    if ! check_and_format_partition "$ROOT_PARTITION" "btrfs" "/mnt"; then
        error "Failed to prepare root"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    info "Mounting root..."
    if ! mount -t btrfs -o compress=zstd "$ROOT_PARTITION" /mnt; then
        error "Failed to mount $ROOT_PARTITION"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    info "Creating subvolumes..."
    if ! btrfs subvolume create /mnt/@; then
        error "Failed to create root subvolume"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    if ! btrfs subvolume create /mnt/@home; then
        error "Failed to create home subvolume"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    info "Remounting subvolumes..."
    umount /mnt
    
    if ! mount -t btrfs -o subvol=/@,compress=zstd "$ROOT_PARTITION" /mnt; then
        error "Failed to remount root"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    mkdir -p /mnt/home
    if ! mount -t btrfs -o subvol=/@home,compress=zstd "$ROOT_PARTITION" /mnt/home; then
        error "Failed to mount home"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    # 准备EFI分区
    if [ "$EFI_REQUIRED" = true ]; then
        if ! check_and_format_partition "$EFI_PARTITION" "vfat" "/mnt/boot/efi"; then
            error "Failed to prepare EFI"
            if ! confirm "Continue?"; then
                exit 1
            fi
        fi
        
        mkdir -p /mnt/boot/efi
        if ! mount "$EFI_PARTITION" /mnt/boot/efi; then
            error "Failed to mount EFI"
            if ! confirm "Continue?"; then
                exit 1
            fi
        fi
    else
        info "Skipping EFI for BIOS"
    fi
    
    # 准备交换分区
    if [ -n "$SWAP_PARTITION" ]; then
        if ! check_and_format_partition "$SWAP_PARTITION" "swap" "swap"; then
            error "Failed to prepare swap"
            if ! confirm "Continue without swap?"; then
                exit 1
            fi
        else
            if ! swapon "$SWAP_PARTITION"; then
                error "Failed to enable swap"
                if ! confirm "Continue without swap?"; then
                    exit 1
                fi
            fi
        fi
    else
        warn "No swap configured"
    fi
    
    success "Disk setup done"
    info "Mount points:"
    df -h
    echo ""
    info "Swap status:"
    swapon --show
}

setup_mirrors() {
    info "Configuring mirrors"
    if ! cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak; then
        error "Failed to backup mirrorlist"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    if ! cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
EOF
    then
        error "Failed to create mirrorlist"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    cat /etc/pacman.d/mirrorlist.bak >> /etc/pacman.d/mirrorlist
    
    success "Mirrors configured"
}

install_system() {
    info "Installing base system"
    
    info "Updating keyring..."
    if ! pacman -Sy archlinux-keyring --noconfirm; then
        error "Failed to update keyring"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    local ucode_package="intel-ucode"
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        ucode_package="amd-ucode"
        info "AMD CPU, installing amd-ucode"
    else
        info "Intel CPU, installing intel-ucode"
    fi
    
    info "Choose kernel:"
    echo "1) Mainstream stable (linux)"
    echo "2) Long-term support (linux-lts)"
    echo "3) Hardened security (linux-hardened)"
    echo "4) Performance optimized (linux-zen)"
    
    read -p "Enter choice (1-4): " kernel_choice
    
    case $kernel_choice in
        1)
            kernel_packages="linux linux-headers"
            info "Installing stable kernel"
            ;;
        2)
            kernel_packages="linux-lts linux-lts-headers"
            info "Installing LTS kernel"
            ;;
        3)
            kernel_packages="linux-hardened linux-hardened-headers"
            info "Installing hardened kernel"
            ;;
        4)
            kernel_packages="linux-zen linux-zen-headers"
            info "Installing zen kernel"
            ;;
        *)
            warn "Invalid, using stable"
            kernel_packages="linux linux-headers"
            ;;
    esac
    
    info "Installing base system..."
    if ! pacstrap -K /mnt base base-devel $kernel_packages linux-firmware btrfs-progs noto-fonts-cjk --noconfirm; then
        error "Failed to install base"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    info "Installing tools..."
    if ! pacstrap /mnt vim sudo bash-completion iwd dhcpcd dhclient git networkmanager $ucode_package --noconfirm; then
        error "Failed to install tools"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    success "Base system installed"
}

cleanup_fstab() {
    info "Cleaning up fstab file..."
    
    # 备份原文件
    cp /mnt/etc/fstab /mnt/etc/fstab.backup.$(date +%s)
    
    # 移除 VMware 共享文件夹条目
    sed -i '/vmhgfs-fuse/d' /mnt/etc/fstab
    
    # 移除重复的 swap 条目
    awk '!seen[$0]++' /mnt/etc/fstab > /mnt/etc/fstab.tmp && mv /mnt/etc/fstab.tmp /mnt/etc/fstab
    
    # 移除空白行
    sed -i '/^$/d' /mnt/etc/fstab
    
    success "fstab cleaned up"
}

generate_fstab() {
    local swap_partition=$1
    
    info "Generating fstab..."
    if ! genfstab -U /mnt > /mnt/etc/fstab; then
        error "Failed to generate fstab"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    # 确保 Btrfs 挂载选项正确
    info "Ensuring Btrfs mount options..."
    if grep -q "btrfs" /mnt/etc/fstab; then
        # 为 Btrfs 分区添加正确的挂载选项
        sed -i '/btrfs/s/defaults/subvol=\/@,compress=zstd,defaults/g' /mnt/etc/fstab
        # 修复 home 子卷的挂载点
        sed -i '/\/home.*btrfs/s/defaults/subvol=\/@home,compress=zstd,defaults/g' /mnt/etc/fstab
    fi
    
    # 如果提供了 swap 分区，确保有一个 swap 条目
    if [ -n "$swap_partition" ]; then
        local swap_uuid=$(blkid -s UUID -o value "$swap_partition")
        if [ -n "$swap_uuid" ]; then
            # 检查是否已存在该 swap 条目
            if ! grep -q "$swap_uuid" /mnt/etc/fstab; then
                info "Adding swap to fstab: $swap_uuid"
                echo "UUID=$swap_uuid none swap defaults 0 0" >> /mnt/etc/fstab
            else
                info "Swap entry already exists in fstab"
            fi
        else
            warn "No swap UUID found"
        fi
    fi
    
    cleanup_fstab
    
    # 验证 fstab
    info "Verifying fstab..."
    if ! arch-chroot /mnt bash -c "findmnt --verify --verbose"; then
        error "fstab verification failed"
        if confirm "View fstab content?"; then
            cat /mnt/etc/fstab
        fi
        if ! confirm "Continue despite fstab errors?"; then
            exit 1
        fi
    fi
    
    success "fstab generated and verified"
}

chroot_setup() {
    info "Chroot configuration"
    
    local uefi_supported=false
    local cpu_vendor="intel"
    
    if [[ -d /sys/firmware/efi ]]; then
        uefi_supported=true
    fi
    
    if grep -q "AuthenticAMD" /proc/cpuinfo; then
        cpu_vendor="amd"
    fi
    
    cat > /mnt/root/chroot_setup.sh << 'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

echo "Starting chroot config..."

UEFI_SUPPORTED=false
if [[ -d /sys/firmware/efi ]]; then
    UEFI_SUPPORTED=true
fi

CPU_VENDOR="intel"
if grep -q "AuthenticAMD" /proc/cpuinfo; then
    CPU_VENDOR="amd"
fi

info "Setting hostname..."
echo "archlinux" > /etc/hostname

info "Setting timezone..."
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc

info "Setting locale..."
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
locale-gen

cat > /etc/locale.conf << 'LOCALE_EOF'
LANG=en_US.UTF-8
LC_CTYPE=zh_CN.UTF-8
LC_NUMERIC=zh_CN.UTF-8
LC_TIME=zh_CN.UTF-8
LC_COLLATE=zh_CN.UTF-8
LC_MONETARY=zh_CN.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=zh_CN.UTF-8
LC_NAME=zh_CN.UTF-8
LC_ADDRESS=zh_CN.UTF-8
LC_TELEPHONE=zh_CN.UTF-8
LC_MEASUREMENT=zh_CN.UTF-8
LC_IDENTIFICATION=zh_CN.UTF-8
LOCALE_EOF

info "Setting root password..."
while true; do
    if passwd; then
        break
    else
        warn "Password failed, retry"
        if ! confirm "Retry?"; then
            warn "Skipping password"
            break
        fi
    fi
done

info "Installing bootloader..."
pacman -S grub efibootmgr os-prober --noconfirm

# 添加 NetworkManager 安装
info "Installing NetworkManager..."
if ! pacman -S networkmanager --noconfirm; then
    error "Failed to install NetworkManager"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

install_bootloader() {
    info "Installing bootloader..."
    
    if [ "$UEFI_SUPPORTED" = "true" ]; then
        info "Installing UEFI GRUB..."
        if grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux; then
            success "UEFI GRUB installed"
            return 0
        else
            error "UEFI GRUB failed"
        fi
    fi
    
    warn "Trying BIOS install..."
    info "Available disks:"
    lsblk
    
    read -p "Enter disk for BIOS (e.g., /dev/sda,not partition like:/dev/sda1): " bios_disk
    
    if [[ -z "$bios_disk" ]]; then
        bios_disk="/dev/sda"
        warn "Using default: $bios_disk"
    fi
    
    if [[ ! -e "$bios_disk" ]]; then
        error "Disk $bios_disk doesn't exist"
        return 1
    fi
    
    info "Installing BIOS GRUB on $bios_disk..."
    if grub-install --target=i386-pc "$bios_disk"; then
        success "BIOS GRUB installed"
        return 0
    else
        error "BIOS GRUB failed"
        return 1
    fi
}

if ! install_bootloader; then
    error "Bootloader failed"
    if confirm "Continue without bootloader?"; then
        warn "No bootloader - manual install needed"
    else
        exit 1
    fi
fi

info "Configuring GRUB..."
if [ "$CPU_VENDOR" = "amd" ]; then
    watchdog_blacklist="modprobe.blacklist=sp5100_tco"
    info "AMD CPU, using sp5100_tco"
else
    watchdog_blacklist="modprobe.blacklist=iTCO_wdt"
    info "Intel CPU, using iTCO_wdt"
fi

if confirm "Add watchdog blacklist?"; then
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=5 nowatchdog $watchdog_blacklist\"/" /etc/default/grub
else
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=5"/' /etc/default/grub
fi

sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

info "Configuring GRUB for Btrfs..."
root_fs_type=$(mount | grep "on / " | awk '{print $5}')
if [ "$root_fs_type" = "btrfs" ]; then
    info "Detected Btrfs root filesystem, adding Btrfs-specific options"
    if ! grep -q "btrfs" /etc/default/grub; then
        sed -i 's/^GRUB_PRELOAD_MODULES="/&btrfs /' /etc/default/grub
        if mount | grep -q "subvol=@"; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&rootflags=subvol=@ /' /etc/default/grub
        fi
    fi
fi

info "Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg

info "Enabling NetworkManager..."
if ! systemctl enable NetworkManager; then
    error "Failed to enable NetworkManager"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

success "Chroot done!"
EOF

    chmod +x /mnt/root/chroot_setup.sh
    if ! arch-chroot /mnt /root/chroot_setup.sh; then
        error "Chroot errors"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
}

setup2() {
    info "Creating phase 2 script..."
    
    cat > /mnt/root/setup2.sh << 'EOFSET'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

check_network_connection() {
    info "Checking network connection..."
    
    local test_hosts=("archlinux.org" "baidu.com")
    local connection_ok=false
    local retry_count=0
    local max_retries=2
    
    while [ $retry_count -lt $max_retries ] && [ "$connection_ok" = false ]; do
        for host in "${test_hosts[@]}"; do
            if ping -c 3 -W 3 "$host" &> /dev/null; then
                connection_ok=true
                break
            fi
        done
        
        if [ "$connection_ok" = false ]; then
            ((retry_count++))
            if [ $retry_count -lt $max_retries ]; then
                info "Network check failed, retrying in 3 seconds... ($retry_count/$max_retries)"
                sleep 3
            fi
        fi
    done
    
    if ! $connection_ok; then
        # 尝试 HTTP 连接作为后备
        info "Trying HTTP connection as fallback..."
        if curl -s --connect-timeout 10 --max-time 15 http://www.baidu.com > /dev/null || \
           curl -s --connect-timeout 10 --max-time 15 http://captive.apple.com > /dev/null; then
            connection_ok=true
            warn "HTTP connection works but ping may be blocked"
        fi
    fi
    
    if $connection_ok; then
        success "Network connection verified"
        return 0
    else
        warn "No reliable network connection detected"
        return 1
    fi
}

echo "========================================"
echo "     Phase 2 Setup"
echo "========================================"

info "Need network connection"
info "Connect WiFi:"
echo "1. nmcli dev wifi connect 'SSID' password 'password'"
echo "2. nmtui"
echo ""
read -p "Press Enter after connecting..."

if ! check_network_connection; then
    if ! confirm "Continue without network?"; then
        exit 1
    fi
fi


if confirm "Are you running on VMWare virtual machine? (Install open-vm-tools for better integration)"; then
    info "Installing VMWare Tools (open-vm-tools)..."
    if pacman -S open-vm-tools --noconfirm; then
        success "open-vm-tools installed"
        
        # 启用服务
        info "Enabling VMWare services..."
        systemctl enable vmtoolsd
        systemctl enable vmware-vmblock-fuse
        systemctl start vmtoolsd
        systemctl start vmware-vmblock-fuse
        
        success "VMWare Tools setup completed"
    else
        error "Failed to install open-vm-tools"
        if confirm "Continue without VMWare Tools?"; then
            warn "Continuing without VMWare Tools"
        else
            exit 1
        fi
    fi
fi

info "Auto detecting graphics..."
gpu_detected=false
amd_gpu=false
intel_xe_gpu=false
amd_780m_like=false

# 改进的 Intel 显卡检测
if lspci | grep -i "VGA" | grep -i "Intel" &> /dev/null; then
    info "Intel graphics detected"
    
    # 首先安装基础Intel驱动
    if pacman -S xf86-video-intel --noconfirm; then
        success "Intel driver installed"
        gpu_detected=true
    else
        error "Intel driver failed"
    fi
    
    # 更精确的 Intel Xe 检测
    local intel_gpu_info=$(lspci -v | grep -A 10 -i "VGA.*Intel")
    if echo "$intel_gpu_info" | grep -i -E "(Iris Xe|UHD Graphics 7[5-9]|UHD Graphics 8[0-9]|Xe Graphics|G12|Tiger Lake-U|Rocket Lake-U|Alder Lake-U|Raptor Lake-U)" &> /dev/null; then
        intel_xe_gpu=true
        info "Intel Xe or modern integrated graphics detected, installing hardware acceleration drivers..."
        if pacman -S intel-media-driver libva libva-utils --noconfirm; then
            success "Intel graphics acceleration drivers installed"
        else
            error "Failed to install Intel acceleration drivers"
        fi
    fi
fi

# 检测AMD显卡
if lspci | grep -i "VGA" | grep -i "AMD" &> /dev/null; then
    info "AMD graphics detected"
    if pacman -S xf86-video-amdgpu --noconfirm; then
        success "AMD driver installed"
        gpu_detected=true
        amd_gpu=true
        
        # 检测是否为AMD 780M或类似显卡
        if lspci -v | grep -i "Radeon 780M" &> /dev/null || \
           lspci -v | grep -i "RDNA3" &> /dev/null || \
           lspci -v | grep -i "Navi 3" &> /dev/null || \
           lspci -v | grep -i "Ryzen 7040" &> /dev/null || \
           lspci -v | grep -i "Ryzen 8040" &> /dev/null; then
            amd_780m_like=true
            info "AMD 780M or similar graphics detected, ensuring libva-mesa-driver is installed..."
            if ! pacman -Q libva-mesa-driver &> /dev/null; then
                if pacman -S libva-mesa-driver --noconfirm; then
                    success "libva-mesa-driver installed"
                else
                    error "Failed to install libva-mesa-driver"
                fi
            else
                info "libva-mesa-driver already installed"
            fi
        fi
    else
        error "AMD driver failed"
    fi
fi

# NVIDIA显卡不管
if lspci | grep -i "VGA" | grep -i "NVIDIA" &> /dev/null; then
    info "NVIDIA graphics detected"
    warn "NVIDIA needs manual install, continuing in 3s..."
    sleep 3
    gpu_detected=true
fi

if [ "$gpu_detected" = false ]; then
    warn "No common graphics, continuing in 3s..."
    sleep 3
fi


info "Choose desktop environment:"
echo "1) KDE Plasma"
echo "2) GNOME"
read -p "Enter choice (1-2): " desktop_choice

case $desktop_choice in
    1)
        desktop_packages="xorg-server xorg-xinit plasma-meta kde-system-meta kde-utilities-meta sddm flatpak"
        display_manager="sddm"
        info "Installing KDE Plasma..."
        ;;
    2)
        desktop_packages="gnome-desktop gdm ghostty gnome-control-center gnome-software flatpak gnome-text-editor gnome-disk-utility gnome-clocks gnome-calculator fragments"
        display_manager="gdm"
        info "Installing GNOME..."
        ;;
    *)
        warn "Invalid choice, using KDE Plasma"
        desktop_packages="xorg-server xorg-xinit plasma-meta kde-system-meta kde-utilities-meta sddm flatpak"
        display_manager="sddm"
        ;;
esac


info "Installing desktop environment..."
if ! pacman -S $desktop_packages --noconfirm; then
    error "Failed to install desktop environment"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

setup_sddm() {
    info "设置SDDM显示管理器..."
    
    if ! pacman -Q sddm &>/dev/null; then
        info "安装SDDM..."
        pacman -S sddm --noconfirm
    fi
    
    # 停止服务（如果正在运行）
    systemctl stop sddm 2>/dev/null || true
    
    # 创建必要的目录结构
    mkdir -p /var/lib/sddm
    mkdir -p /var/lib/sddm/.config
    mkdir -p /etc/sddm.conf.d
    
    # 设置正确的权限
    chown -R sddm:sddm /var/lib/sddm
    chmod 755 /var/lib/sddm
    chmod 700 /var/lib/sddm/.config
    
    # 使用配置文件片段而不是覆盖主配置
    cat > /etc/sddm.conf.d/arch-installer.conf << 'SDDM_EOF'
[Autologin]
Relogin=false
Session=
User=

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
DisplayServer=x11

[Theme]
Current=breeze
CursorTheme=breeze_cursors
Font=Noto Sans,10,-1,0,50,0,0,0,0,0
ThemeDir=/usr/share/sddm/themes

[Users]
MaximumUid=65000
MinimumUid=1000
HideUsers=
HideShells=

[X11]
DisplayCommand=/usr/share/sddm/scripts/Xsetup
DisplayStopCommand=/usr/share/sddm/scripts/Xstop
SDDM_EOF
    
    systemctl enable sddm
    
    success "SDDM configuration completed (will take effect after reboot)"
}


if [ "$desktop_choice" = "1" ]; then
    setup_sddm
fi


if [ "$amd_gpu" = true ]; then
    info "Installing Vulkan support for AMD graphics..."
    if ! pacman -S vulkan-radeon --noconfirm; then
        error "Failed to install Vulkan support"
        if ! confirm "Continue?"; then
            exit 1
        fi
    else
        success "Vulkan support installed for AMD graphics"
    fi
fi

info "Enabling display manager..."
if ! systemctl enable $display_manager; then
    error "Failed to enable $display_manager"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

info "Creating user account..."
username=""
while true; do
    read -p "Enter username: " username
    if [ -z "$username" ]; then
        error "Username cannot be empty"
        continue
    fi
    
    # 验证用户名格式
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        error "Invalid username format. Use only lowercase letters, numbers, - and _"
        continue
    fi
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        warn "User $username already exists"
        if confirm "Use existing user?"; then
            break
        else
            continue
        fi
    fi
    
    # 创建用户
    if useradd -m -g wheel -s /bin/bash "$username"; then
        success "User $username created"
        break
    else
        error "Failed to create user $username"
        if ! confirm "Try again?"; then
            error "Cannot continue without user account"
            exit 1
        fi
    fi
done

# 设置用户密码
echo "Setting password for $username:"
while true; do
    if passwd "$username"; then
        success "Password set for $username"
        break
    else
        error "Failed to set password"
        if ! confirm "Try again?"; then
            warn "Continuing without password set"
            break
        fi
    fi
done

info "Configuring sudo..."
if ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
    success "sudo configured for wheel group"
fi

info "Configuring archlinuxcn..."
cat >> /etc/pacman.conf << 'ENDOFFILE'

[archlinuxcn]
SigLevel = Optional TrustedOnly
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch 
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch 
Server = https://mirrors.hit.edu.cn/archlinuxcn/$arch 
Server = https://repo.huaweicloud.com/archlinuxcn/$arch
ENDOFFILE

if ! pacman -Sy --noconfirm; then
    error "Failed to sync db"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

if ! pacman -S archlinuxcn-keyring --noconfirm; then
    error "Failed to install keyring"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

if ! pacman -S yay --noconfirm; then
    error "Failed to install yay"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

info "Installing extras..."
if ! pacman -S fastfetch lolcat cmatrix --noconfirm; then
    warn "Failed to install extras"
fi

info "Creating desktop script..."
user_home="/home/$username"
desktop_dir="$user_home/Desktop"

mkdir -p "$desktop_dir"

cat > "$desktop_dir/README-Setup3.txt" << 'EOF'
安装的最后一步：
请打开终端，输入一下代码并执行
sudo bash /root/setup3.sh
EOF


chown -R "$username:wheel" "$desktop_dir"

cat > "/root/setup3.sh" << 'SCRIPT_EOF'
#!/bin/bash

if ! grep -q "Arch\|Manjaro" /etc/os-release; then
    echo "错误：此脚本仅适用于 Arch Linux 及其衍生版"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "需要管理员权限，请使用 sudo 运行此脚本"
    exit 1
fi

if [ -f "/root/setup2.sh" ]; then
    echo "删除第二阶段脚本 /root/setup2.sh"
    rm -f /root/setup2.sh
fi

echo "开始第三阶段安装..."


echo "安装网络管理工具..."
pacman -S --noconfirm network-manager-applet dnsmasq

echo "安装音频软件..."
pacman -S --needed --noconfirm sof-firmware alsa-firmware alsa-ucm-conf

echo "安装 pipewire 音频系统..."
pacman -S --needed --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber


echo "启用 pipewire 服务..."
if [ -n "$SUDO_USER" ]; then
    sudo -u $SUDO_USER systemctl --user enable --now pipewire pipewire-pulse wireplumber
else
    echo "警告：无法确定当前用户，pipewire 服务可能需要手动启用"
fi

echo "启用蓝牙服务..."
systemctl enable --now bluetooth

echo "安装 fcitx5 输入法..."
pacman -S --noconfirm fcitx5-im fcitx5-chinese-addons

echo "配置输入法环境变量..."
if ! grep -q "GTK_IM_MODULE=fcitx5" /etc/environment; then
    echo "GTK_IM_MODULE=fcitx5" >> /etc/environment
fi

if ! grep -q "QT_IM_MODULE=fcitx5" /etc/environment; then
    echo "QT_IM_MODULE=fcitx5" >> /etc/environment
fi

if ! grep -q "XMODIFIERS=@im=fcitx5" /etc/environment; then
    echo "XMODIFIERS=@im=fcitx5" >> /etc/environment
fi

if systemctl is-enabled vmtoolsd &>/dev/null; then
    echo "启动 VMWare Tools 服务..."
    systemctl start vmtoolsd
    systemctl start vmware-vmblock-fuse
    
    echo ""
    echo "VMWare 共享文件夹使用说明（手动挂载）："
    echo "1. 首先在 VMWare 设置中启用共享文件夹"
    echo "2. 手动挂载命令：vmhgfs-fuse .host:/ /你想要挂载到的文件夹 -o allow_other"
fi

# 只有 UEFI 系统才询问是否安装 rEFInd
if [[ -d /sys/firmware/efi ]]; then
    read -p "是否安装 rEFInd 引导程序以更好的选择启动的系统？(y/n): " install_refind
    if [[ $install_refind =~ ^[Yy]$ ]]; then
        echo "正在安装 rEFInd..."
        pacman -S --noconfirm refind
        refind-install
        echo "rEFInd 安装完成"
        echo "注意：rEFInd 已安装，如需配置请编辑 /boot/efi/EFI/refind/refind.conf"
    fi
fi

echo "基本系统配置完成！"

# 询问是否开启32位支持
read -p "是否开启32位软件支持（multilib）？(y/n): " enable_multilib
if [[ $enable_multilib =~ ^[Yy]$ ]]; then
    echo "正在开启32位软件支持..."
    if grep -q "^#\[multilib\]" /etc/pacman.conf; then
        # 取消注释 multilib 部分
        sed -i '/^#\[multilib\]/{n;s/^#//;}' /etc/pacman.conf
        sed -i 's/^#\[multilib\]/\[multilib\]/' /etc/pacman.conf
        echo "已开启32位软件支持"
        echo "正在更新软件包数据库..."
        pacman -Sy
    else
        echo "32位软件支持已经开启或配置格式不同，请手动检查 /etc/pacman.conf"
    fi
fi

# 询问是否安装额外字体
read -p "是否安装文泉驿正黑字体和Noto表情符号字体？(y/n): " install_fonts
if [[ $install_fonts =~ ^[Yy]$ ]]; then
    echo "正在安装字体..."
    pacman -S --noconfirm wqy-zenhei noto-fonts-emoji
    echo "字体安装完成"
fi

read -p "是否安装图形化声音管理工具 (pavucontrol)？(y/n): " install_pavucontrol
if [[ $install_pavucontrol =~ ^[Yy]$ ]]; then
    echo "正在安装 pavucontrol..."
    pacman -S --noconfirm pavucontrol
fi

read -p "是否安装画图工具 (krita)？(y/n): " install_krita
if [[ $install_krita =~ ^[Yy]$ ]]; then
    echo "正在安装 krita..."
    pacman -S --noconfirm krita
fi

read -p "是否安装视频剪辑工具 (kdenlive)？(y/n): " install_kdenlive
if [[ $install_kdenlive =~ ^[Yy]$ ]]; then
    echo "正在安装 kdenlive..."
    pacman -S --noconfirm kdenlive
fi

libreoffice_installed=false

read -p "是否启用性能模式？(y/n): " enable_performance
if [[ $enable_performance =~ ^[Yy]$ ]]; then
    echo "正在安装性能模式支持..."
    pacman -S --noconfirm power-profiles-daemon
    systemctl enable --now power-profiles-daemon
fi

read -p "是否安装 Firefox 浏览器？(y/n): " install_firefox
if [[ $install_firefox =~ ^[Yy]$ ]]; then
    echo "正在安装 Firefox..."
    pacman -S --noconfirm firefox firefox-i18n-zh-cn
fi

read -p "是否安装 Zen 浏览器？(y/n): " install_zen
if [[ $install_zen =~ ^[Yy]$ ]]; then
    echo "正在安装 Zen 浏览器..."
    pacman -S --noconfirm zen-browser zen-browser-i18n-zh-cn
fi

read -p "是否安装 LibreOffice 稳定版？(y/n): " install_libreoffice_still
if [[ $install_libreoffice_still =~ ^[Yy]$ ]]; then
    echo "正在安装 LibreOffice 稳定版..."
    pacman -S --noconfirm libreoffice-still libreoffice-still-zh-cn
    libreoffice_installed=true
fi

if [[ $libreoffice_installed == false ]]; then
    read -p "是否安装 LibreOffice 最新版？(y/n): " install_libreoffice_fresh
    if [[ $install_libreoffice_fresh =~ ^[Yy]$ ]]; then
        echo "正在安装 LibreOffice 最新版..."
        pacman -S --noconfirm libreoffice-fresh libreoffice-fresh-zh-cn
    fi
fi

echo "所有安装完成！"
echo "注意：某些设置需要重启系统才能生效"
echo "输入法配置可能需要重新登录才能使用"
SCRIPT_EOF

chmod +x "/root/setup3.sh"

success "Desktop script at $desktop_dir/README-Setup3.txt"

success "Setup done!"
echo ""
echo "Next:"
echo "1. reboot"
echo "2. Login as $username"
echo "3. Run sudo /root/setup3.sh"
EOFSET

    chmod +x /mnt/root/setup2.sh
    success "Phase 2 script created"
}

main() {
    ROOT_PARTITION=""
    SWAP_PARTITION=""
    EFI_PARTITION=""
    EFI_REQUIRED=false
    
    
    read -p "Do you understand and wish to continue? (type 'I ACCEPT'): " acceptance
    if [ "$(echo "$acceptance" | tr '[:lower:]' '[:upper:]')" != "I ACCEPT" ]; then
        echo "Operation cancelled. No changes were made."
        exit 1
    fi
    
    echo "Warning acknowledged. Proceeding with installation..."
    
    connect_wifi
    setup_disk
    setup_mirrors
    install_system
    generate_fstab "$SWAP_PARTITION"
    chroot_setup
    
    rm -f /mnt/root/chroot_setup.sh
    
    setup2
    
    success "========================================"
    success "     Phase 1 Complete!"
    success "========================================"
    
    info "Cleaning up..."
    info "Unmounting partitions..."
    if umount -R /mnt; then
        success "Unmounted successfully"
    else
        error "Failed to unmount /mnt"
        warn "Please manually check and unmount before rebooting:"
        info "To see what's using /mnt: fuser -mv /mnt"
        info "To force unmount: umount -R -f /mnt"
        info "After resolving, manually run: reboot"
        exit 1
    fi
    
    info "Turning off swap..."
    swapoff -a
    
    info "Phase 1 done!"
    echo ""
    info "After reboot:"
    echo "- Login as root"
    echo "- Run: /root/setup2.sh"
    echo ""
    warn "Remove installation media!"
    
    if confirm "Reboot now?"; then
        info "Rebooting..."
        reboot
    else
        info "Reboot manually later"
    fi
}

main