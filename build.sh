#!/bin/bash

# Set default configuration values
# These can be overridden by entering them into config.sh

ALARM_MIRROR="http://eu.mirror.archlinuxarm.org"

QEMU_AARCH64="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static.tar.gz"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL='https://github.com/ericwoud/buildRKarch/releases/download/repo-$arch'

# Standard erase size, when it cannot be determined (using /dev/sdX cardreader or loopdev)
SD_ERASE_SIZE_MB=4             # in Mega bytes

ATF_END_KB=1024                # End of atf partition
MINIMAL_SIZE_FIP_MB=190        # Minimal size of fip partition
ROOT_END_MB=100%               # Size of root partition
#ROOT_END_MB=$(( 4*1024  ))    # Size 4GiB
IMAGE_SIZE_MB=7456             # Size of image
IMAGE_FILE="./bpir.img"        # Name of image

NEEDED_PACKAGES="base dbus-broker-units hostapd openssh wireless-regdb iproute2 nftables f2fs-tools dosfstools\
 btrfs-progs dtc mkinitcpio patch sudo evtest parted"
EXTRA_PACKAGES="vim nano screen i2c-tools ethtool"
PREBUILT_PACKAGES="bpir-atf-git mmc-utils-git peekpoke-git ssh-fix-reboot hostapd-launch"
SCRIPT_PACKAGES="curl ca-certificates udisks2 parted gzip bc f2fs-tools dosfstools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison"

TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"                      # Root password

TARGETS=("bpir64 Bananapi-R64"
         "bpir3  Bananapi-R3"
         "bpir3m Bananapi-R3-Mini"
         "bpir4  Bananapi-R4")

function setupenv {
#BACKUPFILE="/run/media/$USER/DATA/${target}-${atfdevice}-rootfs.tar"
BACKUPFILE="./${target}-${atfdevice}-rootfs.tar"
arch='aarch64'
PREBUILT_PACKAGES+=' '"linux-${target}-git"
case ${target} in
  bpir64)
    SETUPBPIR=("RT       Router setup"
               "RTnoAUX  Router setup, not using aux port (dsa port 5)"
               "AP       Access Point setup")
    WIFIMODULE="mt7615e"
    ;;
  bpir3)
    SETUPBPIR=("RT       Router setup, SFP module eth1 as wan"
               "RTnoSFP  Router setup, not using SFP module"
               "AP       Access Point setup")
    WIFIMODULE="mt7915e"
    ;;
  bpir3m)
    SETUPBPIR=("RT       Router setup"
               "AP       Access Point setup")
    WIFIMODULE="mt7915e"
    ;;
  bpir4)
    SETUPBPIR=(
               "AP       Access Point setup")
    WIFIMODULE="mt7915e"
    ;;
  *)
    echo "Unknown target '${target}'"
    exit
    ;;
esac
} 

# End of default configuration values

function finish {
  trap 'echo got SIGINT' INT
  trap 'echo got SIGEXIT' EXIT
  [ -v noautomountrule ] && $sudo rm -vf $noautomountrule
  if [ -v rootfsdir ] && [ ! -z "$rootfsdir" ]; then
    $sudo sync
    echo Running exit function to clean up...
    echo $(mountpoint $rootfsdir)
    while [[ "$(mountpoint $rootfsdir)" =~ "is a mountpoint" ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo sync
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

function waitdev {
  while [ ! -b $(realpath "$1") ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function formatimage {
  esize_mb=$(cat /sys/block/${device/"/dev/"/""}/device/preferred_erase_size) 
  [ -z "$esize_mb" ] && esize_mb=$SD_ERASE_SIZE_MB || esize_mb=$(( $esize_mb /1024 /1024 ))
  echo "Erase size = $esize_mb MB"
  minimalrootstart_kb=$(( $ATF_END_KB + ($MINIMAL_SIZE_FIP_MB * 1024) ))
  rootstart_kb=0
  while [[ $rootstart_kb -lt $minimalrootstart_kb ]]; do
    rootstart_kb=$(( $rootstart_kb + ($esize_mb * 1024) ))
  done
  if [[ "$ROOT_END_MB" =~ "%" ]]; then
    root_end_kb=$ROOT_END_MB
  else
    root_end_kb=$(( ($ROOT_END_MB/$esize_mb*$esize_mb)*1024 ))
  fi
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do $sudo umount $PART; done
  if [ "$l" != true ]; then
    $sudo parted -s "${device}" unit MiB print
    echo -e "\nAre you sure you want to format "$device"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  $sudo wipefs --all --force "${device}"
  $sudo dd of="${device}" if=/dev/zero bs=64kiB count=$(($rootstart_kb/64)) status=progress conv=notrunc,fsync
  $sudo sync
  $sudo partprobe "${device}"; udevadm settle
  $sudo parted -s -- "${device}" mklabel gpt
  [[ $? != 0 ]] && exit
  $sudo parted -s -- "${device}" unit kiB \
    mkpart primary 34s $ATF_END_KB \
    mkpart primary $ATF_END_KB $rootstart_kb \
    mkpart primary $rootstart_kb $root_end_kb \
    set 1 legacy_boot on \
    name 1 ${target}-${atfdevice}-atf \
    name 2 ${target}-${atfdevice}-fip \
    name 3 ${target}-${atfdevice}-root \
    print
  $sudo partprobe "${device}"; udevadm settle
  mountdev=$(lsblk -prno partlabel,name $device | grep -P '^bpir' | grep -- -root | cut -d' ' -f2)
  waitdev "${mountdev}"
  $sudo blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  nrseg=$(( $esize_mb / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
  $sudo mkfs.f2fs -s $nrseg -t 0 -f -l "${target^^}-ROOT" ${mountdev}
  $sudo sync
  if [ -b ${device}"boot0" ] && [[ "$compatible" == *"bananapi"*"mediatek,mt7622"* ]]; then
    $sudo mmc bootpart enable 7 1 ${device}
  fi
  $sudo lsblk -o name,mountpoint,label,partlabel,size,uuid "${device}"
}

function resolv {
  $sudo cp /etc/resolv.conf $rootfsdir/etc/
  if [ -z "$(cat $rootfsdir/etc/resolv.conf | grep -oP '^nameserver')" ]; then
    echo "nameserver 8.8.8.8" | $sudo tee -a $rootfsdir/etc/resolv.conf
  fi
}

function bootstrap {
  trap ctrl_c INT
  [ -d "$rootfsdir/etc" ] && return
  eval repo=${BACKUPREPOURL}
  until pacmanpkg=$(curl -L $repo'/ericwoud.db' | tar -xzO --wildcards "pacman-static*/desc" \
        | grep "%FILENAME%" -A1 | tail -n 1)
  do sleep 2; done
  until curl -L $repo'/'$pacmanpkg | xz -dc - | $sudo tar x -C $rootfsdir
  do sleep 2; done
  [ ! -d "$rootfsdir/usr" ] && return
  $sudo mkdir -p $rootfsdir/{etc/pacman.d,var/lib/pacman}
  resolv
  echo 'Server = '"$ALARM_MIRROR/$arch"'/$repo' | \
    $sudo tee $rootfsdir/etc/pacman.d/mirrorlist
  cat <<-EOF | $sudo tee $rootfsdir/etc/pacman.conf
	[options]
	SigLevel = Never
	[core]
	Include = /etc/pacman.d/mirrorlist
	[extra]
	Include = /etc/pacman.d/mirrorlist
	[community]
	Include = /etc/pacman.d/mirrorlist
	EOF
  until $schroot pacman-static -Syu --noconfirm --needed --overwrite \* pacman archlinuxarm-keyring
  do sleep 2; done
  $sudo mv -vf $rootfsdir/etc/pacman.conf.pacnew         $rootfsdir/etc/pacman.conf
  $sudo mv -vf $rootfsdir/etc/pacman.d/mirrorlist.pacnew $rootfsdir/etc/pacman.d/mirrorlist
}

function setupMACconfig {
  file="$rootfsdir/etc/systemd/network/mac.txt"
  while [ ! -z "$(cat $file | grep 'aa:bb:cc:dd:ee:ff')" ]; do
    mac_read="$(cat $file | grep -m1 'aa:bb:cc:dd:ee:ff' | cut -d ' ' -f1)"
    mac=${mac_read::17}
    nr=${mac_read:18}
    [ -z "$nr" ] && nr=1
    first="aa:bb:cc"
    while [ ! -z "$(cat $file | grep $mac)" ]; do # make sure all macs are different
      mac=$first:$(printf %02x $(($RANDOM%256))):$(printf %02x $(($RANDOM%256)))
    done
    mac=$mac:$(printf %02x $(($RANDOM%256)) )
    mac=${mac::-2}$(printf %02x $(((16#${mac: -2}&-$nr)+0)))
    $sudo sed -i '0,/aa:bb:cc:dd:ee:ff/{s/aa:bb:cc:dd:ee:ff/'$mac'/}' $file
  done
}

function rootfs {
  trap ctrl_c INT
  resolv
  if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
    serv="[ericwoud]\nServer = $REPOURL\nServer = $BACKUPREPOURL\n"
    $sudo sed -i '/^\[core\].*/i'" ${serv}"'' $rootfsdir/etc/pacman.conf
  fi
  $schroot pacman-key --init
  $schroot pacman-key --populate archlinuxarm
  $schroot pacman-key --recv-keys $REPOKEY
  $schroot pacman-key --finger     $REPOKEY
  $schroot pacman-key --lsign-key $REPOKEY
  $schroot pacman-key --lsign-key "Arch Linux ARM Build System <builder@archlinuxarm.org>"
  until $schroot pacman -Syyu --needed --noconfirm --overwrite \* pacman-static \
                        $NEEDED_PACKAGES $EXTRA_PACKAGES $PREBUILT_PACKAGES
  do sleep 2; done
  $schroot useradd --create-home --user-group \
               --groups audio,games,log,lp,optical,power,scanner,storage,video,wheel \
               -s /bin/bash $USERNAME
  echo $USERNAME:$USERPWD | $schroot chpasswd
  echo      root:$ROOTPWD | $schroot chpasswd
  echo "${target}" | $sudo tee $rootfsdir/etc/hostname
  echo "%wheel ALL=(ALL) ALL" | $sudo tee $rootfsdir/etc/sudoers.d/wheel
  $schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  $sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*UsePAM.*/UsePAM no/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*#IgnorePkg.*/IgnorePkg = bpir*-atf-git bpir*-uboot-git/' $rootfsdir/etc/pacman.conf
  $sudo cp -rfvL "$rootfsdir/usr/share/buildR64arch/etc" $rootfsdir
  wdir="$rootfsdir/etc/systemd/network"; $sudo rm -rf $wdir/*
  $sudo cp -rfvL "$rootfsdir/usr/share/buildR64arch/network/${target^^}-${setup}/"* $wdir
  wdir="$rootfsdir/etc/hostapd";         $sudo rm -rf $wdir/*
  $sudo cp -rfvL "$rootfsdir/usr/share/buildR64arch/hostapd/${target^^}/"* $wdir
  $sudo sed -i "s/\bdummy\b/PARTLABEL=${target}-${atfdevice}-root/g" $rootfsdir/etc/fstab
  if [ ! -z "$brlanip" ]; then
    $sudo sed -i 's/Address=.*/Address='$brlanip'\/24/' \
                    $rootfsdir/etc/systemd/network/10-brlan.network
  fi
  $sudo mkdir -p $rootfsdir/etc/modules-load.d
  echo -e "# Load ${WIFIMODULE}.ko at boot\n${WIFIMODULE}" | \
           $sudo tee $rootfsdir/etc/modules-load.d/${WIFIMODULE}.conf
  $schroot sudo systemctl --force --no-pager reenable systemd-timesyncd.service
  $schroot sudo systemctl --force --no-pager reenable sshd.service
  $schroot sudo systemctl --force --no-pager reenable systemd-resolved.service
  if [[ ${setup} == "RT"* ]]; then
    $schroot sudo systemctl --force --no-pager reenable nftables.service
  else
    $schroot sudo systemctl --force --no-pager disable nftables.service
  fi
  $schroot sudo systemctl --force --no-pager reenable systemd-networkd.service
  find -L "$rootfsdir/etc/hostapd" -name "*.conf"| while read conf ; do
    conf=$(basename $conf); conf=${conf/".conf"/""}
    $schroot sudo systemctl --force --no-pager reenable hostapd@${conf}.service \
                 2>&1 | grep -v "is added as a dependency to a non-existent unit"
  done
  setupMACconfig
  $schroot bpir-toolbox $bpir_write
}

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  $schroot
}

function compressimage {
  rm -f $IMAGE_FILE".xz" $IMAGE_FILE".gz"
  $sudo rm -vrf $rootfsdir/tmp/*
  echo "Type Y + Y:"
  yes | $schroot pacman -Scc
  finish
  [ "$x" = true ] && xz   --keep --force --verbose $IMAGE_FILE
  [ "$z" = true ] && dd if=$IMAGE_FILE status=progress | gzip >$IMAGE_FILE".gz"
}

function backuprootfs {
  $sudo tar -vcf "${BACKUPFILE}" -C $rootfsdir .
}

function restorerootfs {
  if [ -z "$(ls $rootfsdir)" ] || [ "$(ls $rootfsdir)" = "boot" ]; then
    $sudo tar -vxf "${BACKUPFILE}" -C $rootfsdir
    echo "Run ./build.sh and execute 'pacman -Sy bpir-atf-git' to write the" \
         "new atf-boot! Then type 'exit'."
  else
    echo "Root partition not empty!"
  fi
}

function installscript {
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes            $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN
  else
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX
  fi
  # On all linux's
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so install qemu
    until curl -L $QEMU_AARCH64 | $sudo tar -xz  -C /usr/local/bin
    do sleep 2; done
    S1=':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/local/bin/qemu-aarch64-static:CF'
    echo -n $S1$S2| $sudo tee /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    echo
    $sudo systemctl restart systemd-binfmt.service
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

function add_children() {
  [ -z "$1" ] && return || echo $1
  for ppp in $(pgrep -P $1 2>/dev/null) ; do add_children $ppp; done
}

function ctrl_c() {
  echo "** Trapped CTRL-C, PID=$mainPID **"
  if [ ! -z "$mainPID" ]; then
    for pp in $(add_children $mainPID | sort -nr); do
      $sudo kill -s SIGKILL $pp &>/dev/null
    done
  fi
  exit
}

export LC_ALL=C
export LANG=C
export LANGUAGE=C 

[ -f "config.sh" ] && source config.sh

cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
[ $USER = "root" ] && sudo="" || sudo="sudo"
while getopts ":ralcbxzpRAFBIP" opt $args; do
  if [[ "${opt}" == "?" ]]; then echo "Unknown option -$OPTARG"; exit; fi
  declare "${opt}=true"
  ((argcnt++))
done
[ -z "$argcnt" ] && c=true
if [ "$l" = true ]; then
  if [ $argcnt -eq 1 ]; then 
    c=true
  else
    [ ! -f $IMAGE_FILE ] && F=true
  fi
fi
[ "$F" = true ] && r=true
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
echo "Compatible:" $compatible

hostarch=$(uname -m)
echo "Host Arch:" $hostarch

[ "$a" = true ] && installscript
[ "$A" = true ] && removescript

rootdevice=$(mount | grep -E '\s+on\s+/\s+' | cut -d' ' -f1)
rootdev=$(lsblk -sprno name ${rootdevice} | tail -2 | head -1)
echo "rootdev=$rootdev , do not use."
[ -z $rootdev ] && exit

pkroot=$(lsblk -srno name ${rootdevice} | tail -1)
echo "pkroot=$pkroot , do not use."
[ -z $pkroot ] && exit

[ "$I" = true ] && source config.sh

if [ "$F" = true ]; then
  if [ "$I" != true ]; then # Non-interactive -lFI or -lrI
    PS3="Choose target to format image for: "; COLUMNS=1
    select target in "${TARGETS[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#TARGETS[@]} )) ; then break; else exit; fi
    done
    target=${target%% *}
    PS3="Choose atfdevice to format image for: "; COLUMNS=1
    atfdevices=()
    [[ $target != "bpir3m" ]] && atfdevices+=("sdmmc SD Card")
    atfdevices+=("emmc  EMMC onboard" "Quit")
    select atfdevice in "${atfdevices[@]}" ; do
      if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
    done
    atfdevice=${atfdevice%% *}
  fi
  if [ "$l" = true ]; then
    [ ! -f $IMAGE_FILE ] && touch $IMAGE_FILE
    loopdev=$($sudo losetup --show --find $IMAGE_FILE 2>/dev/null)
    echo "Loop device = $loopdev"
    device=$loopdev
  else
    readarray -t options < <(lsblk -dprno name,size \
       | grep -v "^/dev/"${pkroot} | grep -v 'boot0 \|boot1 \|boot2 ')
    PS3="Choose device to format: "; COLUMNS=1
    select device in "${options[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
    done
    device=${device%% *}
  fi
else
  if [ "$l" = true ]; then
    loopdev=$($sudo losetup --show --find $IMAGE_FILE)
    echo "Loop device = $loopdev"
    $sudo partprobe $loopdev; udevadm settle
    device=$loopdev
  else
    readarray -t options < <(lsblk -prno partlabel,pkname | grep -P '^bpir' \
        | grep -- -root | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    if [ ${#options[@]} -gt 1 ]; then
      PS3="Choose device to work on: "; COLUMNS=1
      select choice in "${options[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
      done
    else
      choice=${options[0]}
    fi
    device=$(echo $choice | cut -d' ' -f2)
  fi
  pr=$(lsblk -prno partlabel $device | grep -P '^bpir' | grep -- -root)
  target=$(echo $pr | cut -d'-' -f1)
  atfdevice=$(echo $pr | cut -d'-' -f2)
fi
echo -e "Device=${device}\nTarget=${target}\nATF-device="${atfdevice}
[ -z "$device" ] && exit
[ -z "${target}" ] && exit
[ -z "${atfdevice}" ] && exit

setupenv # Now that target and atfdevice are known.

if [ "$r" = true ]; then
  if [ "$I" != true ]; then
    echo -e "\nCreate root filesystem\n"
    PS3="Choose setup to create root for: "; COLUMNS=1
    select setup in "${SETUPBPIR[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#SETUPBPIR[@]} )) ; then break; else exit; fi
    done
    setup=${setup%% *}
    echo "Setup="${setup}
    read -p "Enter ip address for local network (emtpy for default): " brlanip
    echo "IP="$brlanip
  fi
  if [ "$p" = true ]  ; then bpir_write="--fip2boot"
  elif [ "$P" = true ]; then bpir_write="--boot2fip"
  else
    case ${atfdevice} in
      sdmmc|emmc) bpir_write="--fip2boot" ;;
      nand)       bpir_write="--boot2fip" ;;
      *) echo "Unknown atfdevice '${atfdevice}'"; exit ;;
    esac
  fi
fi

# Check if 'config.sh' exists.  If so, source that to override default values.
[ -f "config.sh" ] && source config.sh

if [ "$l" = true ] && [ $(stat --printf="%s" $IMAGE_FILE) -eq 0 ]; then
  echo -e "\nCreating image file..."
  dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$IMAGE_SIZE_MB status=progress conv=notrunc,fsync
  $sudo losetup --set-capacity $device
fi

$sudo mkdir -p "/run/udev/rules.d"
noautomountrule="/run/udev/rules.d/10-no-automount-bpir.rules"
echo 'KERNELS=="'${device/"/dev/"/""}'", ENV{UDISKS_IGNORE}="1"' | $sudo tee $noautomountrule

[ "$F" = true ] && formatimage

mountdev=$(lsblk -prno partlabel,name $device | grep -P '^bpir' | grep -- -root | cut -d' ' -f2)
bootdev=$( lsblk -prno partlabel,name $device | grep -P '^bpir' | grep -- -boot | cut -d' ' -f2)
echo "Mountdev = $mountdev"
echo "Bootdev  = $bootdev"
[ -z "$mountdev" ] && exit

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi

rootfsdir="/tmp/bpirootfs.$$"
schroot="$sudo unshare --fork --kill-child --pid --root=$rootfsdir"
echo "Rootfsdir="$rootfsdir

$sudo umount $mountdev
$sudo mkdir -p $rootfsdir
[ "$b" = true ] && ro=",ro" || ro=""
$sudo mount --source $mountdev --target $rootfsdir \
            -o exec,dev,noatime,nodiratime$ro
[[ $? != 0 ]] && exit
if [ ! -z "$bootdev" ]; then
  $sudo umount $bootdev
  $sudo mkdir -p $rootfsdir/boot
  $sudo mount -t vfat "$bootdev" $rootfsdir/boot
  [[ $? != 0 ]] && exit
fi

if [ "$b" = true ] ; then backuprootfs ; exit; fi
if [ "$B" = true ] ; then restorerootfs; exit; fi

if [ "$R" = true ] ; then
  read -p "Type <remove> to delete everything from the card: " prompt
  [[ $prompt != "remove" ]] && exit
  (shopt -s dotglob; $sudo rm -rf $rootfsdir/*)
  exit
fi

[ ! -d "$rootfsdir/dev" ] && $sudo mkdir $rootfsdir/dev
$sudo mount --rbind --make-rslave /dev  $rootfsdir/dev # install gnupg needs it
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then bootstrap &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
$sudo mount -t proc               /proc $rootfsdir/proc
[[ $? != 0 ]] && exit
$sudo mount --rbind --make-rslave /sys  $rootfsdir/sys
[[ $? != 0 ]] && exit
$sudo mount --rbind --make-rslave /run  $rootfsdir/run
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then rootfs &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
[ "$c" = true ] && chrootfs
if [ "$x" = true ] || [ "$z" = true ]; then
  compressimage
fi

exit

# xz -e -k -9 -C crc32 $$< --stdout > $$@

# kernelcmdline: block2mtd.block2mtd=/dev/mmcblk0p2,128KiB,MyMtd cmdlinepart.mtdparts=MyMtd:1M(mtddata)ro
