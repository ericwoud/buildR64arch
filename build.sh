#!/bin/bash

# xz -e -k -9 -C crc32 $$< --stdout > $$@

BACKUPFILE="./rootfs.tar"
#BACKUPFILE="/run/media/$USER/DATA/rootfs.tar"

ALARM_MIRROR="http://de.mirror.archlinuxarm.org"

QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v5.2.0-11/x86_64_qemu-aarch64-static.tar.gz"

ARCHBOOTSTRAP="https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL='https://github.com/ericwoud/buildRKarch/releases/download/repo-$arch'

case $TARGET in
  bpir64)
    KERNELDTB="mt7622-bananapi-bpi-r64"
    KERNELBOOTARGS="console=ttyS0,115200 rw rootwait audit=0"
    ;;
  bpir3)
    KERNELDTB="mt7986a-bananapi-bpi-r3"
    KERNELBOOTARGS="earlycon=uart8250,mmio32,0x11002000 console=ttyS0,115200 debug=7 rw rootwait audit=0"
    ;;
esac 

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
# On f2fs it is used for wanted-sector-size, but sector size is stuck at 512,
# so with the standard f2fs format does does not do anything. Just leave as is for now...
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When runnig on BPIR64 or when inserted in an /dev/mmcblkX cardreader execute:
# bc -l <<<"$(cat /sys/block/mmcblk1/device/preferred_erase_size) /1024 /1024"
# bc -l <<<"$(cat /sys/block/mmcblk1/queue/discard_granularity) /1024 /1024"
SD_ERASE_SIZE_MB=4                   # in Mega bytes

ATF_END_KB=1024                   # End of atf partition
MINIMAL_SIZE_FIP_MB=62             # Minimal size of fip partition
ROOT_END_MB=100%                     # Size of root partition
#ROOT_END_MB=$(( 4*1024  ))        # Size 4GiB 
IMAGE_SIZE_MB=7456                # Size of image
IMAGE_FILE="./bpir.img"

ROOTFS_LABEL="BPI-ROOT"

NEEDED_PACKAGES="base hostapd openssh wireless-regdb iproute2 nftables f2fs-tools dtc mkinitcpio patch sudo"
EXTRA_PACKAGES="vim nano screen"
PREBUILT_PACKAGES="bpir64-atf-git linux-bpir64-git yay mmc-utils-git"
SCRIPT_PACKAGES="wget ca-certificates udisks2 parted gzip bc f2fs-tools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison "

TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"                      # Root password

[ -f "./override.sh" ] && source ./override.sh

export LC_ALL=C
export LANG=C
export LANGUAGE=C

function finish {
  trap 'echo got SIGINT' INT
  trap 'echo got SIGEXIT' EXIT
  [ -v noautomountrule ] && $sudo rm -vf $noautomountrule
  if [ -v rootfsdir ] && [ ! -z "$rootfsdir" ]; then
    $sudo sync
    echo Running exit function to clean up...
    $sudo sync
    echo $(mountpoint $rootfsdir)
    while [[ "$(mountpoint $rootfsdir)" =~ "is a mountpoint" ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo umount -R $rootfsdir
      sleep 0.1
    done
    $sudo rm -rf $rootfsdir
    $sudo sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
  if [ -v loopdev ] && [ ! -z "$loopdev" ]; then
    $sudo losetup -d $loopdev
  fi
  unset loopdev
  [ -v sudoPID ] && kill -TERM $sudoPID
}

function waitdevlink {
  while [ ! -L "$1" ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function reinsert {
  sync
  bindpart=$(basename $(realpath /sys/block/$1/../..))
  driver=$(realpath /sys/block/$1/device/driver)
  echo -n $bindpart | $sudo tee $driver/unbind
  echo -e "\nRe-inserting" $1
  sleep 0.1
  echo -n $bindpart | $sudo tee $driver/bind
  echo
  newdev=$(ls $driver/$bindpart/block | head -1)
  echo "New Block Device: "$newdev
  until lsblk /dev/$newdev >/dev/null 2>/dev/null; do sleep 0.1; done
  $sudo partprobe "/dev/"$newdev
  sync
}

function formatsd {
  echo ROOTDEV: $rootdev
  pkroot=$(lsblk -rno pkname $rootdev)
  [ -z $pkroot ] && exit
  minimalrootstart=$(( $ATF_END_KB + ($MINIMAL_SIZE_FIP_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  if [[ "$ROOT_END_MB" =~ "%" ]]; then
    root_end_kb=$ROOT_END_MB
  else
    root_end_kb=$(( ($ROOT_END_MB/$SD_ERASE_SIZE_MB*$SD_ERASE_SIZE_MB)*1024))
    echo $root_end_kb
  fi
  if [ "$l" = true ]; then
    device=$loopdev
    pkdev=${device/"/dev/"/""}
  else
    readarray -t options < <(lsblk --nodeps -no name,serial,size \
                       | grep -v "^"${pkroot} \
                      | grep -v 'boot0 \|boot1 \|boot2 ')
    PS3="Choose device to format: "
    select dev in "${options[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
    done
    pkdev=${dev%% *}
    device="/dev/"$pkdev
  fi
  echo -n 'KERNELS=="'${pkdev}'", ENV{UDISKS_IGNORE}="1"' | $sudo tee $noautomountrule
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do $sudo umount $PART; done
  $sudo parted -s "${device}" unit MiB print
  echo -e "\nAre you sure you want to format "$device"???"
  read -p "Type <format> to format: " prompt
  [[ $prompt != "format" ]] && exit
  $sudo wipefs --all --force "${device}"
  $sudo dd of="${device}" if=/dev/zero bs=64kiB count=$(($rootstart/64)) status=progress
  $sudo sync
  $sudo partprobe "${device}"
  $sudo parted -s -- "${device}" mklabel gpt
  [[ $? != 0 ]] && exit
#    mkpart primary 34s 13311s \
#    mkpart primary 13312s $rootstart \
  $sudo parted -s -- "${device}" unit kiB \
    mkpart primary 34s $ATF_END_KB \
    mkpart primary $ATF_END_KB $rootstart \
    mkpart primary $rootstart $root_end_kb \
    set 1 legacy_boot on \
    name 1 ${TARGET}-${ATFDEVICE}-atf \
    name 2 ${TARGET}-${ATFDEVICE}-fip \
    name 3 ${TARGET}-${ATFDEVICE}-root \
    print
  $sudo partprobe "${device}"
  waitdevlink "/dev/disk/by-partlabel/${TARGET}-${ATFDEVICE}-root"
  $sudo blkdiscard -fv "/dev/disk/by-partlabel/${TARGET}-${ATFDEVICE}-root"
  waitdevlink "/dev/disk/by-partlabel/${TARGET}-${ATFDEVICE}-root"
  nrseg=$(( $SD_ERASE_SIZE_MB / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
  $sudo mkfs.f2fs -w $(( $SD_BLOCK_SIZE_KB * 1024 )) -s $nrseg -t 0 \
       -f -l $ROOTFS_LABEL "/dev/disk/by-partlabel/${TARGET}-${ATFDEVICE}-root"
  $sudo sync
  if [ -b ${device}"boot0" ] && [[ "$compatible" == *"bananapi"*"mediatek,mt7"* ]]; then
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

function selectdir {
  $sudo rm -rf $1
  $sudo mkdir -p $1
  [ -d $1-$2                ] && $sudo mv -vf $1-$2/*                $1
  [ -d $1-$2-${ATFDEVICE^^} ] && $sudo mv -vf $1-$2-${ATFDEVICE^^}/* $1
  $sudo rm -rf $1-*
}

function rootfs {
  $sudo mkdir -p $rootfsdir/boot/bootcfg
  $sudo cp -rfv ./rootfs/boot $rootfsdir
  selectdir $rootfsdir/boot/dtbos ${TARGET^^}
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
  for d in $(ls ./rootfs/ | grep -vx boot); do $sudo cp -rfv ./rootfs/$d $rootfsdir; done
  $sudo sed -i "s/\bdummy\b/PARTLABEL=${TARGET}-${ATFDEVICE}-root/g" $rootfsdir/etc/fstab
  selectdir $rootfsdir/etc/systemd/network ${TARGET^^}-${SETUP}
  selectdir $rootfsdir/etc/hostapd ${TARGET^^}
  if [ ! -z "$brlanip" ]; then
    $sudo sed -i 's/Address=.*/Address='$brlanip'\/24/' \
                    $rootfsdir/etc/systemd/network/10-brlan.network
  fi
  $sudo systemctl --root=$rootfsdir reenable systemd-timesyncd.service
  $sudo systemctl --root=$rootfsdir reenable sshd.service
  $sudo systemctl --root=$rootfsdir reenable systemd-resolved.service
  $sudo systemctl --root=$rootfsdir reenable hostapd.service
  if [ $SETUP == "RT" ]; then $sudo systemctl --root=$rootfsdir reenable nftables.service
  else                        $sudo systemctl --root=$rootfsdir disable nftables.service
  fi
  $sudo systemctl --root=$rootfsdir reenable systemd-networkd.service
  find -L "rootfs/etc/systemd/system" -name "*.service"| while read service ; do
    $sudo systemctl --root=$rootfsdir reenable  $(basename $service)
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

function backuprootfs {
  $sudo tar -vcf "${BACKUPFILE}" -C $rootfsdir .
}

function restorerootfs {
  if [ -z "$(ls $rootfsdir)" ] || [ "$(ls $rootfsdir)" = "boot" ]; then
    $sudo tar -vxf "${BACKUPFILE}" -C $rootfsdir
    echo "Run ./build.sh and execute 'pacman -Sy bpir64-atf-git' to write the" \
         "new atf-boot! Then type 'exit'."
  else
    echo "Root partition not empty!"
  fi
}

function installscript {
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes         $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN
  else
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX
  fi
  # On all linux's
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so install qemu
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
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so remove qemu
    $sudo rm -f /usr/local/bin/qemu-aarch64-static
    $sudo rm -f /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}

function compressimage {
  rm -f $IMAGE_FILE".xz"
  xz --keep --force --verbose $IMAGE_FILE
}

function ctrl_c() {
  echo "** Trapped CTRL-C"
  exit
}

[ $USER = "root" ] && sudo="" || sudo="sudo"
[[ $# == 0 ]] && args="-c"|| args=$@	
cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
while getopts ":ralcbRASEFBX" opt $args; do declare "${opt}=true" ; done
trap finish EXIT
trap ctrl_c INT
shopt -s extglob

if [ -n "$sudo" ]; then
  sudo -v
  ( while true; do sudo -v; sleep 40; done ) &
  sudoPID=$!
fi

echo "Current dir:" $(realpath .)
compatible="$(tr -d '\0' 2>/dev/null </proc/device-tree/compatible)"
hostarch=$(uname -m)
echo "Compatible:" $compatible
echo "Host Arch:" $hostarch

[ "$a" = true ] && installscript
[ "$A" = true ] && removescript

if [ "$X" = true ]; then compressimage; exit; fi
 
set -m # send CTRL-C to children
 
rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
rootdev=${rootdev%% *}
$sudo mkdir -p "/run/udev/rules.d"
noautomountrule="/run/udev/rules.d/10-no-automount.$$.rules"

if [ "$l" = true ]; then
  if [ ! -f $IMAGE_FILE ]; then
    dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$IMAGE_SIZE_MB status=progress
  fi	  
  loopdev=$($sudo losetup --show --find  $IMAGE_FILE)
fi 

if [ "$F" = true ]; then
  PS3="Choose target to format image for: "
  select TARGET in "bpir3  Bananapi-R3" "bpir64 Bananapi-R64" "Quit" ; do
    if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
  done
  TARGET=${TARGET%% *}
  PS3="Choose atfdevice to format image for: "
  select ATFDEVICE in "sdmmc SD Card" "emmc  EMMC onboard" "Quit" ; do
    if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
  done
  ATFDEVICE=${ATFDEVICE%% *}
  formatsd
  mountdev="/dev/disk/by-partlabel/${TARGET}-${ATFDEVICE}-root"
else
  if [ "$l" = true ]; then
    $sudo partprobe $loopdev
    mountdev=$(lsblk $loopdev -prno partlabel,name | grep -- -root | cut -d' ' -f2)
    if [ -z "$mountdev" ]; then
      echo "Not inserted! (Maybe not matching the target device on the image)"
      exit
    fi
    partlabelroot=$(lsblk -prno partlabel $mountdev)
  else
    readarray -t options < <(lsblk -prno partlabel,name,pkname | grep -P '^bpir' | grep -- -root)
    if [ ${#options[@]} -gt 1 ]; then
      PS3="Choose root partition to work on: "
      select choice in "${options[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
      done
    else
      choice=${options[0]}
    fi
    mountdev=$(echo $choice | cut -d' ' -f2)
    partlabelroot=$(echo $choice | cut -d' ' -f1)
  fi
  TARGET=$(echo $partlabelroot | cut -d'-' -f1)
  ATFDEVICE=$(echo $partlabelroot | cut -d'-' -f2)
fi

[ -z "$TARGET" ] && exit
echo "Target=${TARGET}, ATF-device="$ATFDEVICE

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi
pkdev=$(lsblk -no pkname ${mountdev})

if [ "$r" = true ]; then
  PS3="Choose setup to create root for: "
  select SETUP in "RT  Router setup" "AP  Access Point setup" "Quit" ; do
    if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
  done
  SETUP=${SETUP%% *}
  read -p "Enter ip address for local network: " brlanip
fi

rootfsdir="/tmp/bpirootfs.$$"
schroot="$sudo unshare --mount --fork --kill-child --pid --root=$rootfsdir"
echo "SETUP="$SETUP
echo "Rootfsdir="$rootfsdir
echo "Mountdev="$(realpath $mountdev)
 
echo -n 'KERNELS=="'${pkdev}'", ENV{UDISKS_IGNORE}="1"' | $sudo tee $noautomountrule
echo

$sudo umount $mountdev
[ -d $rootfsdir ] || $sudo mkdir $rootfsdir
[ "$b" = true ] && ro=",ro" || ro=""
$sudo mount --source $mountdev --target $rootfsdir \
            -o exec,dev,noatime,nodiratime$ro
[[ $? != 0 ]] && exit
 
if [ "$b" = true ] ; then backuprootfs; exit; fi
if [ "$B" = true ] ; then restorerootfs; exit; fi
if [ "$R" = true ] ; then
  read -p "Type <remove> to delete everything from the card: " prompt
  [[ $prompt != "remove" ]] && exit
  $sudo rm -rf $rootfsdir/{*,.*}
  exit
fi
 
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
