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

ROOT_START_MB=256MiB           # Size of root partition in MiB
ROOT_END_MB=100%               # Size of root partition in MiB
#ROOT_END_MB=$(( 4*1024  ))    # Size 4GiB
IMAGE_SIZE_MB=7456             # Size of image
IMAGE_FILE="bpir.img"          # Name of image

STRAP_PACKAGES_ALARM="pacman archlinuxarm-keyring inetutils"
STRAP_PACKAGES_DEBIAN="apt-utils ca-certificates gnupg hostname"

SCRIPT_PACKAGES="curl ca-certificates parted gzip f2fs-tools btrfs-progs dosfstools debootstrap"
SCRIPT_PACKAGES_ALARM="qemu-user-static qemu-user-static-binfmt"
SCRIPT_PACKAGES_DEBIAN="qemu-user qemu-user-binfmt"

TARGETS=("bpir64 Bananapi-R64"
         "bpir3  Bananapi-R3"
         "bpir3m Bananapi-R3-Mini"
         "bpir4  Bananapi-R4")

DISTROS=("alarm    ArchLinuxARM"
         "ubuntu   Ubuntu (experimental with bugs)")

function setupenv {
arch='aarch64'
#BACKUPFILE="/run/media/$USER/DATA/${target}-${device}-rootfs.tar"
BACKUPFILE="./${target}-${device}-rootfs.tar"
devices=()
[[ $target != "bpir3m" ]] && devices+=("sdmmc SD Card")
                             devices+=("emmc  EMMC onboard")
[[ $target == "bpir64" ]] && devices+=("sata  SATA onboard")
[[ $target != "bpir64" ]] && devices+=("nvme  NVME onboard")
}

# End of default configuration values

function finish {
  trap 'echo got SIGINT' INT
  trap 'echo got SIGEXIT' EXIT
  [ -v noautomountrule ] && rm -vf $noautomountrule
  if [ -v rootfsdir ] && [ ! -z "$rootfsdir" ]; then
    sync
    echo Running exit function to clean up...
    while mountpoint -q $rootfsdir/cachedir; do
      echo "Unmounting...DO NOT REMOVE!"
      sync; umount -R $rootfsdir/cachedir; sleep 0.1
    done
    rm -rf $rootfsdir/cachedir
    while mountpoint -q $rootfsdir; do
      echo "Unmounting...DO NOT REMOVE!"
      sync; umount -R $rootfsdir; sleep 0.1
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
  for part in $(parts "${dev}"); do umount "${part}" 2>/dev/null; done
  if [ "$l" != true ]; then
    parted -s "${dev}" unit MiB print
    echo -e "\nDo you want to wipe all partitions from "${dev}"???"
    read -p "Type <wipeall> to wipe all: " prompt
  else
    prompt="wipeall"
  fi
  if [[ $prompt == "wipeall" ]]; then
    wipefs --all --force "${dev}"
    sync
    partprobe "${dev}"; udevadm settle 2>/dev/null
    parted -s -- "${dev}" mklabel gpt
    [[ $? != 0 ]] && exit
    partprobe "${dev}"; udevadm settle 2>/dev/null
  fi
  mountdev=$(blkid $(parts ${dev}) -t PARTLABEL=${target}-${device}-root -o device)
  if [ -z "$mountdev" ]; then
    parted -s -- "${dev}" unit GiB print
    echo "To enter percentage: append the number with a '%' without space (e.g. 100%)."
    read -p "Enter GiB or percentage of start of root partition: " rootstart_gb
    read -p "Enter GiB or percentage of end of root partition: " rootend_gb
    parted -s -- "${dev}" unit GiB \
      mkpart ${target}-${device}-root btrfs $rootstart_gb $rootend_gb
    [[ $? != 0 ]] && exit 1
    partprobe "${dev}"; udevadm settle 2>/dev/null
    while
      mountdev=$(blkid $(parts ${dev}) -t PARTLABEL=${target}-${device}-root -o device)
      [ -z "$mountdev" ]
    do sleep 0.1; done
    waitdev "${mountdev}"
    partnum=$(cat /sys/class/block/$(basename ${mountdev})/partition)
    [ -z "$partnum" ] && exit 1
    parted -s -- "${dev}" set "$partnum" boot on
    partprobe "${dev}"; udevadm settle 2>/dev/null
    while
      [ -z "$(blkid $(parts ${dev}) -t PARTLABEL=${target}-${device}-root -o device)" ]
    do sleep 0.1; done
  elif [ "$l" != true ]; then
    parted -s "${dev}" unit MiB print
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
  for part in $(parts "${dev}"); do umount "${part}" 2>/dev/null; done
  if [ "$l" != true ]; then
    parted -s "${dev}" unit MiB print
    echo -e "\nAre you sure you want to format "${dev}"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  wipefs --all --force "${dev}"
  sync
  partprobe "${dev}"; udevadm settle 2>/dev/null
  parted -s -- "${dev}" mklabel gpt
  [[ $? != 0 ]] && exit
  parted -s -- "${dev}" unit MiB \
    mkpart ${target}-${device}-root $ROOT_START_MB $ROOT_END_MB \
    print
  partprobe "${dev}"; udevadm settle 2>/dev/null
  while
    mountdev=$(blkid $(parts ${dev}) -t PARTLABEL=${target}-${device}-root -o device)
    [ -z "$mountdev" ]
  do sleep 0.1; done
  waitdev "${mountdev}"
  blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  mkfs.btrfs -f -L "${target^^}-ROOT" ${mountdev}
  sync
}
#    mkpart primary 34s $ATF_END_KB \
#    mkpart primary $ATF_END_KB $rootstart_kb \
#    mkpart primary $rootstart_kb $root_end_kb \
#    set 1 legacy_boot on \
#    name 1 ${target}-${device}-atf \
#    name 2 fip \
#    name 3 ${target}-${device}-root \

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
  if [ "$distro" == "ubuntu" ]; then
    [ "$d" = true ] && cdir="--cache-dir=$(realpath ./cachedir)" || cdir="--no-check-gpg"
    until debootstrap "${cdir}" --arch=arm64 --no-check-gpg --components=$DEBOOTSTR_COMPNS \
                     --variant=minbase --include="${STRAP_PACKAGES_DEBIAN// /,}" \
                     $DEBOOTSTR_RELEASE $rootfsdir $DEBOOTSTR_SOURCE
    do sleep 2; done
    echo -e 'APT::Install-Suggests "0";'"\n"'APT::Install-Recommends "0";' | \
        tee $rootfsdir/etc/apt/apt.conf.d/99onlyneeded
    echo "deb [arch=arm64] http://${WOUDSTRA}/apt-repo stable main" | \
        tee $rootfsdir/etc/apt/sources.list.d/ericwoud.list
    until schroot gpg --batch --yes --keyserver "${DEBIANKEYSERVER}" --recv-keys $REPOKEY
    do sleep 2; done
    schroot gpg --batch --yes --output /etc/apt/trusted.gpg.d/ericwoud.gpg --export $REPOKEY
  elif [ "$distro" == "alarm" ]; then
    eval repo=${ALARMREPOURL}
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
    [ "$d" = true ] && cdir="--cachedir=/cachedir" || cdir="--noconfirm"
    [ "$S" = true ] && sb="--disable-sandbox"      || sb="--noconfirm"
    until schrootstrap pacman-static -Syu "${cdir}" "${sb}" --noconfirm --needed --overwrite \* $STRAP_PACKAGES_ALARM pacman-static
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
  [ "$d" = true ] && cdir="--cachedir"      || cdir=""
  [ "$S" = true ] && sb="--disable-sandbox" || sb=""
  schroot xargs -a <(echo -n "--configonly ${cdir} ${sb} ${rootfsargs}") bpir-rootfs
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
  rm -vrf $rootfsdir/var/cache/apt/archives/*.deb
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

function ask() {
  local a items count
  if [ -z "${!1}" ]; then
    eval 'items=("${'"${2}"'[@]}")'
    eval 'count=${#'"${2}"'[@]}'
    if [ ${count} -gt 1 ]; then
      PS3="${3} "; COLUMNS=1; echo
      select a in "${items[@]}" "Quit"; do
        (( REPLY > 0 && REPLY <= ${count} )) && break || exit 1
      done
    else
      a=${items[0]}
    fi
    export declare $1=${a%% *}
  fi
}

function usage {
 cat <<-EOF
	Usage: $(basename "$0") [OPTION]...
	  -F --format              format sd/emmc or image-file
	  -l --loopdev             use image-file instead of sd-card
	  -r --rootfs              setup rootfs on image
	  -c --chroot              enter chroot on image
	  -b --backup              backup rootfs
	  -B --restore             restore rootfs
	  -x --createxz            create bpir.img.xz
	  -z --creategz            create bpir.img.gz
	  -p --boot2fip            setup fip-partition bootchain (sd/emmc)
	  -P --fip2boot            setup boot-partition (fat32) bootchain (sd/emmc)
	  -p --creategz            create bpir.img.gz
	  -u --uartboot            create uartboot image
	  -d --cachedir            store packages in cachedir
	  -R --clearrootfs         empty rootfs
	  --imagefile [FILENAME]   image file name, default bpir.img
	  --imagesize [FILESIZE]   image file size in Mib, default ${IMAGE_SIZE_MB}
	  --rootstart [ROOTSTART]  sd/emmc: root partition start in MiB, default ${ROOT_START_MB}
	  --rootend [ROOTEND]      sd/emmc: root partition end in MiB or %, default ${ROOT_END_MB}
	  --erasesize [SIZE]       sd/emmc: erasesize in MiB, default ${SD_ERASE_SIZE_MB}
	  --bpirtoolbox [ARGS]     arguments for bpir-toolbox
	  --brlanip [default|IP]   ip for brlan
	  --ddrsize [default|8]    ddr size in GB
	  --setup [AP|RT|...]      setup for network
	  --target [bpir64|bpir3|bpir3m|bpir4]   specify target
	  --device [sdmmc|emmc|nvme|sata]        specify device
	EOF
    exit 1
}

export LC_ALL=C
export LANG=C
export LANGUAGE=C

[ -f "config.sh" ] && source config.sh

cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"

while getopts ":rlcbxzpudRFBIPS-:" opt $args; do
  if [[ "${opt}" == "?" ]]; then
    echo "Unknown option -$OPTARG"
    usage
  elif [[ "${opt}" == "-" ]]; then
    case "$OPTARG" in
      chroot) opt=c ;;
      loopdev) opt=l ;;
      rootfs) opt=r ;;
      backup) opt=b ;;
      restore) opt=B ;;
      createxz) opt=x ;;
      creategz) opt=z ;;
      uartboot) opt=u ;;
      cachedir) opt=d ;;
      clearrootfs) opt=R ;;
      format) opt=F ;;
      disable-sandbox) opt=S ;;
      distro)             distro="${!OPTIND}"; ((OPTIND++));;
      distro=*)           distro="${OPTARG#*=}";;
      bpirtoolbox)        bpirtoolbox="${!OPTIND}"; ((OPTIND++));;
      bpirtoolbox=*)      bpirtoolbox="${OPTARG#*=}";;
      brlanip)            brlanip="${!OPTIND}"; ((OPTIND++));;
      brlanip=*)          brlanip="${OPTARG#*=}";;
      ddrsize)            ddrsize="${!OPTIND}"; ((OPTIND++));;
      ddrsize=*)          ddrsize="${OPTARG#*=}";;
      setup)              setup="${!OPTIND}"; ((OPTIND++));;
      setup=*)            setup="${OPTARG#*=}";;
      target)             target="${!OPTIND}"; ((OPTIND++));;
      target=*)           target="${OPTARG#*=}";;
      device)             device="${!OPTIND}"; ((OPTIND++));;
      device=*)           device="${OPTARG#*=}";;
      imagefile)          IMAGE_FILE="${!OPTIND}"; ((OPTIND++));;
      imagefile=*)        IMAGE_FILE="${OPTARG#*=}";;
      imagesize)          IMAGE_SIZE_MB="${!OPTIND}"; ((OPTIND++));;
      imagesize=*)        IMAGE_SIZE_MB="${OPTARG#*=}";;
      rootstart)          ROOT_START_MB="${!OPTIND}"; ((OPTIND++));;
      rootstart=*)        ROOT_START_MB="${OPTARG#*=}";;
      rootend)            ROOT_END_MB="${!OPTIND}"; ((OPTIND++));;
      rootend=*)          ROOT_END_MB="${OPTARG#*=}";;
      erasesize)          SD_ERASE_SIZE_MB="${!OPTIND}"; ((OPTIND++));;
      erasesize=*)        SD_ERASE_SIZE_MB="${OPTARG#*=}";;
      *)
        echo "Unknown option --$OPTARG"
        usage
        ;;
    esac
  fi
  [[ "${opt}" != "-" ]] && declare "${opt}=true"
  ((argcnt++))
done

[ "$l" = true ] && ((argcnt--))
[ "$d" = true ] && ((argcnt--))
[ $argcnt -eq 0 ] && c=true
if [ "$l" = true ]; then
  if [ "$initrd" = true ]; then
    echo "Loopdev not supported in initrd!"
    exit 1
  fi
  [ $argcnt -eq 0 ] && [ ! -f $IMAGE_FILE ] && F=true
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
      [[ "$hostarch" == "aarch64" ]] && [[ "$package" =~ "qemu-user" ]] && continue
      if ! dpkg -l $package >/dev/null; then missing+=" $package"; fi
    done
    instcmd="sudo apt-get install $missing"
  else
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ALARM; do
      [[ "$hostarch" == "aarch64" ]] && [[ "$package" =~ "qemu-user" ]] && continue
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

[ -f "config.sh" ] && source config.sh

if [ "$F" = true ]; then
  ask target TARGETS "Choose target to format image for:"
  setupenv # Now that target is known.
  ask device devices "Choose device to format image for:"
  if [ "$l" = true ]; then
    [ ! -f $IMAGE_FILE ] && touch $IMAGE_FILE
    loopdev=$(losetup --show --find $IMAGE_FILE 2>/dev/null)
    echo "Loop device = $loopdev"
    dev=$loopdev
  else
    readarray -t devs < <(lsblk -dprno name,size \
       | grep -v "^/dev/"${pkroot} | grep -v 'boot0 \|boot1 \|boot2 ')
    ask dev devs "Choose device to format:"
  fi
else
  if [ "$l" = true ]; then
    loopdev=$(losetup --show --find $IMAGE_FILE)
    echo "Loop device = $loopdev"
    partprobe $loopdev; udevadm settle
    dev=$loopdev
  else
    readarray -t devs < <(blkid -s PARTLABEL | \
        grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    ask dev devs "Choose device to work on:"
    dev=$(lsblk -npo pkname ${dev/:/})
  fi
  pr=$(blkid -s PARTLABEL $(parts ${dev})| grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d'"' -f2)
  target=$(echo $pr | cut -d'-' -f1)
  device=$(echo $pr | cut -d'-' -f2)
fi
echo -e "Dev=${dev}\nTarget=${target}\ndevice="${device}
[ -z "${dev}" ] && exit
[ -z "${target}" ] && exit
[ -z "${device}" ] && exit

setupenv # Now that target and device are known.

if [ "$r" = true ]; then
  [ "$p" = true ] && bpirtoolbox="--fip2boot"
  [ "$P" = true ] && bpirtoolbox="--boot2fip"
  if [ "$F" = true ]; then
    ask distro DISTROS "Choose distro to create root for:"
    echo "Distro="${distro}
  fi
  rm -f "/tmp/bpir-rootfs.txt"
  rootfsargs="--menuonly --target '${target}' --device '${device}' --ddrsize '${ddrsize}' --setup '${setup}' --brlanip '${brlanip}' --bpirtoolbox '${bpirtoolbox}'"
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
  losetup --set-capacity ${dev}
fi

if [ "$initrd" != true ]; then
  mkdir -p "/run/udev/rules.d"
  noautomountrule="/run/udev/rules.d/10-no-automount-bpir.rules"
  echo 'KERNELS=="'${dev/"/dev/"/""}'", ENV{UDISKS_IGNORE}="1"' | tee $noautomountrule
fi

if [ "$F" = true ]; then
  if [ "${device}" == "nvme" ] || [ "${device}" == "sata" ]; then
    formatimage_nvme
  else
    formatimage_mmc
  fi
fi

mountdev=$(blkid -s PARTLABEL $(parts ${dev}) | grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d' ' -f1 | tr -d :)
bootdev=$( blkid -s PARTLABEL $(parts ${dev}) | grep -E 'PARTLABEL="'     | grep -E -- 'boot"'  | cut -d' ' -f1 | tr -d :)
echo "Mountdev = $mountdev"
echo "Bootdev  = $bootdev"
[ -z "$mountdev" ] && exit

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi

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
  mountoptions="rw,nosuid,nodev,noexec,relatime,nosymfollow,fmask=0077,dmask=0077,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro"
  mount -t vfat "$bootdev" $rootfsdir/boot -o "${mountoptions}"
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
if [ "$d" = true ]; then
  mkdir -p ./cachedir $rootfsdir/cachedir
  mount --rbind --make-rslave ./cachedir  $rootfsdir/cachedir
  [[ $? != 0 ]] && exit
fi
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

