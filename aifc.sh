#!/bin/bash

echo "========================================"
echo "    Arch Linux Interactive Installer"
echo "========================================"

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
        info "Step 1: Connect to WiFi"
        
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
                
                local connect_check=0
                while [ $connect_check -lt 5 ]; do
                    if ping -c 3 -W 3 archlinux.org &> /dev/null; then
                        success "Network connected!"
                        return 0
                    fi
                    sleep 2
                    ((connect_check++))
                done
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
        if ! ping -c 3 -W 3 archlinux.org &> /dev/null; then
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
        
        # 统一文件系统名称
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
            # 统一文件系统名称
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
    info "Step 2: Disk partitioning and mounting"
    echo "Current disk layout:"
    lsblk -p
    
    echo "Note: Please use existing partitions only"
    echo "You need to manually create partitions before running this script"
    
    # 获取分区信息
    local root_partition=""
    local swap_partition=""
    local efi_partition=""
    
    # 获取根分区
    while true; do
        read -p "Enter ROOT partition (e.g., /dev/sda1): " root_partition
        if [ -e "$root_partition" ]; then
            break
        else
            error "Partition $root_partition doesn't exist!"
            if ! confirm "Try again?"; then
                exit 1
            fi
        fi
    done
    
    # 获取交换分区
    while true; do
        read -p "Enter SWAP partition (e.g., /dev/sda2, or leave empty for no swap): " swap_partition
        if [ -z "$swap_partition" ]; then
            info "No swap partition specified"
            break
        elif [ -e "$swap_partition" ]; then
            break
        else
            error "Partition $swap_partition doesn't exist!"
            if confirm "Continue without swap?"; then
                swap_partition=""
                break
            fi
        fi
    done
    
    # 获取EFI分区（如果是UEFI模式）
    if check_uefi_support; then
        while true; do
            read -p "Enter EFI partition (e.g., /dev/sda1): " efi_partition
            efi_required=true
            if [ -e "$efi_partition" ]; then
                break
            else
                error "Partition $efi_partition doesn't exist!"
                if ! confirm "Try again?"; then
                    exit 1
                fi
            fi
        done
    else
        info "BIOS mode - no EFI partition needed"
        efi_required=false
    fi
    
    # 显示分区选择
    info "Partition selection:"
    info "Root: $root_partition"
    info "Swap: ${swap_partition:-none}"
    if [ "$efi_required" = true ]; then
        info "EFI: $efi_partition"
    fi
    
    # 开始格式化和挂载
    if ! confirm "Proceed with formatting and mounting?"; then
        error "Cancelled"
        exit 1
    fi
    
    # 准备根分区
    if ! check_and_format_partition "$root_partition" "btrfs" "/mnt"; then
        error "Failed to prepare root"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    info "Mounting root..."
    if ! mount -t btrfs -o compress=zstd "$root_partition" /mnt; then
        error "Failed to mount $root_partition"
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
    
    if ! mount -t btrfs -o subvol=/@,compress=zstd "$root_partition" /mnt; then
        error "Failed to remount root"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    mkdir -p /mnt/home
    if ! mount -t btrfs -o subvol=/@home,compress=zstd "$root_partition" /mnt/home; then
        error "Failed to mount home"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    # 准备EFI分区
    if [ "$efi_required" = true ]; then
        if ! check_and_format_partition "$efi_partition" "vfat" "/mnt/boot/efi"; then
            error "Failed to prepare EFI"
            if ! confirm "Continue?"; then
                exit 1
            fi
        fi
        
        mkdir -p /mnt/boot/efi
        if ! mount "$efi_partition" /mnt/boot/efi; then
            error "Failed to mount EFI"
            if ! confirm "Continue?"; then
                exit 1
            fi
        fi
    else
        info "Skipping EFI for BIOS"
    fi
    
    # 准备交换分区
    if [ -n "$swap_partition" ]; then
        if ! check_and_format_partition "$swap_partition" "swap" "swap"; then
            error "Failed to prepare swap"
            if ! confirm "Continue without swap?"; then
                exit 1
            fi
        else
            if ! swapon "$swap_partition"; then
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
    info "Step 3: Configuring mirrors"
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
    info "Step 4: Installing base system"
    
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
    if ! pacstrap /mnt vim sudo bash-completion networkmanager $ucode_package --noconfirm; then
        error "Failed to install tools"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    success "Base system installed"
}

generate_fstab() {
    info "Generating fstab..."
    if ! genfstab -U /mnt > /mnt/etc/fstab; then
        error "Failed to generate fstab"
        if ! confirm "Continue?"; then
            exit 1
        fi
    fi
    
    local swap_uuid=$(blkid -s UUID -o value "$swap_partition")
    if [ -n "$swap_uuid" ]; then
        info "Adding swap to fstab: $swap_uuid"
        echo "UUID=$swap_uuid none swap defaults 0 0" >> /mnt/etc/fstab
    else
        warn "No swap UUID"
    fi
    
    success "fstab generated"
    info "fstab:"
    cat /mnt/etc/fstab
}

chroot_setup() {
    info "Step 5: Chroot configuration"
    
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

info "Setting hostname..."
echo "archlinux" > /etc/hostname

info "Setting timezone..."
if ! ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; then
    error "Failed to set timezone"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

if ! hwclock --systohc; then
    error "Failed to set clock"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

info "Setting locale..."
if ! sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen; then
    error "Failed to enable en_US"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

if ! sed -i 's/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen; then
    error "Failed to enable zh_CN"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

if ! locale-gen; then
    error "Failed to generate locales"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

echo "LANG=en_US.UTF-8" > /etc/locale.conf

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
if ! pacman -S grub efibootmgr os-prober --noconfirm; then
    error "Failed to install bootloader"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

install_bootloader() {
    info "Installing bootloader..."
    
    if [[ -d /sys/firmware/efi ]]; then
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
    
    read -p "Enter disk for BIOS (e.g., /dev/sda): " bios_disk
    
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
if grep -q "AuthenticAMD" /proc/cpuinfo; then
    watchdog_blacklist="modprobe.blacklist=sp5100_tco"
    info "AMD CPU, using sp5100_tco"
else
    watchdog_blacklist="modprobe.blacklist=iTCO_wdt"
    info "Intel CPU, using iTCO_wdt"
fi

if read -p "Add watchdog blacklist? (y/N): " -n 1 -r && [[ $REPLY =~ ^[Yy]$ ]]; then
    if ! sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=5 nowatchdog $watchdog_blacklist\"/" /etc/default/grub; then
        error "Failed to modify GRUB"
    fi
else
    if ! sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=5"/' /etc/default/grub; then
        error "Failed to modify GRUB"
    fi
fi

if ! sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub; then
    error "Failed to enable OS prober"
fi

info "Generating GRUB config..."
if ! grub-mkconfig -o /boot/grub/grub.cfg; then
    error "Failed to generate GRUB"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

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
    
    cat > /mnt/root/setup2.sh << 'EOF'
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

echo "========================================"
echo "     Phase 2 Setup"
echo "========================================"

info "Need network connection"
info "Connect WiFi:"
echo "1. nmcli dev wifi connect 'SSID' password 'password'"
echo "2. nmtui"
echo ""
read -p "Press Enter after connecting..."

if ! ping -c 3 -W 3 archlinux.org &> /dev/null; then
    warn "No network"
    if ! confirm "Continue without network?"; then
        exit 1
    fi
fi

info "Auto detecting graphics..."
gpu_detected=false
amd_gpu=false

if lspci | grep -i "VGA" | grep -i "Intel" &> /dev/null; then
    info "Intel graphics detected"
    if pacman -S xf86-video-intel --noconfirm; then
        success "Intel driver installed"
        gpu_detected=true
    else
        error "Intel driver failed"
    fi
fi

if lspci | grep -i "VGA" | grep -i "AMD" &> /dev/null; then
    info "AMD graphics detected"
    if pacman -S xf86-video-amdgpu --noconfirm; then
        success "AMD driver installed"
        gpu_detected=true
        amd_gpu=true
    else
        error "AMD driver failed"
    fi
fi

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

# 桌面环境选择
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

# 如果是AMD显卡，安装Vulkan支持
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

info "Creating user..."
read -p "Enter username: " username
if ! useradd -m -g wheel "$username"; then
    error "Failed to create user $username"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

echo "Set password for $username:"
if ! passwd "$username"; then
    error "Failed to set password"
    if ! confirm "Continue?"; then
        exit 1
    fi
fi

info "Configuring sudo..."
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

info "Configuring archlinuxcn..."
cat >> /etc/pacman.conf << 'ENDOFFILE'

[archlinuxcn]
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

cat > "$desktop_dir/setup3.sh" << 'SCRIPT_EOF'
#!/bin/bash

if ! grep -q "Arch\|Manjaro" /etc/os-release; then
    echo "错误：只适用于Arch Linux及其衍生版"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "需要sudo权限"
    exit 1
fi

if [ -f "/root/setup2.sh" ]; then
    echo "删除第二阶段脚本 /root/setup2.sh"
    rm -f /root/setup2.sh
fi

echo "开始安装..."

echo "安装网络管理工具..."
pacman -S --noconfirm network-manager-applet dnsmasq

echo "安装音频软件..."
pacman -S --needed --noconfirm sof-firmware alsa-firmware alsa-ucm-conf

echo "安装pipewire..."
pacman -S --needed --noconfirm pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber

echo "启用pipewire..."
sudo -u $SUDO_USER systemctl --user enable --now pipewire pipewire-pulse wireplumber

echo "启用蓝牙..."
systemctl enable --now bluetooth

echo "安装fcitx5..."
pacman -S --noconfirm fcitx5-im fcitx5-chinese-addons

echo "配置环境变量..."
if ! grep -q "GTK_IM_MODULE=fcitx5" /etc/environment; then
    echo "GTK_IM_MODULE=fcitx5" >> /etc/environment
fi

if ! grep -q "QT_IM_MODULE=fcitx5" /etc/environment; then
    echo "QT_IM_MODULE=fcitx5" >> /etc/environment
fi

if ! grep -q "XMODIFIERS=@im=fcitx5" /etc/environment; then
    echo "XMODIFIERS=@im=fcitx5" >> /etc/environment
fi

echo "基本完成！"

# 询问安装额外软件
read -p "安装图形化声音管理工具 (pavucontrol)? (y/n): " install_pavucontrol
if [[ $install_pavucontrol =~ ^[Yy]$ ]]; then
    echo "安装pavucontrol..."
    pacman -S --noconfirm pavucontrol
fi

read -p "安装画图工具 (krita)? (y/n): " install_krita
if [[ $install_krita =~ ^[Yy]$ ]]; then
    echo "安装krita..."
    pacman -S --noconfirm krita
fi

read -p "安装视频剪辑工具 (kdenlive)? (y/n): " install_kdenlive
if [[ $install_kdenlive =~ ^[Yy]$ ]]; then
    echo "安装kdenlive..."
    pacman -S --noconfirm kdenlive
fi

libreoffice_installed=false

read -p "启用性能模式？(y/n): " enable_performance
if [[ $enable_performance =~ ^[Yy]$ ]]; then
    echo "安装性能模式..."
    pacman -S --noconfirm power-profiles-daemon
    systemctl enable --now power-profiles-daemon
fi

read -p "安装Firefox？(y/n): " install_firefox
if [[ $install_firefox =~ ^[Yy]$ ]]; then
    echo "安装Firefox..."
    pacman -S --noconfirm firefox firefox-i18n-zh-cn
fi

read -p "安装Zen浏览器？(y/n): " install_zen
if [[ $install_zen =~ ^[Yy]$ ]]; then
    echo "安装Zen..."
    pacman -S --noconfirm zen-browser zen-browser-i18n-zh-cn
fi

read -p "安装LibreOffice稳定版？(y/n): " install_libreoffice_still
if [[ $install_libreoffice_still =~ ^[Yy]$ ]]; then
    echo "安装LibreOffice稳定版..."
    pacman -S --noconfirm libreoffice-still libreoffice-still-zh-cn
    libreoffice_installed=true
fi

if [[ $libreoffice_installed == false ]]; then
    read -p "安装LibreOffice最新版？(y/n): " install_libreoffice_fresh
    if [[ $install_libreoffice_fresh =~ ^[Yy]$ ]]; then
        echo "安装LibreOffice最新版..."
        pacman -S --noconfirm libreoffice-fresh libreoffice-fresh-zh-cn
    fi
fi

echo "所有完成！"
echo "某些设置需要重启"
echo "输入法可能需要重新登录"
SCRIPT_EOF

chmod +x "$desktop_dir/setup3.sh"
chown -R "$username:wheel" "$desktop_dir"

success "Desktop script at $desktop_dir/setup3.sh"

success "Setup done!"
echo ""
echo "Next:"
echo "1. reboot"
echo "2. Login as $username"
echo "3. Run /Desktop/setup3.sh"
EOF

    chmod +x /mnt/root/setup2.sh
    success "Phase 2 script created"
}

main() {
    info "Starting Arch install..."
    
    if ! confirm "Start Arch installation?"; then
        info "Cancelled"
        exit 0
    fi
    
    connect_wifi
    setup_disk
    setup_mirrors
    install_system
    generate_fstab
    chroot_setup
    
    rm -f /mnt/root/chroot_setup.sh
    
    setup2
    
    success "========================================"
    success "     Phase 1 Complete!"
    success "========================================"
    
    info "Unmounting partitions..."
    sleep 3

    # 第一次尝试正常卸载
    if umount -R /mnt; then
        success "Unmounted successfully"
    else
        warn "First unmount attempt failed, waiting 3 seconds and retrying..."
        sleep 3
    
        # 第二次尝试正常卸载
        if umount -R /mnt; then
            success "Unmounted successfully on second attempt"
        else
            warn "Second unmount attempt failed, trying force unmount..."
            sleep 2
        
            # 第三次尝试强制卸载
            if umount -R -f /mnt; then
                success "Force unmount successful"
            else
                error "All unmount attempts failed"
                warn "This may indicate that some processes are still using the mounted filesystems"
                info "You can check with: fuser -mv /mnt"
                info "Or try manually: lsof /mnt"
            
                if confirm "Try to kill processes using mounted filesystems and retry?"; then
                    # 尝试终止使用挂载点的进程
                    fuser -k /mnt
                    sleep 2
                
                    if umount -R -f /mnt; then
                        success "Unmounted after killing processes"
                    else
                        error "Still cannot unmount after killing processes"
                        warn "Manual intervention required before reboot"
                        info "Please check mounted partitions: mount | grep /mnt"
                        info "And processes using them: fuser -mv /mnt"
                    
                        if ! confirm "Reboot despite unmount failures? (NOT RECOMMENDED - may cause data loss)"; then
                            exit 1
                        fi
                    fi
                else
                    if ! confirm "Reboot despite unmount failures? (NOT RECOMMENDED - may cause data loss)"; then
                        exit 1
                    fi
                fi
            fi
        fi
    fi
    
    info "Turning off swap..."
    swapoff -a
    
    info "Phase 1 done!"
    echo ""
    info "After reboot:"
    echo "- Login as root(Run root)"
    echo "- Run: /root/setup2.sh(bash /root/setup2.sh)"
    echo ""
    warn "Remove installation media!"
    
    if confirm "Reboot now to test GRUB?"; then
        info "Rebooting..."
        reboot
    else
        info "Reboot manually later"
    fi
}

main