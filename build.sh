#!/bin/bash

[[ -f "/etc/bpir-is-initrd" ]] && initrd=true
[[ -z "$SUDO_USER" ]] && SUDO_USER="$USER"

# Set default configuration values
# These can be overridden by entering them into config.sh

export PACKAGES="build-r64-arch-utils-git hostapd-launch ssh-fix-reboot bpir-initrd ethtool-static-git hostapd-static-git"

export ALARM_MIRROR="http://mirror.archlinuxarm.org"
export DEBIANKEYSERVER="hkps://keyserver.ubuntu.com:443"

export ALARMREPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'

export DEBOOTSTR_RELEASE="noble"
#export DEBOOTSTR_SOURCE="https://ports.ubuntu.com/ubuntu-ports"
export DEBOOTSTR_SOURCE="https://mirror.gofoss.xyz/ubuntu-ports"
export DEBOOTSTR_COMPNS="main,restricted,universe,multiverse"
#export DEBOOTSTR_RELEASE="bullseye"
#export DEBOOTSTR_SOURCE="http://ftp.debian.org/debian/"
#export DEBOOTSTR_COMPNS="main,contrib,non-free"

export ROOT_START_MB=256              # Start of root partition in MiB
export ROOT_END_MB=100%               # End of root partition in MiB or %
#export ROOT_END_MB=4GiB              # Size 4GiB
export IMAGE_SIZE_MB=7456             # Size of image
export IMAGE_FILE="bpir.img"          # Name of image

export STRAP_PACKAGES_ALARM="pacman archlinuxarm-keyring"
export STRAP_PACKAGES_DEBIAN="apt-utils ca-certificates gnupg"

SCRIPT_PACKAGES="curl ca-certificates parted gzip btrfs-progs dosfstools debootstrap zstd"
SCRIPT_PACKAGES_ALARM=" qemu-user-static qemu-user-static-binfmt inetutils"
SCRIPT_PACKAGES_DEBIAN="qemu-user        qemu-user-binfmt        hostname"

TARGETS=("bpir64 Bananapi-R64"
         "bpir3  Bananapi-R3"
         "bpir3m Bananapi-R3-Mini"
         "bpir4  Bananapi-R4")

DISTROS=("alarm    ArchLinuxARM"
         "ubuntu   Ubuntu (experimental with bugs)")

function setupenv {
arch="aarch64"
export PACKAGES+=" packages-${target}"
#export BACKUPFILE="/run/media/$USER/DATA/${target}-${device}-rootfs.tar"
export BACKUPFILE="./${target}-${device}-rootfs.tar"
devices=()
[[ $target != "bpir3m" ]] && devices+=("sdmmc SD Card")
                             devices+=("emmc  EMMC onboard")
[[ $target == "bpir64" ]] && devices+=("sata  SATA onboard")
[[ $target != "bpir64" ]] && devices+=("nvme  NVME onboard")
}

# End of default configuration values

function waitdev() {
  while [[ ! -b "$(realpath "$1")" ]]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function parts() {
  lsblk "$1" -lnpo name
}

function checknumber() {
  [[ "${!1}" -eq "${!1}" ]] 2>/dev/null
  [[ $? -eq 0 ]] && return
  echo "$1=\""${!1}"\" is not number"
  exit 1
}

function createimage() {
  echo "Creating image from noroot directory..."
  ATF_END_MB=1
  atf_end_s="$((ATF_END_MB*1024*1024/512))"
  checknumber ROOT_START_MB
  checknumber IMAGE_SIZE_MB
  atffile=$(cat "${rootfsdir}/etc/rootcfg/atffile" | xargs)
  [[ ! -f "${rootfsdir}${atffile}" ]] && return
  rm "${IMAGE_FILE}" "${IMAGE_FILE}.root" 2>/dev/null
  dd if=/dev/zero of="${IMAGE_FILE}" bs=1 count=0 seek=$((ROOT_START_MB))M 2>/dev/null
  dd if=/dev/zero of="${IMAGE_FILE}.root" bs=1 count=0 seek=$((IMAGE_SIZE_MB - ROOT_START_MB - 1))M 2>/dev/null
  dd if="${rootfsdir}${atffile}" of="${IMAGE_FILE}" bs=17K seek=1 count=32 conv=notrunc
  mkfs.vfat --offset "${atf_end_s}" -v -F 32 -S 512 -s 16 -n "${target^^}-BOOT" "${IMAGE_FILE}"
  mcopy -soi "${IMAGE_FILE}@@${atf_end_s}s" "${rootfsdir}/boot"/* ::
  mv -vf "${rootfsdir}/boot" "${rootfsdir}-boot"
  mkfs.btrfs -f -L "${target^^}-ROOT" "${IMAGE_FILE}.root" --rootdir="${rootfsdir}"
  mv -vf "${rootfsdir}-boot" "${rootfsdir}/boot"
  dd if="${IMAGE_FILE}.root" of="${IMAGE_FILE}" bs=1M seek="${ROOT_START_MB}" conv=sparse
  dd if=/dev/zero of="${IMAGE_FILE}" bs=1 count=0 seek="${IMAGE_SIZE_MB}M" 2>/dev/null
  rm "${IMAGE_FILE}.root"
  parted -s -- "${IMAGE_FILE}" unit MiB                                                   \
      mklabel gpt                                                                         \
      mkpart "${target}-${device}-root" btrfs "${ROOT_START_MB}" "$((IMAGE_SIZE_MB - 1))" \
      mkpart "${target}-${device}-atf"        "34s"              "${ATF_END_MB}MiB"       \
      mkpart boot                       fat32 "${ATF_END_MB}MiB" "${ROOT_START_MB}"       \
      set 2 legacy_boot on                                                                \
      set 3        boot on                                                                \
      print
  echo "Imagesize: $(du -h --apparent-size ${IMAGE_FILE}|cut -d$'\t' -f1)," \
      "disk usage: $(du -h                 ${IMAGE_FILE}|cut -d$'\t' -f1)"
}

function formatimage() {
  if [[ "$optn_n" = true ]]; then
    removeallnoroot
    return
  fi
  for part in $(parts "${dev}"); do umount "${part}" 2>/dev/null; done
  if [[ "$optn_l" == true ]]; then
    prompt="wipeall"
  else
    parted -s "${dev}" unit MiB print
    echo -e "\nDo you want to wipe all partitions from ${dev} and create GPT???"
    echo -e "This may require a reboot..."
    read -p "Type <wipeall> to wipe all: " prompt <&1
  fi
  if [[ "${prompt}" == "wipeall" ]]; then
    wipefs --all --force "${dev}"
    sync
    partprobe "${dev}"; udevadm settle 2>/dev/null
    parted -s -- "${dev}" mklabel gpt
    [[ $? != 0 ]] && exit 1
    partprobe "${dev}"; udevadm settle 2>/dev/null
  fi
  if [[ -z $(parted -s -- "${dev}" print 2>/dev/null | grep "^Partition Table: gpt$") ]]; then
    echo -e "\nDevice ${dev} does not contain a usable GPT!"
    exit 1
  fi
  mountdev="$(blkid $(parts "${dev}") -t PARTLABEL="${target}-${device}-root" -o device)"
  if [[ -z "${mountdev}" ]]; then
    parted -s -- "${dev}" unit MiB print
    if [[ "$optn_l" != true ]]; then
      echo "Press enter to continue with default values."
      echo "To enter KiB: Append the number with 'KiB' without space (e.g. 17KiB)."
      echo "To enter MiB: Enter the number of MiB's, no appending needed."
      echo "To enter GiB: Append the number with 'GiB' without space (e.g. 256GiB)."
      echo "To enter %:   Append the number with a '%' without space (e.g. 100%)."
      read -p "Enter the start of the root partition (default ${ROOT_START_MB}): " rootstart <&1
      read -p "Enter the  end  of the root partition (default ${ROOT_END_MB}): "   rootend <&1
    fi
    [[ -z "${rootstart}" ]] && rootstart="${ROOT_START_MB}"
    [[ -z "${rootend}"   ]] && rootend="${ROOT_END_MB}"
    parted -s -- "${dev}" unit MiB mkpart "${target}-${device}-root" btrfs $rootstart $rootend
    [[ $? != 0 ]] && exit 1
    partprobe "${dev}"; udevadm settle 2>/dev/null
    while
      mountdev=$(blkid $(parts ${dev}) -t PARTLABEL="${target}-${device}-root" -o device)
      [[ -z "${mountdev}" ]]
    do sleep 0.1; done
  elif [[ "$optn_l" != true ]]; then
    parted -s "${dev}" unit MiB print
    echo -e "\nAre you sure you want to format "${mountdev}"???"
    read -p "Type <format> to format: " prompt <&1
    [[ "${prompt}" != "format" ]] && exit 1
  fi
  waitdev "${mountdev}"
  blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  mkfs.btrfs -f -L "${target^^}-ROOT" "${mountdev}"
  sync
}

function downloadpkg() {
  eval local repo="$1"
  until local pkg=$(curl -L "${repo}"'/'"${2}.db" | tar -xzO --wildcards "${3}*/desc" \
        | grep "%FILENAME%" -A1 | tail -n 1)
  do sleep 2; done
  until curl -L "${repo}"'/'"${pkg}" | xz -dc - | tar x -C "${rootfsdir}"
  do sleep 2; done
}

function setuppacman() {
  [[ ! -d "${rootfsdir}/usr" ]] && exit 1
  mkdir -p "${rootfsdir}/"{etc/pacman.d,var/lib/pacman}
  echo 'Server = '"${1}/${2}"'/$repo' > "${rootfsdir}/etc/pacman.d/mirrorlist"
  cat <<-EOF > "${rootfsdir}/etc/pacman.conf"
	[options]
	Architecture = ${2}
	SigLevel = Never
	[core]
	Include = /etc/pacman.d/mirrorlist
	[extra]
	Include = /etc/pacman.d/mirrorlist
	[community]
	Include = /etc/pacman.d/mirrorlist
	EOF
}

function rootcfg() {
  mkdir -p "${rootfsdir}/etc/rootcfg"
  echo -n "${target}" > ${rootfsdir}/etc/hostname
  if [[ -z $(grep "${target}" ${rootfsdir}/etc/hosts 2>/dev/null) ]]; then
    echo -e "127.0.0.1\t${target}" >> "${rootfsdir}/etc/hosts"
  fi
  rm -f                      "${rootfsdir}/etc/rootcfg/"*
  echo -n "${target}" >      "${rootfsdir}/etc/rootcfg/target"
  echo -n "${device}" >      "${rootfsdir}/etc/rootcfg/device"
  mv -f "/tmp/bpir-rootfs/"* "${rootfsdir}/etc/rootcfg"
  [[ -d "/usr/share/buildR64arch" ]] && rootfs="/usr/share/buildR64arch" || rootfs="./rootfs"
  cp   -vrfL "${rootfs}/keyring/"*         "${rootfsdir}"
  if   chroot "${rootfsdir}" bash -c "command -v apt"    >/dev/null 2>&1; then
    cp -vrfL "${rootfs}/skeleton-apt/"*    "${rootfsdir}"
  elif chroot "${rootfsdir}" bash -c "command -v pacman" >/dev/null 2>&1; then
    cp -vrfL "${rootfs}/skeleton-pacman/"* "${rootfsdir}"
  fi
}

function setupresolv() {
  [[ "$(realpath -q "${rootfsdir}/etc/resolv.conf")" == "/run/bpir-resolv.conf" ]] && return
  rm -vf "${rootfsdir}/etc/resolv.conf.backup" 2>/dev/null
  mv -vf "${rootfsdir}/etc/resolv.conf" "${rootfsdir}/etc/resolv.conf.backup" 2>/dev/null
  cp -vfLT "/etc/resolv.conf" "${rootfsdir}/run/bpir-resolv.conf"
  ln -sT "/run/bpir-resolv.conf" "${rootfsdir}/etc/resolv.conf"
  if [[ -z "$(cat "${rootfsdir}/run/bpir-resolv.conf" | grep -oP '^nameserver')" ]]; then
    echo "nameserver 8.8.8.8" >> "${rootfsdir}/run/bpir-resolv.conf"
  fi
}

function restoreresolv() {
  [[ "$(realpath -q "${rootfsdir}/etc/resolv.conf")" != "/run/bpir-resolv.conf" ]] && return
  rm -vf "${rootfsdir}/etc/resolv.conf"
  mv -vf "${rootfsdir}/etc/resolv.conf.backup" "${rootfsdir}/etc/resolv.conf" 2>/dev/null
}

function bootstrap() {
  mountcachedir
  if [[ "$distro" == "ubuntu" ]]; then
    local opts=(--arch=arm64 --no-check-gpg --variant=minbase
                --components="${DEBOOTSTR_COMPNS}"
                --include="${STRAP_PACKAGES_DEBIAN// /,}")
    [[ "$optn_d" = true ]] && opts+=(--cache-dir="$(realpath ./cachedir)")
    until debootstrap "${opts[@]}" "${DEBOOTSTR_RELEASE}" "${rootfsdir}" "${DEBOOTSTR_SOURCE}"
    do sleep 2; done
    rootcfg
    mountdevrunprocsys # again, proc and sys get unmounted by debootstrap
    opts=(--yes --quiet)
    [[ "$optn_d" = true ]] && opts+=(-o "Dir::Cache::Archives=/cachedir")
    until DEBIAN_FRONTEND=noninteractive chroot "${rootfsdir}" apt-get update "${opts[@]}"
    do sleep 2; done
    if ! DEBIAN_FRONTEND=noninteractive chroot "${rootfsdir}" apt-get reinstall "${opts[@]}" --no-act '~i'; then
      echo "Check of packages has failed! Maybe gpg error?"
      exit 1
    fi
    until DEBIAN_FRONTEND=noninteractive chroot "${rootfsdir}" apt-get install "${opts[@]}" $PACKAGES
    do sleep 2; done
    setupresolv
    rm -vrf "${rootfsdir}/var/lib/apt/lists/partial"
  elif [[ "$distro" == "alarm" ]]; then
    downloadpkg "${ALARMREPOURL}" "ericwoud" "pacman-static"
    setuppacman "${ALARM_MIRROR}" "${arch}"
    setupresolv
    local opts=(--noconfirm --overwrite="*")
    [[ "$optn_d" = true ]] && opts+=(--cachedir=/cachedir)
    [[ "$optn_S" = true ]] && opts+=(--disable-sandbox)
    until chroot "${rootfsdir}" pacman-static -Syu "${opts[@]}" $STRAP_PACKAGES_ALARM
    do sleep 2; done
    rootcfg
    chroot "${rootfsdir}" pacman-key --init
    chroot "${rootfsdir}" pacman-key --populate archlinuxarm
    chroot "${rootfsdir}" pacman-key --populate ericwoud
    if !  chroot "${rootfsdir}" pacman -Qqn | \
          chroot "${rootfsdir}" pacman -Syyu "${opts[@]}" --downloadonly -; then
      echo "Check of packages has failed! Maybe gpg error?"
      exit 1
    fi
    until chroot "${rootfsdir}" pacman -Su "${opts[@]}" $PACKAGES pacman-static
    do sleep 2; done
  else
    echo "Unknown distro!"
    exit 1
  fi
  restoreresolv
  sync
}

function uartbootbuild() {
  chroot "${rootfsdir}" bpir-toolbox --uartboot
  mkdir -p ./uartboot
  cp -vf "${rootfsdir}/tmp/uartboot/"*".bin"            ./uartboot/
  [[ "$optn_n" != true ]] && chown -R $SUDO_USER:nobody ./uartboot/
  chroot "${rootfsdir}" bpir-toolbox --nand-image
  mkdir -p ./nandimage
  cp -vf "${rootfsdir}/tmp/nandimage/"*".bin"           ./nandimage/
  [[ "$optn_n" != true ]] && chown -R $SUDO_USER:nobody ./nandimage/
}

function bpirrootfs() {
  [[ "$optn_r" != true ]] && return
  rm -f "/tmp/bpir-rootfs.txt"
  rootfsargs=("$@" --target "${target}"   --device "${device}"
                   --ddrsize "${ddrsize}" --setup "${setup}" --brlanip "${brlanip}")
  if [[ -f "${rootfsdir}/bin/bpir-rootfs" ]]; then
    chroot "${rootfsdir}" bpir-rootfs "${rootfsargs[@]}"
  elif [[ -f "./rootfs/bin/bpir-rootfs" ]]; then
    ./rootfs/bin/bpir-rootfs "${rootfsargs[@]}"
  else echo "bpir-rootfs no found!"; exit 1
  fi
}

function chrootfs() {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  mountcachedir
  setupresolv
  chroot "${rootfsdir}" bash <&1
  rm -vrf "${rootfsdir}/var/lib/apt/lists/partial"
  restoreresolv
}

function cleanupimage() {
  rm -f $IMAGE_FILE".xz" $IMAGE_FILE".gz"
  rm -vrf "${rootfsdir}/tmp/"*
  rm -vrf "${rootfsdir}/var/cache/pacman/pkg/"*
  rm -vrf "${rootfsdir}/var/cache/apt/archives/"*".deb"
  rm -vrf "${rootfsdir}/var/lib/apt/lists/partial"
}

function compressimage() {
  if [[ "$optn_x" = true ]]; then
    zstd -kf -5 --sparse --format=xz "${IMAGE_FILE}"
    [[ "$optn_n" != true ]] && chown $SUDO_USER:nobody "${IMAGE_FILE}.xz"
  fi
  if [[ "$optn_z" = true ]]; then
    zstd -kf -5 --sparse --format=gzip "${IMAGE_FILE}"
    [[ "$optn_n" != true ]] && chown $SUDO_USER:nobody "${IMAGE_FILE}.gz"
  fi
}

function backuprootfs() {
  tar -vcf "${BACKUPFILE}" -C "${rootfsdir}" .
  [[ "$optn_n" != true ]] && chown $SUDO_USER:nobody "${BACKUPFILE}"
}

function restorerootfs() {
  if [[ -z "$(ls "${rootfsdir}")" ]] || [[ "$(ls "${rootfsdir}")" = "boot" ]]; then
    tar -vxf "${BACKUPFILE}" -C "${rootfsdir}"
    echo "Run ./build.sh and execute 'bpir-toolbox --write2atf' to write the" \
         "new atf-boot! Then type 'exit'."
  else
    echo "Root partition not empty!"
  fi
}

function mountcachedir() {
  if [[ "$optn_d" = true ]]; then
    mkdir -p "${rootfsdir}/cachedir"
    mount --rbind --make-rslave ./cachedir "${rootfsdir}/cachedir"
    [[ $? != 0 ]] && exit 1
  fi
}


function domount() {
  if ! mountpoint -q "${2}"; then
    if [[ "${1}" == "/dev/"* ]] && [[ "${1}" != "/dev/pts" ]]; then
      touch "${rootfsdir}${1}"
    else
      mkdir -p "${rootfsdir}${1}"
    fi
    mount "$@"
    [[ $? != 0 ]] && exit 1
  fi
}

function mountdevrunprocsys() {
  domount /sys            "${rootfsdir}/sys"         --rbind --make-rslave
  domount /run            "${rootfsdir}/run"         -t tmpfs  -o nosuid,nodev,mode=0755
  domount /proc           "${rootfsdir}/proc"        -t proc   -o nosuid,noexec,nodev
  if [[ "$optn_n" = true ]]; then
    mkdir -p              "${rootfsdir}/dev"
    touch                 "${rootfsdir}/dev/ptmx"
    ln -sfT /proc/self/fd "${rootfsdir}/dev/fd"
    domount /dev/full     "${rootfsdir}/dev/full"    --rbind --make-rslave
    domount /dev/null     "${rootfsdir}/dev/null"    --rbind --make-rslave
    domount /dev/random   "${rootfsdir}/dev/random"  --rbind --make-rslave
    domount /dev/tty      "${rootfsdir}/dev/tty"     --rbind --make-rslave
    domount /dev/urandom  "${rootfsdir}/dev/urandom" --rbind --make-rslave
    domount /dev/zero     "${rootfsdir}/dev/zero"    --rbind --make-rslave
    domount /dev/pts      "${rootfsdir}/dev/pts"     -t devpts -o newinstance,ptmxmode=0666,mode=0620,gid=5
  else
    domount /dev          "${rootfsdir}/dev"         --rbind --make-rslave
  fi
}

function mountrootboot() {
  if [[ "$optn_n" = true ]]; then
    mkdir -p "${rootfsdir}"
    mount --bind "${rootfsdir}"  "${rootfsdir}"
  else
    mountdev="$(blkid -s PARTLABEL $(parts "${dev}") | grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d' ' -f1 | tr -d :)"
    bootdev="$( blkid -s PARTLABEL $(parts "${dev}") | grep -E 'PARTLABEL="'     | grep -E -- 'boot"'  | cut -d' ' -f1 | tr -d :)"
    echo "Mountdev = ${mountdev}"
    echo "Bootdev  = ${bootdev}"
    [[ -z "${mountdev}" ]] && exit 1
    if [[ "${rootdev}" == "$(realpath "${mountdev}")" ]]; then
      echo "Target device == Root device, exiting!"
      exit 1
    fi
    umount "${mountdev}" 2>/dev/null
    mkdir -p "${rootfsdir}"
    [[ "$optn_b" = true ]] && ro=",ro" || ro=""
    mount --source "${mountdev}" --target "${rootfsdir}" -o exec,dev,noatime,nodiratime$ro
    [[ $? != 0 ]] && exit 1
    if [[ ! -z "${bootdev}" ]]; then
      umount "${bootdev}" 2>/dev/null
      mkdir -p "${rootfsdir}/boot"
      mountoptions="rw,nosuid,nodev,noexec,relatime,nosymfollow,fmask=0077,dmask=0077,codepage=437"
      mountoptions+=",iocharset=ascii,shortname=mixed,utf8,errors=remount-ro"
      mount -t vfat "${bootdev}" "${rootfsdir}/boot" -o "${mountoptions}"
      [[ $? != 0 ]] && exit 1
    fi
  fi
}

function ask() {
  local a items count
  if [[ -z "${!1}" ]]; then
    eval 'items=("${'"${2}"'[@]}")'
    eval 'count=${#'"${2}"'[@]}'
    if [[ ${count} -gt 1 ]]; then
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

function add_children() {
  [[ -z "$1" ]] && return
  echo $1
  local p; for p in $(pgrep -P $1 2>/dev/null) ; do add_children $p; done
}

function kill_children() {
  if [[ ! -z "$1" ]]; then
    local p q
    for q in 1 2; do
      for p in $(add_children $1); do
        kill -s SIGKILL $p &>/dev/null
        wait -f $p 2>/dev/null
        tail --pid=$p -f /dev/null # wait for all, even not a child
      done
    done
  fi
}

function ctrl_c() {
  echo "** Trapped CTRL-C, unshare PID=$unsharedpid **"
  kill_children "$unsharedpid"
  exit
}

function unsharefunction() {
  [[ "$optn_n" = true ]] && local becomeroot="--map-root-user --map-auto" || local becomeroot=""
  unshare $becomeroot --mount --fork --kill-child --pid --uts <<< "$(echo '#!/bin/bash'; type $1)" &
  unsharedpid=$! ; wait -f $unsharedpid ; local rc=$?; kill_children $unsharedpid; unset unsharedpid
  [[ $rc != 0 ]] && exit 1
}

function removeallnoroot() {
  [[ -z "${rootfsdir}" ]] && return
  [[ -d "${rootfsdir}" ]] && rm -rf "${rootfsdir}"
}

function removeallroot() {
  read -p "Type <remove> to delete everything from the card: " prompt <&1
  [[ "${prompt}" != "remove" ]] && exit 1
  (shopt -s dotglob; rm -rf "${rootfsdir}/"*)
}

function setuproot() {
  hostname "${target}"
  mountrootboot
  if [[ "$optn_b" = true ]] ; then backuprootfs ; exit 1; fi
  if [[ "$optn_B" = true ]] ; then restorerootfs; exit 1; fi
  [[ "$optn_R" = true ]] && removeallroot
  mountdevrunprocsys
  [[ ! -d "${rootfsdir}/etc" ]] && bootstrap || bpirrootfs "--noask"
  [[ "$optn_u" = true ]] && uartbootbuild
  [[ "$optn_c" = true ]] && chrootfs
  if [[ "$optn_i" = true ]] || [[ "$optn_x" = true ]] || [[ "$optn_z" = true ]]; then
    cleanupimage
  fi
}

function finish() {
  trap 'true' INT
  trap 'true' EXIT
  echo Cleaning up...
  rm -rf /tmp/bpir-rootfs 2>/dev/null
  if [[ -v rootfsdir ]] && [[ -n "${rootfsdir}" ]] && [[ -d "${rootfsdir}" ]]; then
    restoreresolv
###    rm -vrf "${rootfsdir}/var/lib/apt/lists/partial"
    [[ -d "${rootfsdir}/cachedir" ]] && rm -rf "${rootfsdir}/cachedir"
    if [[ "$optn_n" = true ]]; then
      [[ -d "${rootfsdir}-boot" ]] && mv -vf "${rootfsdir}-boot" "${rootfsdir}/boot"
    else
      [[ -d "./cachedir" ]] && chown -R $SUDO_USER:nobody ./cachedir
      rm -rf "${rootfsdir}"
    fi
    sync
    echo -e "Done. You can remove the card now.\n"
  fi
  if [[ -v loopdev ]] && [[ -n "${loopdev}" ]]; then
    losetup -d "${loopdev}"
  fi
  unset loopdev
  [[ -v noautomountrule ]] && rm -f "${noautomountrule}"
}

function usage() {
 cat <<-EOF
	Usage: $(basename "$0") [OPTION]...
	  -F --format              format sd/emmc or image-file
	  -l --loopdev             create file using loopdev instead of sd-card
	  -n --noroot              create file without root access instead of sd-card
	  -r --rootfs              setup rootfs on image
	  -c --chroot              enter chroot on image
	  -b --backup              backup rootfs
	  -B --restore             restore rootfs
	  -i --createimage         create bpir.img, when using --noroot
	  -x --createxz            create bpir.img.xz
	  -z --creategz            create bpir.img.gz
	  -u --uartboot            create uartboot image
	  -d --cachedir            store packages in cachedir
	  -R --clearrootfs         empty rootfs
	  -N --removenoroot        remove directories created with --noroot
	  -S --disable-sandbox     disable sandbox for kernels not supporting landlock
	  --imagefile [FILENAME]   image file name, default bpir.img
	  --imagesize [FILESIZE]   image file size in Mib, default ${IMAGE_SIZE_MB}
	  --rootstart [ROOTSTART]  sd/emmc: root partition start in MiB, default ${ROOT_START_MB}
	  --rootend [ROOTEND]      sd/emmc: root partition end in MiB or %, default ${ROOT_END_MB}
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

argcnt=0
while getopts ":rlcbxzudniRFBISN-:" opt $args; do
  if [[ "${opt}" == "?" ]]; then
    echo "Unknown option -$OPTARG"
    usage
  elif [[ "${opt}" == "-" ]]; then
    case "$OPTARG" in
      chroot) opt=c ;;
      loopdev) opt=l ;;
      noroot) opt=n ;;
      rootfs) opt=r ;;
      backup) opt=b ;;
      restore) opt=B ;;
      createimage) opt=i ;;
      createxz) opt=x ;;
      creategz) opt=z ;;
      uartboot) opt=u ;;
      cachedir) opt=d ;;
      clearrootfs) opt=R ;;
      format) opt=F ;;
      disable-sandbox) opt=S ;;
      distro)             distro="${!OPTIND}"; ((OPTIND++));;
      distro=*)           distro="${OPTARG#*=}";;
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
      imagefile)          export IMAGE_FILE="${!OPTIND}"; ((OPTIND++));;
      imagefile=*)        export IMAGE_FILE="${OPTARG#*=}";;
      imagesize)          export IMAGE_SIZE_MB="${!OPTIND}"; ((OPTIND++));;
      imagesize=*)        export IMAGE_SIZE_MB="${OPTARG#*=}";;
      rootstart)          export ROOT_START_MB="${!OPTIND}"; ((OPTIND++));;
      rootstart=*)        export ROOT_START_MB="${OPTARG#*=}";;
      rootend)            export ROOT_END_MB="${!OPTIND}"; ((OPTIND++));;
      rootend=*)          export ROOT_END_MB="${OPTARG#*=}";;
      *)
        echo "Unknown option --$OPTARG"
        usage
        ;;
    esac
  fi
  [[ "${opt}" != "-" ]] && declare "optn_${opt}=true" && export "optn_${opt}"
  ((argcnt++))
done

if [[ "$optn_N" = true ]]; then
  export optn_n=true
  ((argcnt++))
fi
if [[ "$optn_n" != true ]]; then
  if [[ $USER != "root" ]] && [[ "$initrd" != true ]]; then
    echo "Running as root user!"
    sudo $0 "${@:1}"
    exit
  fi
fi

[[ "$optn_l" = true ]] && ((argcnt--))
[[ "$optn_n" = true ]] && ((argcnt--))
[[ "$optn_d" = true ]] && ((argcnt--))
[ $argcnt -eq 0 ] && export optn_c=true
if [[ "$optn_l" = true ]]; then
  if [[ "$initrd" = true ]]; then
    echo "Loopdev not supported in initrd!"
    exit 1
  fi
  [[ $argcnt -eq 0 ]] && [[ ! -f "${IMAGE_FILE}" ]] && export optn_F=true
fi
[[ "$optn_F" = true ]] && export optn_r=true

trap finish EXIT
trap ctrl_c INT
shopt -s extglob

echo "Current dir:" $(realpath .)

hostarch="$(uname -m)"
echo "Host Arch: ${hostarch}"

if [[ "$initrd" != true ]]; then
  if [[ ! -f "/etc/arch-release" ]]; then ### Ubuntu / Debian
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN; do
      [[ "${hostarch}" == "aarch64" ]] && [[ "${package}" =~ "qemu-user" ]] && continue
      if ! dpkg -l $package >/dev/null; then missing+=" ${package}"; fi
    done
    instcmd="sudo apt-get install $missing"
  else
    for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ALARM; do
      [[ "${hostarch}" == "aarch64" ]] && [[ "${package}" =~ "qemu-user" ]] && continue
      if ! pacman -Qi $package >/dev/null; then missing+=" ${package}"; fi
    done
    instcmd="sudo pacman -Syu $missing"
  fi
  if [[ ! -z "$missing" ]]; then
    echo -e "\nInstall these packages with command:\n${instcmd}\n"
    exit 1
  fi
  rootdevice="$(mount | grep -E '\s+on\s+/\s+' | cut -d' ' -f1)"
  rootdev="$(lsblk -sprno name "${rootdevice}" | tail -2 | head -1)"
  echo "rootdev=${rootdev} , do not use."
  [[ -z "${rootdev}" ]] && exit 1
  pkroot="$(lsblk -srno name "${rootdevice}" | tail -1)"
  echo "pkroot=${pkroot} , do not use."
  [[ -z "${pkroot}" ]] && exit 1
else
  rootdev="undefined"
  pkroot="undefined"
fi

[ -f "config.sh" ] && source config.sh

if [[ "$optn_F" = true ]]; then
  ask target TARGETS "Choose target to format image for:"
  setupenv # Now that target is known.
  ask device devices "Choose device to format image for:"
  if [[ "$optn_l" = true ]]; then
    [[ ! -f "${IMAGE_FILE}" ]] && touch "${IMAGE_FILE}"
    loopdev="$(losetup --show --find "${IMAGE_FILE}" 2>/dev/null)"
    echo "Loop device = ${loopdev}"
    dev="${loopdev}"
  elif [[ "$optn_n" = true ]]; then
    dev="none"
  else
    readarray -t devs < <(lsblk -dprno name,size \
       | grep -v "^/dev/${pkroot}" | grep -v 'boot0 \|boot1 \|boot2 ')
    ask dev devs "Choose device to format:"
  fi
else
  if [[ "$optn_l" = true ]]; then
    loopdev="$(losetup --show --find "${IMAGE_FILE}")"
    echo "Loop device = $loopdev"
    partprobe "${loopdev}"; udevadm settle
    dev="${loopdev}"
  elif [[ "$optn_n" = true ]]; then
    dev="none"
  else
    readarray -t devs < <(blkid -s PARTLABEL | \
        grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    ask dev devs "Choose device to work on:"
    dev="$(lsblk -npo pkname "${dev/:/}")"
  fi
  if [[ "${dev}" != "none" ]]; then
    pr=$(blkid -s PARTLABEL $(parts ${dev})| grep -E 'PARTLABEL="bpir' | grep -E -- '-root"' | cut -d'"' -f2)
    target=$(echo "${pr}" | cut -d'-' -f1)
    device=$(echo "${pr}" | cut -d'-' -f2)
  else
    readarray -t dirs < <(ls -1a -d image-*-*-*)
    ask rootfsdir dirs "Choose directory to work on:"
    [[ -z "${rootfsdir}" ]] && exit 1
    rootfsdir="$(realpath "${rootfsdir}")"
    target=$(cat "${rootfsdir}/etc/rootcfg/target" 2>/dev/null)
    device=$(cat "${rootfsdir}/etc/rootcfg/device" 2>/dev/null)
  fi
fi
echo -e "Dev=${dev}\nTarget=${target}\ndevice="${device}
[ -z "${dev}" ] && exit 1

export -f $(typeset -F | cut -d' ' -f 3)
export arch target device dev

if [[ -n "${target}" ]] && [[ -n "${device}" ]]; then
  setupenv # Now that target and device are known.
  if [[ "$optn_r" = true ]]; then
    if [[ "$optn_F" = true ]]; then
      ask distro DISTROS "Choose distro to create root for:"
      echo "Distro=${distro}"
    fi
    bpirrootfs "--menuonly"
  fi
  # Check if 'config.sh' exists.  If so, source that to override default values.
  [[ -f "config.sh" ]] && source config.sh
  if [[ "$optn_l" = true ]] && [[ $(stat --printf="%s" $IMAGE_FILE) -eq 0 ]]; then
    dd if=/dev/zero of="${IMAGE_FILE}" bs=1 count=0 seek=${IMAGE_SIZE_MB}M
    losetup --set-capacity "${dev}"
  fi
  if [[ "$initrd" != true ]] && [[ "$optn_n" != true ]]; then
    mkdir -p "/run/udev/rules.d"
    noautomountrule="/run/udev/rules.d/10-no-automount-bpir.rules"
    echo 'KERNELS=="'${dev/'/dev/'/}'", ENV{UDISKS_IGNORE}="1"' > "${noautomountrule}"
  fi
  if [[ -z "${rootfsdir}" ]]; then
    if [[ "$optn_n" = true ]]; then
      rootfsdir="$(realpath "image-${target}-${device}-${distro}")"
    else
      rootfsdir="/tmp/bpirootfs.$$"
    fi
  fi
  echo "Rootfsdir=${rootfsdir}"
  export rootfsdir distro ddrsize setup brlanip
  if [[ "$optn_d" = true ]]; then
    mkdir -p ./cachedir
    if [[ "$optn_n" != true ]]; then
      chmod -R 755               ./cachedir
      chown -R $SUDO_USER:nobody ./cachedir
    fi
  fi
  [[ "$optn_F" = true ]] && unsharefunction formatimage

  unsharefunction setuproot
fi

finish

if [[ "$optn_n" = true ]] && [[ "$optn_i" = true ]]; then
  unsharefunction createimage
fi

if [[ "$optn_N" = true ]] ; then
  echo "Removing noroot directory..."
  unsharefunction removeallnoroot
fi

if [[ "$optn_x" = true ]] || [[ "$optn_z" = true ]]; then
  compressimage
fi

exit

# gpg --export DD73724DCA27796790D33E98798137154FE1474C | gpg --dearmour -o /tmp/ericwoud.gpg

