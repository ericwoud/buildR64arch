#!/bin/bash

# Set default configuration values
# These can be overridden by entering them into config.sh

ALARM_MIRROR="http://mirror.archlinuxarm.org"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
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

NEEDED_PACKAGES="hostapd wireless-regdb iproute2 nftables f2fs-tools dosfstools\
 btrfs-progs patch sudo evtest parted linux-firmware binutils cpio mtd-utils"
NEEDED_PACKAGES_DEBIAN="openssh-server device-tree-compiler mmc-utils\
 libpam-systemd systemd-timesyncd systemd-resolved kmod zstd
 iputils-ping apt-utils iw"
NEEDED_PACKAGES_ALARM=" openssh        dtc                  mmc-utils-git\
 base dbus-broker-units"
STRAP_PACKAGES_ALARM="pacman archlinuxarm-keyring inetutils"
EXTRA_PACKAGES="nano screen i2c-tools ethtool iperf3 curl wget debootstrap"
PREBUILT_PACKAGES="bpir-atf-git bpir-uboot-git ssh-fix-reboot hostapd-launch bpir-initrd"
SCRIPT_PACKAGES="curl ca-certificates udisks2 parted gzip bc f2fs-tools dosfstools debootstrap"
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

DISTROBPIR=("alarm    ArchLinuxARM"
            "ubuntu   Ubuntu")

QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static.tar.gz"
QEMUFILE="qemu-aarch64-static"
S1=':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/run/buildarch/qemu-aarch64-static:CF'

function setupenv {
#BACKUPFILE="/run/media/$USER/DATA/${target}-${atfdevice}-rootfs.tar"
BACKUPFILE="./${target}-${atfdevice}-rootfs.tar"
arch='aarch64'
PREBUILT_PACKAGES+=" linux-${target}-git"
case ${target} in
  bpir64)
    DDRSIZE=("default    1 GB")
    SETUPBPIR=("RT       Router setup"
               "AP       Access Point setup")
    WIFIMODULE="mt7615e"
    ;;
  bpir3)
    DDRSIZE=("default    2 GB")
    SETUPBPIR=("RT       Router setup, SFP module eth1 as wan"
               "RTnoSFP  Router setup, not using SFP module"
               "AP       Access Point setup")
    WIFIMODULE="mt7915e"
    ;;
  bpir3m)
    DDRSIZE=("default    2 GB")
    SETUPBPIR=("RT       Router setup"
               "AP       Access Point setup")
    WIFIMODULE="mt7915e"
    ;;
  bpir4)
    DDRSIZE=("default    4 GB"
             "8          8 GB")
    SETUPBPIR=("RTnoSFP  Router setup, not using SFP module, wan=lan0"
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
    while mountpoint -q $rootfsdir; do
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
  disableqemu
}

function waitdev {
  while [ ! -b $(realpath "$1") ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function parts {
  $sudo lsblk $1 -lnpo name
}

function formatimage_nvme {
  echo TODO
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
  for part in $(parts "${device}"); do $sudo umount "${part}" 2>/dev/null; done
  if [ "$l" != true ]; then
    $sudo parted -s "${device}" unit MiB print
    echo -e "\nAre you sure you want to format "$device"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  $sudo wipefs --all --force "${device}"
  $sudo sync
  $sudo partprobe "${device}"; $sudo udevadm settle 2>/dev/null
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
  $sudo partprobe "${device}"; $sudo udevadm settle 2>/dev/null
  while
    mountdev=$($sudo blkid $(parts ${device}) -t PARTLABEL=${target}-${atfdevice}-root -o device)
    [ -z "$mountdev" ]
  do sleep 0.1; done
  waitdev "${mountdev}"
  $sudo blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  nrseg=$(( $esize_mb / 2 )); [[ $nrseg -lt 1 ]] && nrseg=1
  $sudo mkfs.f2fs -s $nrseg -t 0 -f -l "${target^^}-ROOT" ${mountdev}
  $sudo sync
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
  if [ "$distro" == "ubuntu" ]; then
    until $sudo debootstrap --arch=arm64 --no-check-gpg --components=$DEBOOTSTR_COMPNS \
                     --variant=minbase $DEBOOTSTR_RELEASE $rootfsdir $DEBOOTSTR_SOURCE
    do sleep 2; done
  fi
  until pacmanpkg=$(curl -L $repo'/ericwoud.db' | tar -xzO --wildcards "pacman-static*/desc" \
        | grep "%FILENAME%" -A1 | tail -n 1)
  do sleep 2; done
  until curl -L $repo'/'$pacmanpkg | xz -dc - | $sudo tar x -C $rootfsdir
  do sleep 2; done
  [ ! -d "$rootfsdir/usr" ] && return
  $sudo mkdir -p $rootfsdir/{etc/pacman.d,var/lib/pacman}
  if [ "$distro" == "alarm" ]; then
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
    until schrootstrap pacman-static -Syu --noconfirm --needed --overwrite \* $STRAP_PACKAGES_ALARM
    do sleep 2; done
    $sudo mv -vf $rootfsdir/etc/pacman.conf.pacnew         $rootfsdir/etc/pacman.conf
    $sudo mv -vf $rootfsdir/etc/pacman.d/mirrorlist.pacnew $rootfsdir/etc/pacman.d/mirrorlist
  fi
}

function rootfs {
  trap ctrl_c INT
  resolv
  serv="[ericwoud]\nServer = $REPOURL\nServer = $BACKUPREPOURL\n"
  echo "${target}" | $sudo tee $rootfsdir/etc/hostname
  if [[ -z $(grep "${target}" $rootfsdir/etc/hosts 2>/dev/null) ]]; then
    echo -e "127.0.0.1\t${target}" | $sudo tee -a $rootfsdir/etc/hosts
  fi
  if [ ! -f "$rootfsdir/etc/arch-release" ]; then ### Ubuntu / Debian
    sshd="ssh"
    wheel="sudo"
    groups="audio,games,lp,video,$wheel"
    echo -e 'APT::Install-Suggests "0";'"\n"'APT::Install-Recommends "0";' | $sudo tee \
            $rootfsdir/etc/apt/apt.conf.d/99onlyneeded
    until schroot apt-get install --yes $NEEDED_PACKAGES $NEEDED_PACKAGES_DEBIAN $EXTRA_PACKAGES
    do sleep 2; done
    cat <<-EOF | $sudo tee $rootfsdir/etc/pacman.conf
	[options]
	Architecture = aarch64
	#IgnorePkg =
	#IgnoreGroup =
	#NoUpgrade   =
	#NoExtract   =
	CheckSpace
	SigLevel    = Never
	LocalFileSigLevel = Optional
	#RemoteFileSigLevel = Required
	${serv}
	EOF
    $sudo sed -i 's|\\n|\n|g' $rootfsdir/etc/pacman.conf
    until schroot pacman-static -Syu --noconfirm --overwrite \\* build-r64-arch-utils-git
    do sleep 2; done
    until schroot bpir-apt install $PREBUILT_PACKAGES
    do sleep 2; done
  else # ArchLinuxArm
    sshd="sshd"
    wheel="wheel"
    groups="audio,games,log,lp,optical,power,scanner,storage,video,$wheel"
    if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
      $sudo sed -i '/^\[core\].*/i'" ${serv}"'' $rootfsdir/etc/pacman.conf
    fi
    schroot pacman-key --init
    schroot pacman-key --populate archlinuxarm
    schroot pacman-key --recv-keys $REPOKEY
    schroot pacman-key --finger     $REPOKEY
    schroot pacman-key --lsign-key $REPOKEY
#    schroot pacman-key --lsign-key 'Arch Linux ARM Build System <builder@archlinuxarm.org>'
    until schroot pacman -Syyu --needed --noconfirm --overwrite \\* pacman-static \
                          $NEEDED_PACKAGES $NEEDED_PACKAGES_ALARM $EXTRA_PACKAGES $PREBUILT_PACKAGES
    do sleep 2; done
  fi
  schroot useradd --create-home --user-group \
               --groups ${groups} \
               -s /bin/bash $USERNAME
  echo "%${wheel} ALL=(ALL) ALL" | $sudo tee $rootfsdir/etc/sudoers.d/wheel
  schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
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
  echo $USERNAME:$USERPWD | schroot chpasswd
  echo      root:$ROOTPWD | schroot chpasswd
  schroot sudo systemctl --force --no-pager reenable ${sshd}.service
  schroot sudo systemctl --force --no-pager reenable systemd-timesyncd.service
  schroot sudo systemctl --force --no-pager reenable systemd-resolved.service
  if [[ ${setup} == "RT"* ]]; then
    schroot sudo systemctl --force --no-pager reenable nftables.service
  else
    schroot sudo systemctl --force --no-pager disable nftables.service
  fi
  schroot sudo systemctl --force --no-pager reenable systemd-networkd.service
  find -L "$rootfsdir/etc/hostapd" -name "*.conf"| while read conf ; do
    conf=$(basename $conf); conf=${conf/".conf"/""}
    schroot sudo systemctl --force --no-pager reenable hostapd@${conf}.service \
                 2>&1 | grep -v "is added as a dependency to a non-existent unit"
  done
  setupMACconfig
  [[ "${ddrsize}" != "default" ]] && echo -n "${ddrsize}" | \
                 $sudo tee $rootfsdir/boot/bootcfg/ddrsize
  schroot bpir-toolbox $bpir_write
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

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  schroot
}

function compressimage {
  rm -f $IMAGE_FILE".xz" $IMAGE_FILE".gz"
  $sudo rm -vrf $rootfsdir/tmp/*
  $sudo rm -vrf $rootfsdir/var/cache/pacman/pkg/*
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

function setupqemu {
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so use qemu
    if [ ! -f "/run/buildarch/${QEMUFILE}" ]; then
      $sudo mkdir -p "/run/buildarch"
      until curl -L $QEMU | $sudo tar -xz  -C "/run/buildarch"
      do sleep 2; done
    fi
    $sudo mkdir -p "/run/binfmt.d"
    echo -n $S1$S2| $sudo tee /run/binfmt.d/05-buildarch-qemu-static.conf >/dev/null
    echo
    $sudo systemctl restart systemd-binfmt.service
  fi
}

function disableqemu {
  if [ -f "/run/binfmt.d/05-buildarch-qemu-static.conf" ]; then
    $sudo rm -f "/run/binfmt.d/05-buildarch-qemu-static.conf" >/dev/null
    $sudo systemctl restart systemd-binfmt.service
  fi
}

function add_children() {
  [ -z "$1" ] && return || echo $1
  for ppp in $(pgrep -P $1 2>/dev/null) ; do add_children $ppp; done
}

function schrootstrap() {
    $sudo unshare --fork --kill-child --pid --uts --root=$rootfsdir "${@}"
}

function schroot() {
  if [[ -z "${*}" ]]; then
    $sudo unshare --fork --kill-child --pid --uts --root=$rootfsdir su -c "hostname ${target};bash"
  else
    $sudo unshare --fork --kill-child --pid --uts --root=$rootfsdir su -c "hostname ${target};${*}"
  fi
}

function ctrl_c() {
  echo "** Trapped CTRL-C, PID=$mainPID **"
  if [ ! -z "$mainPID" ]; then
    for pp in $(add_children $mainPID | sort -nr); do
      $sudo kill -s SIGKILL $pp &>/dev/null
    done
  fi
  trap - EXIT
  finish
  exit 1
}

export LC_ALL=C
export LANG=C
export LANGUAGE=C

[ -f "config.sh" ] && source config.sh

[ -f "/etc/bpir-is-initrd" ] && initrd=true

cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
if [ $USER = "root" ] || [ "$initrd" = true ]; then
  sudo=""
else
  sudo="sudo"
fi
while getopts ":rlcbxzpRFBIP" opt $args; do
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

if [ "$initrd" != true ]; then
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN; do
      if ! dpkg -l $package >/dev/null; then missing+=" $package"; fi
    done
    instcmd="sudo apt-get install $missing"
  else
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX; do
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
    atfdevices+=("emmc  EMMC onboard" "nvme  NVME onboard" "Quit")
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
    readarray -t options < <($sudo blkid -s PARTLABEL | \
        grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    if [ ${#options[@]} -gt 1 ]; then
      PS3="Choose device to work on: "; COLUMNS=1
      select choice in "${options[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
      done
    else
      choice=${options[0]}
    fi
    device=$($sudo lsblk -npo pkname $(echo $choice | cut -d' ' -f1 | tr -d :))
  fi
  pr=$($sudo blkid -s PARTLABEL $(parts ${device})| grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d'"' -f2)
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
    if [ ${#DDRSIZE[@]} -gt 1 ]; then
      PS3="Choose the size of ddr ram: "; COLUMNS=1
      select ddrsize in "${DDRSIZE[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#DDRSIZE[@]} )) ; then break; else exit; fi
      done
    else
      ddrsize=${DDRSIZE[0]}
    fi
    ddrsize=${ddrsize%% *}
    echo "DDR-size="$ddrsize
    echo -e "\nCreate root filesystem\n"
    PS3="Choose distro to create root for: "; COLUMNS=1
    select distro in "${DISTROBPIR[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#DISTROBPIR[@]} )) ; then break; else exit; fi
    done
    distro=${distro%% *}
    echo "Distro="${distro}
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
      *) echo "Unknown atfdevice '${atfdevice}'" ;;
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

if [ "$F" = true ]; then
  [ "${atfdevice}" == "nvme" ] && formatimage_nvme || formatimage_mmc
fi

mountdev=$($sudo blkid -s PARTLABEL $(parts ${device}) | grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d' ' -f1 | tr -d :)
bootdev=$( $sudo blkid -s PARTLABEL $(parts ${device}) | grep -E 'PARTLABEL="bpir' | grep -E -- '-boot"' | cut -d' ' -f1 | tr -d :)
echo "Mountdev = $mountdev"
echo "Bootdev  = $bootdev"
[ -z "$mountdev" ] && exit

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi

rootfsdir="/tmp/bpirootfs.$$"
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

setupqemu

[ ! -d "$rootfsdir/dev" ] && $sudo mkdir $rootfsdir/dev
$sudo mount --rbind --make-rslave /dev  $rootfsdir/dev # install gnupg needs it
[[ $? != 0 ]] && exit
$sudo mount --rbind --make-rslave /dev/pts  $rootfsdir/dev/pts
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
