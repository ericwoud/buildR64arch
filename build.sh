#!/bin/bash

[ -f "/etc/bpir-is-initrd" ] && initrd=true
if [ $USER != "root" ] && [ "$initrd" != true ]; then
  sudo $0 ${@:1}
  exit
fi
[ -z "$SUDO_USER" ] && SUDO_USER="$USER"

# Set default configuration values
# These can be overridden by entering them into config.sh

ALARM_MIRROR="http://mirror.archlinuxarm.org"
DEBIANKEYSERVER="hkps://keyserver.ubuntu.com:443"

WOUDSTRA='ftp.woudstra.mywire.org'
REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
ALARMREPOURL='ftp://'${WOUDSTRA}'/repo/$arch'
DEBIANREPOURL="http://${WOUDSTRA}/apt-repo"
BACKUPREPOURL='https://github.com/ericwoud/buildRKarch/releases/download/repo-$arch'

DEBOOTSTR_RELEASE="noble"
DEBOOTSTR_SOURCE="http://ports.ubuntu.com/ubuntu-ports"
DEBOOTSTR_COMPNS="main,restricted,universe,multiverse"
#DEBOOTSTR_RELEASE="bullseye"
#DEBOOTSTR_SOURCE="http://ftp.debian.org/debian/"
#DEBOOTSTR_COMPNS="main,contrib,non-free"

# Standard erase size, when it cannot be determined (using /dev/sdX cardreader or loopdev)
SD_ERASE_SIZE_MB=4             # in Mega bytes

ATF_END_KB=1024                # End of atf partition
MINIMAL_SIZE_FIP_MB=190        # Minimal size of fip partition
ROOT_END_MB=100%               # Size of root partition
#ROOT_END_MB=$(( 4*1024  ))    # Size 4GiB
IMAGE_SIZE_MB=7456             # Size of image
IMAGE_FILE="./bpir.img"        # Name of image

STRAP_PACKAGES_ALARM="pacman archlinuxarm-keyring inetutils"
STRAP_PACKAGES_DEBIAN="apt-utils ca-certificates gnupg hostname"

SCRIPT_PACKAGES="curl ca-certificates parted gzip f2fs-tools btrfs-progs dosfstools debootstrap"
SCRIPT_PACKAGES_ALARM="qemu-user-static qemu-user-static-binfmt"
SCRIPT_PACKAGES_DEBIAN="qemu-user qemu-user-binfmt"

TARGETS=("bpir64 Bananapi-R64"
         "bpir3  Bananapi-R3"
         "bpir3m Bananapi-R3-Mini"
         "bpir4  Bananapi-R4")

DISTROBPIR=("alarm    ArchLinuxARM"
            "ubuntu   Ubuntu (experimental with bugs)")

function setupenv {
arch='aarch64'
#BACKUPFILE="/run/media/$USER/DATA/${target}-${atfdevice}-rootfs.tar"
BACKUPFILE="./${target}-${atfdevice}-rootfs.tar"
}

# End of default configuration values

function finish {
  trap 'echo got SIGINT' INT
  trap 'echo got SIGEXIT' EXIT
  [ -v noautomountrule ] && rm -vf $noautomountrule
  if [ -v rootfsdir ] && [ ! -z "$rootfsdir" ]; then
    sync
    echo Running exit function to clean up...
    while mountpoint -q $rootfsdir; do
      echo "Unmounting...DO NOT REMOVE!"
      sync
      umount -R $rootfsdir
      sleep 0.1
    done
    rm -rf $rootfsdir
    sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
  if [ -v loopdev ] && [ ! -z "$loopdev" ]; then
    losetup -d $loopdev
  fi
  unset loopdev
}

function waitdev {
  while [ ! -b $(realpath "$1") ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function parts {
  lsblk $1 -lnpo name
}

function formatimage_nvme {
  echo TODO
  for part in $(parts "${device}"); do umount "${part}" 2>/dev/null; done
  if [ "$l" != true ]; then
    parted -s "${device}" unit MiB print
    echo -e "\nDo you want to wipe all partitions from "$device"???"
    read -p "Type <wipeall> to wipe all: " prompt
  else
    prompt="wipeall"
  fi
  if [[ $prompt == "wipeall" ]]; then
    wipefs --all --force "${device}"
    sync
    partprobe "${device}"; udevadm settle 2>/dev/null
    parted -s -- "${device}" mklabel gpt
    [[ $? != 0 ]] && exit
    partprobe "${device}"; udevadm settle 2>/dev/null
  fi
  mountdev=$(blkid $(parts ${device}) -t PARTLABEL=${target}-${atfdevice}-root -o device)
  if [ -z "$mountdev" ]; then
    parted -s -- "${device}" unit GiB print
    echo "To enter percentage: append the number with a '%' without space (e.g. 100%)."
    read -p "Enter GiB or percentage of start of root partition: " rootstart_gb
    read -p "Enter GiB or percentage of end of root partition: " rootend_gb
    parted -s -- "${device}" unit GiB \
      mkpart ${target}-${atfdevice}-root btrfs $rootstart_gb $rootend_gb
    [[ $? != 0 ]] && exit 1
    partprobe "${device}"; udevadm settle 2>/dev/null
    while
      mountdev=$(blkid $(parts ${device}) -t PARTLABEL=${target}-${atfdevice}-root -o device)
      [ -z "$mountdev" ]
    do sleep 0.1; done
    waitdev "${mountdev}"
    partnum=$(cat /sys/class/block/$(basename ${mountdev})/partition)
    [ -z "$partnum" ] && exit 1
    parted -s -- "${device}" set "$partnum" boot on
    partprobe "${device}"; udevadm settle 2>/dev/null
    while
      [ -z "$(blkid $(parts ${device}) -t PARTLABEL=${target}-${atfdevice}-root -o device)" ]
    do sleep 0.1; done
  elif [ "$l" != true ]; then
    parted -s "${device}" unit MiB print
    echo -e "\nAre you sure you want to format "${mountdev}"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  waitdev "${mountdev}"
  blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  mkfs.btrfs -f -L "${target^^}-ROOT" ${mountdev}
  sync
}

function formatimage_mmc {
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
  for part in $(parts "${device}"); do umount "${part}" 2>/dev/null; done
  if [ "$l" != true ]; then
    parted -s "${device}" unit MiB print
    echo -e "\nAre you sure you want to format "$device"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  wipefs --all --force "${device}"
  sync
  partprobe "${device}"; udevadm settle 2>/dev/null
  parted -s -- "${device}" mklabel gpt
  [[ $? != 0 ]] && exit
  parted -s -- "${device}" unit kiB \
    mkpart primary 34s $ATF_END_KB \
    mkpart primary $ATF_END_KB $rootstart_kb \
    mkpart primary $rootstart_kb $root_end_kb \
    set 1 legacy_boot on \
    name 1 ${target}-${atfdevice}-atf \
    name 2 fip \
    name 3 ${target}-${atfdevice}-root \
    print
  partprobe "${device}"; udevadm settle 2>/dev/null
  while
    mountdev=$(blkid $(parts ${device}) -t PARTLABEL=${target}-${atfdevice}-root -o device)
    [ -z "$mountdev" ]
  do sleep 0.1; done
  waitdev "${mountdev}"
  blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  nrseg=$(( $esize_mb / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
  mkfs.f2fs -s $nrseg -t 0 -f -l "${target^^}-ROOT" ${mountdev}
  sync
}

function resolv {
  cp /etc/resolv.conf $rootfsdir/etc/
  if [ -z "$(cat $rootfsdir/etc/resolv.conf | grep -oP '^nameserver')" ]; then
    echo "nameserver 8.8.8.8" | tee -a $rootfsdir/etc/resolv.conf
  fi
}

function addmyrepo {
  if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
    local serv="[ericwoud]\nServer = $ALARMREPOURL\nServer = $BACKUPREPOURL\n"
    sed -i '/^\[core\].*/i'" ${serv}"'' $rootfsdir/etc/pacman.conf
  fi
}

function bootstrap {
  trap ctrl_c INT
  [ -d "$rootfsdir/etc" ] && return
  eval repo=${BACKUPREPOURL}
  if [ "$distro" == "ubuntu" ]; then
    until debootstrap --arch=arm64 --no-check-gpg --components=$DEBOOTSTR_COMPNS \
                     --variant=minbase --include="${STRAP_PACKAGES_DEBIAN// /,}" \
                     $DEBOOTSTR_RELEASE $rootfsdir $DEBOOTSTR_SOURCE
    do sleep 2; done
    echo -e 'APT::Install-Suggests "0";'"\n"'APT::Install-Recommends "0";' | \
        tee $rootfsdir/etc/apt/apt.conf.d/99onlyneeded
    echo "deb [arch=arm64] http://${WOUDSTRA}/apt-repo stable main" | \
        tee $rootfsdir/etc/apt/sources.list.d/ericwoud.list
    mkdir -p $rootfsdir/usr/share/keyrings/
    until schroot gpg --batch --yes --keyserver "${DEBIANKEYSERVER}" --recv-keys $REPOKEY
    do sleep 2; done
    schroot gpg --batch --yes --output /etc/apt/trusted.gpg.d/ericwoud.gpg --export $REPOKEY
  elif [ "$distro" == "alarm" ]; then
    until pacmanpkg=$(curl -L $repo'/ericwoud.db' | tar -xzO --wildcards "pacman-static*/desc" \
          | grep "%FILENAME%" -A1 | tail -n 1)
    do sleep 2; done
    until curl -L $repo'/'$pacmanpkg | xz -dc - | tar x -C $rootfsdir
    do sleep 2; done
    [ ! -d "$rootfsdir/usr" ] && return
    mkdir -p $rootfsdir/{etc/pacman.d,var/lib/pacman}
    resolv
    echo 'Server = '"$ALARM_MIRROR/$arch"'/$repo' | \
      tee $rootfsdir/etc/pacman.d/mirrorlist
    cat <<-EOF | tee $rootfsdir/etc/pacman.conf
	[options]
	Architecture = ${arch}
	SigLevel = Never
	[core]
	Include = /etc/pacman.d/mirrorlist
	[extra]
	Include = /etc/pacman.d/mirrorlist
	[community]
	Include = /etc/pacman.d/mirrorlist
	EOF
    addmyrepo
    until schrootstrap pacman-static -Syu --noconfirm --needed --overwrite \* $STRAP_PACKAGES_ALARM pacman-static
    do sleep 2; done
    mv -vf $rootfsdir/etc/pacman.conf.pacnew         $rootfsdir/etc/pacman.conf
    mv -vf $rootfsdir/etc/pacman.d/mirrorlist.pacnew $rootfsdir/etc/pacman.d/mirrorlist
    addmyrepo
    schroot pacman-key --init
    schroot pacman-key --populate archlinuxarm
    until schroot pacman-key --recv-keys $REPOKEY
    do sleep 2; done
    schroot pacman-key --finger     $REPOKEY
    schroot pacman-key --lsign-key $REPOKEY
#    schroot pacman-key --lsign-key 'Arch Linux ARM Build System <builder@archlinuxarm.org>'
  else
    echo "Unknown distro!"
    exit 1
  fi
  echo "${target}" | tee $rootfsdir/etc/hostname
  if [[ -z $(grep "${target}" $rootfsdir/etc/hosts 2>/dev/null) ]]; then
    echo -e "127.0.0.1\t${target}" | tee -a $rootfsdir/etc/hosts
  fi
  sync
}

function rootfs {
  trap ctrl_c INT
  if ! schroot command -v bpir-rootfs >/dev/null 2>&1; then
    mkdir -p "$rootfsdir/usr/local/sbin"
    cp -vf ./rootfs/bin/bpir-rootfs $rootfsdir/usr/local/sbin
  fi
  schroot xargs -a <(echo -n "--configonly ${rootfsargs}") bpir-rootfs
  rm -vf $rootfsdir/usr/local/sbin/bpir-rootfs 2>/dev/null
  sync
}

function uartbootbuild {
  trap ctrl_c INT
  schroot bpir-toolbox --uartboot
  mkdir -p ./uartboot
  cp -vf "$rootfsdir/tmp/uartboot/"*".bin"  ./uartboot/
  chown -R $SUDO_USER:nobody                ./uartboot/
  schroot bpir-toolbox --nand-image
  mkdir -p ./nandimage
  cp -vf "$rootfsdir/tmp/nandimage/"*".bin" ./nandimage/
  chown -R $SUDO_USER:nobody                ./nandimage/
}

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  schroot
}

function compressimage {
  rm -f $IMAGE_FILE".xz" $IMAGE_FILE".gz"
  rm -vrf $rootfsdir/tmp/*
  rm -vrf $rootfsdir/var/cache/pacman/pkg/*
  finish
  if [ "$x" = true ]; then
    xz   --keep --force --verbose $IMAGE_FILE
    chown $SUDO_USER:nobody "${IMAGE_FILE}.xz"
  fi
  if [ "$z" = true ]; then
    dd if=$IMAGE_FILE status=progress | gzip >$IMAGE_FILE".gz"
    chown $SUDO_USER:nobody "${IMAGE_FILE}.gz"
  fi
}

function backuprootfs {
  tar -vcf "${BACKUPFILE}" -C $rootfsdir .
  chown $SUDO_USER:nobody "${BACKUPFILE}"
}

function restorerootfs {
  if [ -z "$(ls $rootfsdir)" ] || [ "$(ls $rootfsdir)" = "boot" ]; then
    tar -vxf "${BACKUPFILE}" -C $rootfsdir
    echo "Run ./build.sh and execute 'bpir-toolbox --write2atf' to write the" \
         "new atf-boot! Then type 'exit'."
  else
    echo "Root partition not empty!"
  fi
}

function add_children() {
  [ -z "$1" ] && return || echo $1
  for ppp in $(pgrep -P $1 2>/dev/null) ; do add_children $ppp; done
}

function schrootstrap() {
    unshare --fork --kill-child --pid --uts --root=$rootfsdir "${@}"
}

function schroot() {
  if [[ -z "${*}" ]]; then
#chroot $rootfsdir /bin/bash
    unshare --fork --kill-child --pid --uts --root=$rootfsdir su -c "hostname ${target};bash"
  else
    unshare --fork --kill-child --pid --uts --root=$rootfsdir su -c "hostname ${target};${*}"
  fi
}

function ctrl_c() {
  echo "** Trapped CTRL-C, PID=$mainPID **"
  if [ ! -z "$mainPID" ]; then
    for pp in $(add_children $mainPID | sort -nr); do
      kill -s SIGKILL $pp &>/dev/null
    done
  fi
  trap - EXIT
  finish
  exit 1
}

export LC_ALL=C
export LANG=C
export LANGUAGE=C

ddrsize="default"
[ -f "config.sh" ] && source config.sh

cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"

while getopts ":rlcbxzpuRFBIP" opt $args; do
  if [[ "${opt}" == "?" ]]; then echo "Unknown option -$OPTARG"; exit; fi
  declare "${opt}=true"
  ((argcnt++))
done
[ -z "$argcnt" ] && c=true
if [ "$l" = true ]; then
  if [ "$initrd" = true ]; then
    echo "Loopdev not supported in initrd!"
    exit 1
  fi
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

echo "Current dir:" $(realpath .)

compatible="$(tr -d '\0' 2>/dev/null </proc/device-tree/compatible)"
echo "Compatible:" $compatible

hostarch=$(uname -m)
echo "Host Arch:" $hostarch

if [ "$initrd" != true ]; then
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN; do
      if ! dpkg -l $package >/dev/null; then missing+=" $package"; fi
    done
    instcmd="sudo apt-get install $missing"
  else
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ALARM; do
      if ! pacman -Qi $package >/dev/null; then missing+=" $package"; fi
    done
    instcmd="sudo pacman -Syu $missing"
  fi
  if [ ! -z "$missing" ]; then
    echo -e "\nInstall these packages with command:\n${instcmd}\n"
    exit
  fi
  rootdevice=$(mount | grep -E '\s+on\s+/\s+' | cut -d' ' -f1)
  rootdev=$(lsblk -sprno name ${rootdevice} | tail -2 | head -1)
  echo "rootdev=$rootdev , do not use."
  [ -z $rootdev ] && exit
  pkroot=$(lsblk -srno name ${rootdevice} | tail -1)
  echo "pkroot=$pkroot , do not use."
  [ -z $pkroot ] && exit
else
 rootdev="undefined"
 pkroot="undefined"
fi

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
    atfdevices+=("emmc  EMMC onboard")
    [[ $target == "bpir64" ]] && atfdevices+=("sata  SATA onboard") \
                              || atfdevices+=("nvme  NVME onboard")
    select atfdevice in "${atfdevices[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#atfdevices[@]} )) ; then break; else exit; fi
    done
    atfdevice=${atfdevice%% *}
  fi
  if [ "$l" = true ]; then
    [ ! -f $IMAGE_FILE ] && touch $IMAGE_FILE
    loopdev=$(losetup --show --find $IMAGE_FILE 2>/dev/null)
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
    loopdev=$(losetup --show --find $IMAGE_FILE)
    echo "Loop device = $loopdev"
    partprobe $loopdev; udevadm settle
    device=$loopdev
  else
    readarray -t options < <(blkid -s PARTLABEL | \
        grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    if [ ${#options[@]} -gt 1 ]; then
      PS3="Choose device to work on: "; COLUMNS=1
      select choice in "${options[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
      done
    else
      choice=${options[0]}
    fi
    device=$(lsblk -npo pkname $(echo $choice | cut -d' ' -f1 | tr -d :))
  fi
  pr=$(blkid -s PARTLABEL $(parts ${device})| grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d'"' -f2)
  target=$(echo $pr | cut -d'-' -f1)
  atfdevice=$(echo $pr | cut -d'-' -f2)
fi
echo -e "Device=${device}\nTarget=${target}\nATF-device="${atfdevice}
[ -z "$device" ] && exit
[ -z "${target}" ] && exit
[ -z "${atfdevice}" ] && exit

setupenv # Now that target and atfdevice are known.

if [ "$r" = true ]; then
  if [ "$p" = true ]  ; then bpirwrite="--fip2boot"
  elif [ "$P" = true ]; then bpirwrite="--boot2fip"
  fi
  if [ "$I" == true ]; then
    brlanip="default"
  else
    brlanip=""
    if [ "$F" = true ]; then
      echo -e "\nCreate root filesystem\n"
      PS3="Choose distro to create root for: "; COLUMNS=1
      select distro in "${DISTROBPIR[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#DISTROBPIR[@]} )) ; then break; else exit 1; fi
      done
      distro=${distro%% *}
      echo "Distro="${distro}
    fi
  fi
  rm -f "/tmp/bpir-rootfs.txt"
  rootfsargs="--menuonly --target '${target}' --atfdevice '${atfdevice}' --brlanip '${brlanip}' --bpirwrite '${bpirwrite}'"
  if command -v bpir-rootfs >/dev/null 2>&1 ; then
    xargs -a <(echo -n "${rootfsargs}") bpir-rootfs
  elif [ -f "./rootfs/bin/bpir-rootfs" ]; then
    xargs -a <(echo -n "${rootfsargs}") ./rootfs/bin/bpir-rootfs
  else
    echo "bpir-rootfs no found!"
    exit 1
  fi
  rootfsargs=$(cat "/tmp/bpir-rootfs.txt" 2>/dev/null)
  [ -z "$rootfsargs" ] && exit 1
  echo "rootfsargs: $rootfsargs"
fi

# Check if 'config.sh' exists.  If so, source that to override default values.
[ -f "config.sh" ] && source config.sh

if [ "$l" = true ] && [ $(stat --printf="%s" $IMAGE_FILE) -eq 0 ]; then
  echo -e "\nCreating image file..."
  dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$IMAGE_SIZE_MB status=progress conv=notrunc,fsync
  losetup --set-capacity $device
fi

if [ "$initrd" != true ]; then
  mkdir -p "/run/udev/rules.d"
  noautomountrule="/run/udev/rules.d/10-no-automount-bpir.rules"
  echo 'KERNELS=="'${device/"/dev/"/""}'", ENV{UDISKS_IGNORE}="1"' | tee $noautomountrule
fi

if [ "$F" = true ]; then
  if [ "${atfdevice}" == "nvme" ] || [ "${atfdevice}" == "sata" ]; then
    formatimage_nvme
  else
    formatimage_mmc
  fi
fi

mountdev=$(blkid -s PARTLABEL $(parts ${device}) | grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d' ' -f1 | tr -d :)
bootdev=$( blkid -s PARTLABEL $(parts ${device}) | grep -E 'PARTLABEL="'     | grep -E -- 'boot"'  | cut -d' ' -f1 | tr -d :)
echo "Mountdev = $mountdev"
echo "Bootdev  = $bootdev"
[ -z "$mountdev" ] && exit

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi

echo "DDR-size="$ddrsize

rootfsdir="/tmp/bpirootfs.$$"
echo "Rootfsdir="$rootfsdir

umount $mountdev
mkdir -p $rootfsdir
[ "$b" = true ] && ro=",ro" || ro=""
mount --source $mountdev --target $rootfsdir \
            -o exec,dev,noatime,nodiratime$ro
[[ $? != 0 ]] && exit
if [ ! -z "$bootdev" ]; then
  umount $bootdev
  mkdir -p $rootfsdir/boot
  mount -t vfat "$bootdev" $rootfsdir/boot
  [[ $? != 0 ]] && exit
fi

if [ "$b" = true ] ; then backuprootfs ; exit; fi
if [ "$B" = true ] ; then restorerootfs; exit; fi

if [ "$R" = true ] ; then
  read -p "Type <remove> to delete everything from the card: " prompt
  [[ $prompt != "remove" ]] && exit
  (shopt -s dotglob; rm -rf $rootfsdir/*)
  exit
fi

[ ! -d "$rootfsdir/dev" ] && mkdir $rootfsdir/dev
mount --rbind --make-rslave /dev  $rootfsdir/dev # install gnupg needs it
[[ $? != 0 ]] && exit
[ ! -d "$rootfsdir/dev/pts" ] && mkdir $rootfsdir/dev/pts
mount --rbind --make-rslave /dev/pts  $rootfsdir/dev/pts
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then bootstrap &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
mount -t proc               /proc $rootfsdir/proc
[[ $? != 0 ]] && exit
mount --rbind --make-rslave /sys  $rootfsdir/sys
[[ $? != 0 ]] && exit
mount --rbind --make-rslave /run  $rootfsdir/run
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then rootfs &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
if [ "$u" = true ]; then uartbootbuild &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
[ "$c" = true ] && chrootfs
if [ "$x" = true ] || [ "$z" = true ]; then
  compressimage
fi

exit

# xz -e -k -9 -C crc32 $$< --stdout > $$@

# kernelcmdline: block2mtd.block2mtd=/dev/mmcblk0p2,128KiB,MyMtd cmdlinepart.mtdparts=MyMtd:1M(mtddata)ro
