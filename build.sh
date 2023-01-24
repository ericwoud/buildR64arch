#!/bin/bash

# xz -e -k -9 -C crc32 $$< --stdout > $$@

ALARM_MIRROR="http://de.mirror.archlinuxarm.org"

QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v5.2.0-11/x86_64_qemu-aarch64-static.tar.gz"

ARCHBOOTSTRAP="https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL="https://github.com/ericwoud/buildR64arch/releases/download/packages"

KERNELDTB="mt7622-bananapi-bpi-r64"

ATFDEVICE="sdmmc"
#ATFDEVICE="emmc"

KERNELBOOTARGS="console=ttyS0,115200 rw rootwait audit=0"

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
# On f2fs it is used for wanted-sector-size, but sector size is stuck at 512
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When the SD card was brand new, formatted by the manufacturer, parted shows partition start at 4MiB
# 1      4,00MiB  29872MiB  29868MiB  primary  fat32        lba
# Also, once runnig on BPIR64 execute:
# bc -l <<<"$(cat /sys/block/mmcblk1/device/preferred_erase_size) /1024 /1024"
# bc -l <<<"$(cat /sys/block/mmcblk1/queue/discard_granularity) /1024 /1024"
SD_ERASE_SIZE_MB=4                   # in Mega bytes

ATF_END_KB=1024                   # End of atf partition
MINIMAL_SIZE_FIP_MB=62             # Minimal size of fip partition

ROOTFS_LABEL="BPI-ROOT"

NEEDED_PACKAGES="base hostapd openssh wireless-regdb iproute2 nftables f2fs-tools dtc mkinitcpio patch sudo"
EXTRA_PACKAGES="vim nano screen"
PREBUILT_PACKAGES="bpir64-atf-git linux-bpir64-git linux-bpir64-git-headers bpir64-mkimage yay mmc-utils-git"
SCRIPT_PACKAGES="wget ca-certificates udisks2 parted gzip bc f2fs-tools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison "

SETUP="RT"   # Setup as RouTer
#SETUP="AP"  # Setup as Access Point

TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"                      # Root password

[ -f "./override.sh" ] && source ./override.sh

export LC_ALL=C
export LANG=C
export LANGUAGE=C

function finish {
  if [ -v rootfsdir ] && [ ! -z $rootfsdir ]; then
    $sudo sync
    echo Running exit function to clean up...
    $sudo sync
    echo $(mountpoint $rootfsdir)
    while [[ $(mountpoint $rootfsdir) =~  (is a mountpoint) ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo umount -R $rootfsdir
      sleep 0.1
    done
    $sudo rm -rf $rootfsdir
    $sudo sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
  [ -v sudoPID ] && kill -TERM $sudoPID
}

function waitdevlink {
  while [ ! -L "$1" ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function formatsd {
  echo ROOTDEV: $rootdev
  realrootdev=$(lsblk -prno pkname $rootdev)
  [ -z $realrootdev ] && exit
  [ "$l" = true ] && skip="" || skip='\|^loop'
  readarray -t options < <(lsblk --nodeps -no name,serial,size \
                    | grep -v "^"${realrootdev/"/dev/"/}$skip \
                    | grep -v 'boot0 \|boot1 \|boot2 ')
  PS3="Choose device to format: "
  select dev in "${options[@]}" "Quit" ; do
    if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
      break
    else exit
    fi
  done
  device="/dev/"${dev%% *}
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do $sudo umount $PART; done
  $sudo parted -s "${device}" unit MiB print
  echo -e "\nAre you sure you want to format "$device"???"
  read -p "Type <format> to format: " prompt
  [[ $prompt != "format" ]] && exit
  minimalrootstart=$(( $ATF_END_KB + ($MINIMAL_SIZE_FIP_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$rootstart status=progress
  $sudo sync
  $sudo partprobe "${device}"
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary $rootstart 100% \
    mkpart primary $ATF_END_KB $rootstart \
    mkpart primary 0% $ATF_END_KB \
    name 1 bpir64-${ATFDEVICE}-root \
    name 2 bpir64-${ATFDEVICE}-fip \
    name 3 bpir64-${ATFDEVICE}-atf \
    print
  $sudo partprobe "${device}"
  waitdevlink "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root"
  $sudo blkdiscard -fv "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root"
  waitdevlink "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root"
  nrseg=$(( $SD_ERASE_SIZE_MB / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
  $sudo mkfs.f2fs -w $(( $SD_BLOCK_SIZE_KB * 1024 )) -s $nrseg \
                  -f -l $ROOTFS_LABEL "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root"
  $sudo sync
  if [ -b ${device}"boot0" ] && [ $bpir64 == "true" ]; then
    $sudo mmc bootpart enable 7 1 ${device}
  fi
  $sudo lsblk -o name,mountpoint,label,partlabel,size,uuid "${device}"
}

function bootstrap {
  if [ ! -d "$rootfsdir/etc" ]; then
    rm -f /tmp/downloads/$(basename $ARCHBOOTSTRAP)
    wget --no-verbose $ARCHBOOTSTRAP --no-clobber -P /tmp/downloads/
    $sudo bash /tmp/downloads/$(basename $ARCHBOOTSTRAP) -q -a aarch64 \
          -r $ALARM_MIRROR $rootfsdir #####  2>&0
    ls -al $rootfsdir
  fi
}

function rootfs {
  $sudo mkdir -p $rootfsdir/boot/bootcfg/
  $sudo cp -rf --dereference -v ./rootfs/boot $rootfsdir
  echo /boot/Image |                                  $sudo tee $rootfsdir/boot/bootcfg/linux
  echo /boot/initramfs-linux-bpir64-git.img |         $sudo tee $rootfsdir/boot/bootcfg/initrd
  echo ${KERNELDTB} |                                 $sudo tee $rootfsdir/boot/bootcfg/dtb
  echo $KERNELBOOTARGS |                              $sudo tee $rootfsdir/boot/bootcfg/cmdline
  echo ${ATFDEVICE} |                                 $sudo tee $rootfsdir/boot/bootcfg/device
  echo "--- Following packages are installed:"
  $schroot pacman -Qe
  echo "--- End of package list"
  $schroot pacman-key --init
  $schroot pacman-key --populate archlinuxarm
  $schroot pacman-key --recv-keys $REPOKEY
  $schroot pacman-key --finger     $REPOKEY
  $schroot pacman-key --lsign-key $REPOKEY
  if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
    echo -e "\n[ericwoud]\nServer = $REPOURL\nServer = $BACKUPREPOURL" | \
               $sudo tee -a $rootfsdir/etc/pacman.conf
  fi
  $schroot pacman -Syu --needed --noconfirm $NEEDED_PACKAGES $EXTRA_PACKAGES $PREBUILT_PACKAGES
  $schroot useradd --create-home --user-group \
               --groups audio,games,log,lp,optical,power,scanner,storage,video,wheel \
               -s /bin/bash $USERNAME
  echo $USERNAME:$USERPWD | $schroot chpasswd
  echo      root:$ROOTPWD | $schroot chpasswd
  echo "%wheel ALL=(ALL) ALL" | $sudo tee $rootfsdir/etc/sudoers.d/wheel
  $schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  $sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*UsePAM.*/UsePAM no/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*#IgnorePkg.*/IgnorePkg = bpir64-atf-git/' $rootfsdir/etc/pacman.conf
  $sudo cp -rfv --dereference rootfs/. $rootfsdir
  $sudo rm -rf $rootfsdir/etc/systemd/network
  $sudo mv -vf $rootfsdir/etc/systemd/network-$SETUP $rootfsdir/etc/systemd/network
  $sudo rm -rf $rootfsdir/etc/systemd/network-*
  $schroot systemctl reenable systemd-timesyncd.service
  $schroot systemctl reenable sshd.service
  $schroot systemctl reenable systemd-resolved.service
  $schroot systemctl reenable hostapd.service
  if [ $SETUP == "RT" ]; then $schroot systemctl reenable nftables.service
  else                        $schroot systemctl disable nftables.service
  fi
  $schroot systemctl reenable systemd-networkd.service
  find -L "rootfs/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done
  if [ ! -f "$rootfsdir/etc/mac.eth0.txt" ] || [ ! -f "$rootfsdir/etc/mac.eth1.txt" ]; then
    nr=16 # Make sure there are 16 available mac addresses: nr=16/32/64
    first=AA:BB:CC
    mac5=$first:$(printf %02X $(($RANDOM%256))):$(  printf %02X $(($RANDOM%256)))
    mac=$mac5:$(printf %02X $(($(($RANDOM%256))&-$nr)))
    echo $mac $nr | $sudo tee $rootfsdir/etc/mac.eth0.txt
    mac=$mac5
    while [ "$mac" == "$mac5" ]; do # make sure second mac is different
      mac=$first:$(printf %02X $(($RANDOM%256))):$(printf %02X $(($RANDOM%256)))
    done
    mac=$mac:$(printf %02X $(($RANDOM%256)) )
    echo $mac | $sudo tee $rootfsdir/etc/mac.eth1.txt
  else echo "Macs on eth0 and eth1 already configured."
  fi
}

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  $schroot
}

function installscript {
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes         $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN
  else
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX
  fi
  # On all linux's
  if [ $bpir64 != "true" ]; then # Not running on BPI-R64
    wget --no-verbose $QEMU          --no-clobber -P ./
    $sudo tar -xf $(basename $QEMU) -C /usr/local/bin
    S1=':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/local/bin/qemu-aarch64-static:CF'
    echo -n $S1$S2| $sudo tee /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    echo
    $sudo systemctl restart systemd-binfmt.service
  fi
  if [ -z "$(cat /etc/resolv.conf | grep -oP '^nameserver')" ]; then
    echo "nameserver 8.8.8.8" | $sudo tee -a /etc/resolv.conf
  fi
  exit
}
function removescript {
  # On all linux's
  if [ $bpir64 != "true" ]; then # Not running on BPI-R64
    $sudo rm -f /usr/local/bin/qemu-aarch64-static
    $sudo rm -f /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}

[ $USER = "root" ] && sudo="" || sudo="sudo"
[[ $# == 0 ]] && args="-c"|| args=$@
echo "BASH_SOURCE: ${BASH_SOURCE[0]}"
cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
while getopts ":ralcRASD" opt $args; do declare "${opt}=true" ; done
trap finish EXIT
shopt -s extglob

if [ -n "$sudo" ]; then
  sudo -v
  ( while true; do sudo -v; sleep 40; done ) &
  sudoPID=$!
fi

echo "Current dir:" $(realpath .)
echo "Target device="$ATFDEVICE
if [ "$(tr -d '\0' 2>/dev/null </proc/device-tree/model)" != "Bananapi BPI-R64" ]; then
  echo "Not running on Bananapi BPI-R64"
  bpir64="false"
else
  echo "Running on Bananapi BPI-R64"
  bpir64="true"
fi

[ "$a" = true ] && installscript
[ "$A" = true ] && removescript

rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
rootdev=${rootdev%% *}
if [ "$S" = true ] && [ "$D" = true ]; then formatsd; exit; fi
if [ -L "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root" ]; then
  mountdev=$(realpath "/dev/disk/by-partlabel/bpir64-${ATFDEVICE}-root")
else
  echo "Not inserted! (Maybe not matching the target device on the card)"
  exit
fi
if [ "$rootdev" == "$mountdev" ];then
  rootfsdir="" ; r="" ; R=""     # Protect root when running from it!
  schroot=""
else
  rootfsdir=/mnt/bpirootfs
  schroot="$sudo unshare --mount --fork --kill-child --pid --root=$rootfsdir"
fi

echo OPTIONS: rootfs=$r apt=$a
if [ "$R" = true ] ; then
  echo Removing rootfs...
  $sudo rm -rf $rootfsdir/*
  exit
fi
echo "SETUP="$SETUP
echo "Rootfsdir="$rootfsdir
echo "Mountdev="$mountdev

if [ ! -z $rootfsdir ]; then
  $sudo umount $mountdev
  [ -d $rootfsdir ] || $sudo mkdir $rootfsdir
  $sudo mount --source $mountdev --target $rootfsdir \
              -o exec,dev,noatime,nodiratime
  [[ $? != 0 ]] && exit
  [ "$r" = true ] && bootstrap
  $sudo mount -t proc               /proc $rootfsdir/proc
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /sys  $rootfsdir/sys
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /dev  $rootfsdir/dev
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /run  $rootfsdir/run
  [[ $? != 0 ]] && exit
  [ "$r" = true ] && rootfs
  [ "$c" = true ] && chrootfs
fi

exit

# kernelcmdline: block2mtd.block2mtd=/dev/mmcblk0p2,128KiB,MyMtd cmdlinepart.mtdparts=MyMtd:1M(mtddata)ro

# sudo dd if=/dev/zero of=~/bpir64-sdmmc.img bs=1M count=3360 status=progress
# sync
# sudo udisksctl loop-setup -f ~/bpir64-sdmmc.img
# ./build.sh -lSD
# ./build.sh -r
# ./build.sh
# rm -vrf /tmp/*
# pacman -Scc
# exit
# sudo udisksctl loop-delete --block-device /dev/loop0
# xz --keep --force --verbose ~/bpir64-sdmmc.img
