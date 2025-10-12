# Arch Installer For Chinese脚本

## 说在前面的

### 免责声明

警告：此脚本会格式化磁盘，可能导致数据丢失！

· 使用前务必备份所有数据  
· 建议先在虚拟机测试  
· 用户自行承担使用风险  
· 不提供任何担保  

继续使用即表示您理解并接受上述风险。完整的免责声明见[DISCLAIMER.md](https://github.com/SZ-XY/AIFC/blob/main/DISCLAIMER.md)  

如果是新手或者是想要进一步的用户，可以参考这份 [ArchLinux指南](https://github.com/SHORiN-KiWATA/ShorinArchExperience-ArchlinuxGuide)  
里面的步骤很详细，可以加深你对ArchLinux的理解  

## 使用方法

**1**,进入Arch安装介质(具体步骤请自行搜索)  

**2**,明确要作为根分区，交换分区和EFI分区(仅UEFI模式需要)的具体分区名称  
· 可以输入"lsblk -p"查看分区  
输出示例：  

```
NAME          MAJ:MIN RM   SIZE  RO TYPE MOUNTPOINT
/dev/sda      8:0     0    100G  0  disk           
├─/dev/sda1  8:1     0    512M  0  part 
├─/dev/sda2  8:2     0     8G   0  part [SWAP]
└─/dev/sda3  8:3     0   91.5G  0  part 
/dev/sr0      11:0    1    1.5G  0  rom  /run/archiso/bootmnt
```  
  
· 可以通过fdisk管理分区  
使用方法:  

1.启动 fdisk

```
fdisk /dev/sda  # 替换为你的磁盘设备
```

2.fdisk 常用命令(进入fdisk后执行)

基本操作命令：

```
Command (m for help): m   # 显示帮助菜单

常用命令：
  n - 创建新分区
  d - 删除分区
  p - 显示分区表
  t - 更改分区类型
  w - 保存并退出
  q - 不保存退出
```
创建新分区步骤示例：

```
fdisk /dev/sda

Command (m for help): n     
注:创建新分区，这里不用管分区类型，如果不匹配，脚本会提供格式化到指定类型

Partition number (4-128, default 4):       
注:回车使用默认,也可以输入一个在区间的数字，这里的默认数字为4，区间为 4-128

First sector (17827840-209715166, default 17827840): 
注:这里不用管，回车使用默认

Last sector, +/-sectors or +/-size{K,M,G,T,P} (17827840-209715166, default 209715166): +20G     
注:这表示创建分区的大小为20G,也可以回车使用默认(剩下的全部空间)

Command (m for help): w       
注:之前的操作并没有真正执行，输入q退出后什么也没有变化，输入w才写入，如果不确定，可以输入p验证
```

**3**,需要网络以下载aifc.sh，这里演示用iwctl连接Wi-Fi  
第一种方式(交互式)：   

1.启动 iwctl  
输入以下代码并执行  

```
iwctl
```

然后会进入交互式命令行，提示符变为 [iwd]#  

2.查看可用设备  

```
[iwd]# station list
```

输出示例：

```
                            Available stations
--------------------------------------------------------------------
  Station   State         Scanning   Name
--------------------------------------------------------------------
  wlan0     connected     no         MyWiFi
```

3.扫描网络  

```
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
```

输出示例：  

```
                               Available networks
--------------------------------------------------------------------
    Network name                    Security   Signal
--------------------------------------------------------------------
    HomeWiFi                        psk        ****
    OfficeNetwork                   psk        ****
    FreeWiFi                        open       ****
```

4.连接 WiFi

```
[iwd]# station wlan0 connect "HomeWiFi"
```

如果有密码，系统会提示输入密码：

```
Passphrase: [输入密码，输入不显示]
```
没有密码则直接连接

5.检查连接状态

```
[iwd]# station wlan0 show
```

输出示例：  

```
Station: wlan0
  State: connected
  Connected network: HomeWiFi
  IPv4 configuration: completed
```

6.退出 iwctl

```
[iwd]# exit
```

第二种方式(已知WiFi 名称和密码):  
执行以下代码：

```
iwctl --passphrase "你的密码" station wlan0 connect "WiFi名称"
```
  
  

**4,运行AIFC安装脚本**

在安装介质中输入一下代码并执行   

```
curl -LO https://github.com/SZ-XY/AIFC/releases/download/v1.00/aifc.sh && ./aifc.sh
```

## 安装流程中的用户选择点及需要的操作  

注：第一二阶段因为环境不支持显示中文，所以选项都是英文，第三阶段可以显示中文所以出现了中文

#### 第一阶段脚本中的：  
**1**. 初始确认

```
Start Arch installation? (y/N):
```

· 说明: 确认开始安装过程
· 选择: y (开始安装) 或 N (取消)

**2**. 网络连接

```
Do you want to connect to WiFi? (y/N):
```

· 说明: 询问是否连接 WiFi  
· 选择: y (连接 WiFi) 或 N (跳过)  
· 如果选择 y: 需要输入 WiFi SSID 和密码  
· 如果选择 N:将会检查是否有网络连接，这需要一点时间   

详细的连接过程：  
如果用户选择 y，进入连接流程：

```
Enter WiFi SSID: [用户输入WiFi名称]
Enter WiFi password: [用户输入密码，输入不显示]
```

注意事项：

· SSID 输入可见，密码输入不可见（安全考虑）  
· 按回车确认输入

然后是连接尝试过程

```
Connecting to [WiFi名称]...
Waiting for connection...
```

· 自动操作: 脚本使用 iwctl 命令连接   
· 等待时间: 连接后等待 5 秒让网络稳定   

连接失败重试机制

```
Connection failed (attempt 1/3)
Connection failed (attempt 2/3)  
Connection failed (attempt 3/3)
Failed to connect to WiFi after 3 attempts
```

重试策略：

· 最大重试次数：3 次，每次失败后显示当前尝试次数   
· 所有尝试失败后进入错误处理   

错误处理流程  

```
Failed to connect to WiFi after 3 attempts
Continue without network? (y/N):
```

用户选择分支：

· 选择 y: 继续无网络安装 ~~好像什么也做不了~~  

  ```
  Continuing without network
  ```
· 选择 N: 退出安装脚本  


**3**. 分区选择与格式化

3.1 分区设备选择

```
Enter ROOT partition (e.g., /dev/sda1):
```

· 说明: 输入根分区设备路径   
· 示例: /dev/sda1, /dev/nvme0n1p2

```
Enter SWAP partition (e.g., /dev/sda2, or leave empty for no swap):
```

· 说明: 输入交换分区设备路径，或留空表示不使用交换分区   
· 示例: /dev/sda2 或直接按回车跳过

```
Enter EFI partition (e.g., /dev/sda1):
```

· 说明: 仅在 UEFI 模式下显示，输入 EFI 分区设备路径   
· 示例: /dev/sda1

3.2 再次确认

```
Proceed with formatting and mounting? (y/N):
```

· 说明: 确认进行格式化和挂载操作   
· 选择: y (继续) 或 N (取消)

3.3 分区格式化确认

```
Partition /dev/xxx filesystem: [当前文件系统]
Wrong filesystem ([当前文件系统]), expected [预期文件系统]
Format /dev/xxx as [预期文件系统]? (ERASES ALL DATA!) (y/N):
```

· 说明: 当检测到分区文件系统与预期不符时的格式化确认   
· 选择: y (格式化到预期文件系统，会删除所有数据) 或 N (跳过)

```
No filesystem detected
Format /dev/xxx as [预期文件系统]? (y/N):
```

· 说明: 当分区没有检测到文件系统时的格式化到预期文件系统的确认   
· 选择: y (格式化) 或 N (跳过)


**4**. 内核选择

```
Choose kernel:
1) Mainstream stable (linux)
2) Long-term support (linux-lts)  
3) Hardened security (linux-hardened)
4) Performance optimized (linux-zen)
Enter choice (1-4):
```

· 说明: 选择要安装的 Linux 内核版本，输入数字1~4   
· 选择: 1 (稳定版), 2 (长期支持), 3 (安全强化), 4 (性能优化)

**5**. GRUB 配置

如果你是在 BIOS（传统引导）系统中，GRUB 需要安装到磁盘的主引导记录（MBR） 或分区的引导扇区(不推荐安装到分区)，这时脚本会询问你要安装到的磁盘。   
示例：   

```
[INFO] Installing bootloader...
[WARN] Trying BIOS install...
[INFO] Available disks:
NAME        SIZE TYPE
/dev/sda    100G disk
/dev/sdb    500G disk

Enter disk for BIOS (e.g., /dev/sda, not partition like /dev/sda1): /dev/sda
注：这里输入的设备是磁盘，"TYPE"这一栏显示的要是"disk"，不推荐输入分区(TYPE是part)

[INFO] Installing BIOS GRUB on /dev/sda...
Installation finished. No error reported.
[SUCCESS] BIOS GRUB installed
```
选择是否禁用watchdog:  

```
Add watchdog blacklist? (y/N):
```
   
· 说明：Watchdog（看门狗定时器）是一个硬件或软件机制，用于检测和恢复系统故障。当系统卡死时，Watchdog 会自动重启系统。   
· 这里的选择看个人，一般有人的情况下可以禁用，如你自己用时；没有人的情况下不禁用，如服务器，物联网设备   
· 选择: y (禁用) 或 N (跳过)

**6**. 阶段一结束提示

```
Phase 1 done!
After reboot:
- Login as root
- Run: /root/setup2.sh

Remove installation media!
Reboot now? (y/N):
```

· 说明: 阶段一完成，询问是否立即重启   
· 选择: y (立即重启) 或 N (稍后手动重启)   
· 并且提示在重启后登录root账户并执行阶段二安装脚本   

具体为在重启后输入root，然后再输入root密码以登录root账户：   

```
Arch Linux login: root
Password: [输入您在阶段一中设置的root密码]
```

然后运行脚本:   

```
bash /root/setup2.sh

```

#### 第二阶段脚本中的：  

**1**. 网络连接确认

```
Need network connection
Connect WiFi:
1. nmcli dev wifi connect 'SSID' password 'password'
2. nmtui

Press Enter after connecting...
```

· 操作: 如果确认有网(虚拟机中一般有，有线网络一般自动识别)或不清楚是否有网（实体机中一般没有），回车进入下一步，脚本将自动检测是否连接到网络，如果有网，会跳转到询问是否安装VMware工具，没有网络，则会弹出一下文本

```
Checking network connection...
Network check failed, retrying in 3 seconds... (1/2)
Network check failed, retrying in 3 seconds... (2/2)
Trying HTTP connection as fallback...
No reliable network connection detected
Continue without network? (y/N):
```

· 如果选择 y,脚本将继续执行，但会跳过所有需要网络的操作   
· 跳过的操作包括:   
1, VMWare Tools 安装   
2, 显卡驱动安装   
3, 桌面环境安装   
4, 软件包安装   
5, Arch Linux CN 源配置   
6, yay AUR 助手安装   
· 仍会执行的操作:   
1, 用户账户创建   
2, 基本配置文件设置   
3, 桌面脚本创建   

· 选择 N (退出安装)   
· 结果: 脚本立即退出，返回命令行   
· 然后请连接网络，如输入一下代码并回车：  

```
nmcli dev wifi connect 你的wifi名称 password 它对应的密码
```
· 或输入   

```
nmcli
```
进行图形化网络连接(用上下左右键控制)   
步骤:   
1,在输入nmtui后在主界面选择第二个选项"Activate a connection"   
2,然后选择你的Wi-Fi，回车   
3,在输入Wi-Fi所对应的密码后，回车   
4,如果连接到Wi-Fi前出现"*"号，说明连接成功，然后移动光标至"Back"(返回),回车   
5,这时又回到了nmtui的主界面，移动光标至最下面的Quit选项，回车退出   


**2**. VMware 工具安装

```
Are you running on VMWare virtual machine? (Install open-vm-tools for better integration) (y/N):
```

· 说明: 询问是否在 VMware 虚拟机中运行   
· 选择: y (安装 VMware 工具) 或 N (跳过)

**3**. 桌面环境选择

```
Choose desktop environment:
1) KDE Plasma
2) GNOME
Enter choice (1-2):
```

· 说明: 选择要安装的桌面环境   
· 选择: 1 (KDE Plasma) 或 2 (GNOME)

**4**. 用户账户设置

```
Enter username:
```

· 说明: 输入要创建的用户名   
· 要求: 只能包含小写字母、数字、- 和 _

```
Setting password for [用户名]:
```

· 说明: 为用户设置密码（需要输入两次确认）

**5**. 阶段二结束提示

```
Setup done!
Next:
1. reboot
2. Login as [用户名]
3. Run sudo /root/setup3.sh
```
· 当看到这个，说明阶段二以完成   
· 然后输入

```
reboot
```
以重启，就进入了图形界面，输入[用户名]所对应的密码来登录。  
注意：不是root账户的密码 ~~当然，如果你两个账户密码一样，我也没话说。~~

#### 设置系统语言为中文

步骤：     
1,按下"Win"键(Command)  
2,输入system setting  
3,打开出现的应用(设置)  

· 如果你安装的是KDE Plasma桌面，下滑，找到Language & Time下的 Region & Language选项     
点击进入，找到第一行Language,点击旁边的Modify选项，再点击Change Language选项   
这时会弹出来一个列表，点击"简体中文"，再点击右下角的Apply   
这时就又回到了Region & Language的主界面，上方有一个"Restart now"的选项，点击重启，再点击Restart Now立即重启，稍后进入系统，语言就为中文了。

· 如果你安装的是GNOME桌面，下滑，找到最下面的System选项，点击进入，然后点击第一行的Region & Language，再点击Language选项  
这时会弹出来一个列表，点击"汉语"，再点击右上角的Select,最后点击右上角的Log Out登出。

#### 执行第三阶段脚本

1,按下"Win"键(Command)  
2,如果是KDE Plasma桌面，输入konsole；  
如果是GNOME桌面，输入ghostty
3,再输入以下代码并执行   

```
sudo bash /root/setup3.sh
```
然后你需要输入[用户名]所对应的密码   
这个脚本将会安装一些基础应用(具体见自动配置内容)   


#### 第三阶段脚本中的选项：  


**1** 引导程序

```
是否为UEFI多系统用户安装rEFInd引导程序？(y/n):
```

· 说明: 仅在 UEFI 系统显示，询问是否安装 rEFInd    
· 选择: y (安装) 或 n (跳过)

**2** 额外拓展

```
是否开启32位软件支持（multilib）？(y/n):
是否安装文泉驿正黑字体和Noto表情符号字体？(y/n):
是否安装图形化声音管理工具 (pavucontrol)？(y/n):
是否安装画图工具 (krita)？(y/n):
是否安装视频剪辑工具 (kdenlive)？(y/n):
是否启用性能模式？(y/n):
是否安装 Firefox 浏览器？(y/n):
是否安装 Zen 浏览器？(y/n):
是否安装 LibreOffice 稳定版？(y/n):
是否安装 LibreOffice 最新版？(y/n):
```

· 说明: 一系列可选软件和功能的安装确认   
· 选择: 对每个选项选择 y (安装) 或 n (跳过)

## 自动配置内容

#### 系统基础配置

1.脚本环境准备   

· 自动检测运行环境：如果从 /mnt 目录运行，自动复制到 /tmp 执行   
· 临时文件管理：自动创建和清理临时脚本文件   
· 错误处理机制：设置 set -e 和错误清理陷阱   

2.系统检测与初始化   
   
· UEFI/BIOS 自动检测：检查 /sys/firmware/efi 目录    
· CPU 类型检测：自动识别 Intel 或 AMD 处理器   
· efivarfs 自动挂载：在 UEFI 模式下自动挂载 EFI 变量文件系统   

3.网络配置   

· 网络连接验证：自动测试多个主机（archlinux.org, baidu.com）   
· 备用 HTTP 检查：当 ping 被阻挡时使用 HTTP 连接验证   
· 网络重试机制：失败时自动重试 2 次   

#### 文件系统与分区

1.自动安装Btrfs文件系统  
以下是Btrfs 子卷配置:  

```
# 自动创建的子卷结构
btrfs subvolume create /mnt/@      # 根子卷
btrfs subvolume create /mnt/@home  # 家目录子卷
```

2.挂载选项优化

· 根分区：subvol=/@,compress=zstd   
· 家目录：subvol=/@home,compress=zstd   
· 自动压缩：启用 zstd 压缩算法   

3.分区验证与清理

· 分区卸载验证：自动卸载和检查分区使用状态   
· 交换分区管理：自动关闭和重新激活交换分区   
· fstab 自动清理：移除重复条目和无效挂载点   

#### 软件包与镜像配置

1.镜像源自动配置

```
# 自动配置的中国镜像源
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch
Server = https://mirrors.ustc.edu.cn/archlinux/$repo/os/$arch  
Server = https://mirrors.aliyun.com/archlinux/$repo/os/$arch
```

2.基础软件包安装

· 内核固件：linux-firmware   
· 文件系统工具：btrfs-progs   
· 中文字体：noto-fonts-cjk   
· 开发工具：base-devel   
· 系统工具：vim, sudo, bash-completion, git   

3.网络工具安装

· 网络管理：networkmanager, iwd, dhcpcd, dhclient   
· 连接工具：完整的网络管理套件   

#### 系统服务配置

1.引导程序配置

· GRUB 自动安装：根据 UEFI/BIOS 自动选择安装方式   
· OS Prober 启用：自动检测其他操作系统   
· Btrfs 支持：自动添加 Btrfs 模块到 GRUB   

2.系统本地化

```
# 自动配置的本地化设置
hostname: archlinux
timezone: Asia/Shanghai
locale: en_US.UTF-8 + zh_CN.UTF-8
```

3.服务自动启用

· NetworkManager：网络管理服务   
· 显示管理器：根据桌面选择自动启用 SDDM 或 GDM   

#### 桌面环境配置

1.图形驱动自动检测

· Intel 显卡：自动安装 xf86-video-intel   
· AMD 显卡：自动安装 xf86-video-amdgpu   
· Intel Xe核显：检测并安装 intel-media-driver   
· AMD 780M 系列：自动安装 libva-mesa-driver   

2.Vulkan 支持

· AMD GPU：自动安装 vulkan-radeon   

3.桌面组件

· KDE Plasma：   
安装了:     

```
plasma-meta                    # KDE Plasma 桌面环境核心组件
sddm                           # KDE Plasma 显示管理器
kde-system-meta                # KDE 系统工具集合
kde-utilities-meta             # KDE 实用工具集合
flatpak                        # 应用程序容器平台
```
· GNOME：
安装了：  

``` 
gnome-desktop                 # GNOME 桌面环境核心组件
gdm                           # GNOME 显示管理器
ghostty                       # 现代终端模拟器
gnome-software                # 软件中心
gnome-text-editor             # 文本编辑器
gnome-disk-utility            # 磁盘工具
gnome-clocks                  # 时钟应用
gnome-calculator              # 计算器
fragments                     # 文件分享工具
flatpak                       # 应用程序容器平台
```

#### AUR 和社区源

1.Arch Linux CN 配置

```
# 自动添加的 archlinuxcn 源
[archlinuxcn]
Server = https://mirrors.ustc.edu.cn/archlinuxcn/$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
Server = https://mirrors.hit.edu.cn/archlinuxcn/$arch  
Server = https://repo.huaweicloud.com/archlinuxcn/$arch
```

2.AUR 助手

· yay：自动安装和配置    
· 密钥环：自动安装 archlinuxcn-keyring

#### 音频系统配置

1.PipeWire 音频栈

· 核心组件：pipewire, pipewire-pulse, pipewire-alsa, pipewire-jack    
· 会话管理：wireplumber   
· 服务启用：自动为用户启用 PipeWire 服务   

2.固件和驱动

· 声音固件：sof-firmware, alsa-firmware, alsa-ucm-conf   
· 蓝牙支持：自动启用蓝牙服务   

#### 显示管理器配置

1.SDDM 自动配置（KDE）

· 目录权限：自动设置 /var/lib/sddm 权限   
· 配置文件：自动创建完整的 SDDM 配置   
· 服务管理：自动启用和启动服务   

2.权限修复

· 用户目录：自动创建桌面目录并设置权限   
· 脚本权限：自动设置阶段脚本的执行权限  

#### 输入法与本地化

1.中文输入法

· Fcitx5：完整的中文输入法框架  
· 环境变量：自动配置 GTK、QT 输入法模块  

2.系统环境

```
# 自动设置的环境变量
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5  
XMODIFIERS=@im=fcitx5
```

#### 权限与用户配置

1. 用户权限

· sudo 配置：自动为 wheel 组配置 sudo 权限  
· 用户组：自动将用户添加到 wheel 组  

2. 系统优化

· 性能模式：可选安装 power-profiles-daemon  
· 交换分区：自动配置和启用  

#### 安装流程管理

1. 阶段脚本创建

· 阶段二脚本：自动创建 /root/setup2.sh  
· 阶段三脚本：自动创建 /root/setup3.sh  
· 桌面快捷方式：自动创建用户桌面说明文件  

2. 清理与验证

· 文件系统验证：自动验证 fstab 配置  
· 服务状态检查：验证关键服务状态  
· 安装清理：自动清理临时文件
