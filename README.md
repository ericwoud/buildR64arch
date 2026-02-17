# buildR64arch

Install a minimal ArchLinux-ARM or Ubuntu on Banana Pi R64, R3, R3mini and R4 from scratch.

Downloadable images for quick test located [HERE](https://ftp.woudstra.mywire.org/images/)

R64 Notes:
Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file rootfs/boot/dtbos/cpu-thermal.dts before building, if you do not want to.

R4 Notes:
Still in development stage, basics work, need more testing.

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated using `pacman` or `apt`.
It is also possible to build/alter a package yourself using `makepkg` (and `makedeb`), like any other Archlinux package.

Basic settings are prompted for, when running the script. Other tweaks can be written to config.sh in the
same directory as the script. There the environment variables can be set, that will override the default settings.

The script is in development and uses sudo. Any bug may possibly delete everything permanently! Only using the `--noroot` option, an image can be build without root access.

USE AT YOUR OWN RISK!!!


## Getting Started

You need:

  - Banana Pi R64, R3, R3mini or R4
  - SD card

### Choose your setup

There are basically 2 setups to choose from. RouTer and AccessPoint. Some extra variants are added, according to the selected board/hardware.

1. RouTer setup sets up the wan port (optionally a sfp port) as a dhcp client. It should get an IP number from your main router or modem or such. The lan ports and wlan interfaces are all setup in 1 bridge, called brlan. The bridge is setup with IP number 192.168.5.1. The bpi's wan port should be connected to a lan port of your main router/modem. Traffic from brlan is forwarded to wan, using masquerade. Clients connecting to your bpi board are getting an IP number from the dhcp server listening on brlan bridge.

2. AccessPoint sets up all ports and wlan interfaces under 1 bridge called brlan. The bridge is setup with IP number 192.168.1.33. The bpi board should be connected lan-lan with your main router. The subnet should match the subnet of your router's lan subnet (first 3 numbers of IP). If not matching, then edit either one to match. Clients connecting to your bpi board are bridged with your router/modem so they should get an IP through your main router/modem's dhcp server.

If you have 2 bpi boards you can setup 1 as RouTer and 1 as AccessPoint. If you use matching ssid's and passwords and you can use Fast Transition roaming to roam smoothly from one to another bpi board.

### Installing

Clone from Git

```text
git clone https://github.com/ericwoud/buildR64arch.git
```

Change directory

```text
cd buildR64arch
```

Format your SD card with:

```text
./build.sh -F
```
After formatting the rootfs gets build.

Use for `./build.sh -F --erasesize=XX` if using a cardreader with naming /dev/sdX. Using a reader with /dev/mmcblkX the script will automatically read the erase size. For readers with /dev/sdX the default value of 4MiB is ok for most cards. If you do not know the erase size, later you can read it when the sd-card is inserted in a running bpir64/3. `cat /sys/block/mmcblk0/device/preferred_erase_size` will show it in bytes.

Optionally enter chroot environment on the SD card:

```text
./build.sh
```

This script is also available when running linux on the board. It is also available from the initramdisk.

## Deployment

Insert the SD card,, powerup, connect to the R64/R3 wireless, SSID: WIFI24, password: justsomepassword. To start ssh to R64/R3, password admin
```text
ssh root@192.168.5.1
```
For standard router setup. IPforward is on.
```text
ssh root@192.168.1.33
```
For standard access point setup.

After this, you are on your own. It is supposed to be a minimal installation of Arch Linux.

## Building image file instead of building directly on device

Using the `-l | --loopdev` option uses a loopdevice instead of the real device, but this still needs root access.

Now with the `-n | --noroot` option, the script builds an image- root directory, no root access is needed. The user is mapped to the root user in a namespace.

Adding `-F | --format` the image is formatted, or the directories cleared.

Adding `-i | --createimage` an image is created from them.

Adding `-z | --creategz` the image file is compressed.

So:

```text
./build.sh --noroot --format --createimage --creategz
```
Or in short:
```text
./build.sh -nFiz
```
You can use the menu to choose the rest of the options.
Or choose all options from commandline:
```text
./build.sh -nFiz --target=bpir3 --device=sdmmc --ddrsize=default --setup=RT --distro=alarm --brlanip=default --cachedir --disable-sandbox
```
Deleting the image- root directory, without using sudo, may run into permission issues. Use:
```text
./build.sh -N
```
To remove them.

## Using chroot to change image before final creation

First create root filesystem:
```text
./build.sh -nF
```
Then:
```text
./build.sh -n --chroot
```
To enter it with chroot and mapped to the root user, make some changes, exit with `exit` command.

Then create bpir.img.gz
```text
./build.sh -niz
```

## Ubuntu instead of ArchLinuxARM (EXPERIMENTAL)

It is possible to build an image with Ubuntu instead. Any executables within my custom packages are build as static binaries, so they can be executed independantly of os.


## R64 Build/Install emmc version using script again

When building on R64 (running on sd-card) start/re-enter a screen session with:
```text
screen -R
```
Detach from the session if you want, with CTRL-A + D.

When running on the R64 run:
```text
bpir-build -F
```
Make sure your internet connection is working on the R64. Ping 8.8.8.8 should work.

Choose `emmc` in the script instead of `sdmmc`. Now format the emmc and let it setup rootfs.


## Changing kernel commandline options or devicetree overlays

When changing the kernel commandline options in `/boot/bootcfg/cmdline` or changing/adding/removing devicetree overlays in `/boot/dtbos`
you should run the folling command on the bpir64/3 to write the changes so that they will be activated on the next boot:
```text
bpir-toolbox --write2fip
```
If something goes wrong and you cannot boot, insert the card in your laptop/computer and use the chroot option to undo the changes. Then use the `bpir-writefip` command again. On EMMC (specially on the R3) it will be much more complicated.


## All boards: NAND distro-boot + linux-recovery [RECOMMENDED]

This method is now the prefered method of installing other then SD-card. Just get this installed on NAND, set switches to NAND and you can boot linux from sdmmc/emmc/nvme/nand. The nand image contains:

U-Boot that scans emmc/nvme/nand for (/boot)/extlinux/extlinux.conf and boots it. Alternatively it scans for a boot.scr, see [example howto create a bootscr for distroboot](https://wiki.gentoo.org/wiki/PINE64_ROCKPro64/Installing_U-Boot#Creating_boot.scr), but extlinux.conf is preferred, boot.scr only for backward compatibility.

The partition that contains this file needs to have the boot flag set.

If it fails on emmc and nvme, it boots the linux initramdisk on nand. It contains
all basic utilities needed to setup an internet connection and install any distro.

There are some basic utilities on the initrd, but perhaps it is still missing some tools and/or kernel modules.
It contains my bpi router scripts bpir-build bpir-toolbox, but also:
 debootstrap wget curl nano parted mkfs-btrfs tar xz gzip zstd, etc, etc.

> Note: All images (sdmms/emmc/nvme/uart) all have the same initramdisk. You can interrupt normal boot by keeping 'x' pressed during  early **linux** booting. You will then enter a bash shell from initramdisk.

Setup my archlinuxarm image on sd-card, via my script or prebuild image. Another possibility is to use my uartboot image, specially usefull for the R3-mini.


	UARTBOOT ONLY
	
	After booting from uartboot, first make internet connection with:
	
	bpir-dhcpc <interfacename>
	
	bpir-toolbox needs to download some files needed to build the image, only when booting from uart. SD image has all included.

When running archlinuxarm from sd-card or the initrd from uartboot on the BPI-R3/R3M/R4, you can:

```text
bpir-toolbox --nand-format
```
This will format and install the image.

```text
bpir-toolbox --nand-force-erase
```
This will erase all blocks from nand, even erase all the bad blocks, all blocks are reset to normal.

'bpir-build' to install archlinuxarm (or experimental ubuntu) on nvme is added pretty recently also, so also needs documentation and testing. Basically the steps are:

`bpir-build` can be run from the sd-card image, but it can also be run when booted the initrd on nand. When booted from nand, first use `bpir-dhcpd` to connect to the internet again. Once connected to the internet you can use:

```text
bpir-build -F
```
 and go through the menu.

But of course you can just manually use parted and debootstrap to install any other distro. Add extlinux.conf and set the bootflag. You will need to find a suitable linux kernel then also.

If you have used bpir-build to build the nvme/emmc rootfs, you can also use the same tool when running from the initramdisk to enter it via chroot. Just run the command without arguments.

This all needs more testing...


## Recovery UART boot to a linux rescue image

The files can be found here:

[https://ftp.woudstra.mywire.org/uartboot/](https://ftp.woudstra.mywire.org/uartboot/)

Find the correct `mtk_uartboot` executable for your system. I have build files for the R64, R3, R3mini, R4. Only the R3 is tested at the moment.

Run:
```text
sudo ./mtk_uartboot -p uart-bpir3m-atf.bin -f uart-bpir3m-fip.bin --aarch64 -s /dev/ttyUSB0
```

Or, when wanting to see the debug output after uploading. Make sure you have socat installed, edit /dev/ttyXXXX, and run :
```text
sudo bash -c "./mtk_uartboot -p uart-bpir3m-atf.bin -f uart-bpir3m-fip.bin --aarch64 -s /dev/ttyUSB0 ; socat - /dev/ttyUSB0,raw,echo=0,b115200"
```

The files are quite large, so get a cup of coffee when uploading it to the board.

It has the initrd for emmc inside, which drops to a bash shell. The initrd can run my installscript and/or debootstrap. First setup your internet connection on eth0 or any other interface (defaults to wan):

```text
bpir-dhcpc eth0
```
Now you're ready to use 'bpir-build' 'bpir-toolbox' 'debootstrap' 'wget' 'curl' 'nano' 'parted' 'mkfs-btrfs' 'tar' 'xz' 'gzip' 'zstd', etc, etc.

You could use:
```text
bpir-toolbox --nand-format
```
It will download necessary files and install uboot on nand. This version of U-Boot uses the standard distroboot and is setup to scan sd/emmc - nvme - nand, for extlinux.conf in this order. Need to have the boot flag set on the partition where this file can be found. If nothing is found on sd/emmc/nvme, it loads the same rescue initrd, but now from nand.

I need to add more documentation about 'bpir-toolbox', but you can look into the file to see which options to use. 'bpir-build' to install on nvme is added pretty recently also, so also needs documentation and testing.

Run
```text
bpir-build -F
```
and go through menu to install on nvme


## Different bootchains supported

There are now 4 different bootchains supported, tested on R3 (R64 not yet tested, but should work). First make sure you are using the latest 'atf' with the following command: `pacman -Sy bpir64-atf-git`

1. ATF - KERNEL using `fip` partition.

2. ATF - KERNEL using `boot` partition. Default boot method. The latest atf can boot from `boot` partition instead of `fip` partition, see https://forum.banana-pi.org/t/bpi-r3-bpi-r64-atf-with-fat32-load-capabilities/15345 . ATF will directly load the kernel from the boot (fat32) partition. Change your setup with the following command: `bpir-toolbox --fip2boot`. It will rename the fip partiion to the boot partition and move all files from boot folder to boot partition. Change back to `fip` with `bpir-toolbox --boot2fip`.

3. ATF - UBOOT - KERNEL using `boot` partition. U-Boot uses distro-boot to keep the package simple, using a flexible startup environment. Use `bpir-toolbox --uboot-install`. At boot, U-Boot will be loaded from `/boot/u-boot.bin`

4. ATF - UBOOT - KERNEL using `fip` partition. When still booting with `fip` partition and having u-boot installed,  use `bpir-toolbox --uboot-install`. At boot, U-Boot will be loaded from fip.


## Setup as Access Point

When using a second or third R64/R3 as Access Point, and connecting router-lan-port to AP-lan-port, do the following:

Choose Setup "AP" in stead of "RT".

The Access Point has network address 192.168.1.33.

For vlan setup the lan ports which connect router and AP as lan-trunk port on both router and AP.

Some DSA drivers have a problem with this setup, but some are recently fixed with a fix wireless roaming fix in the kernel. You will need very recent drivers on all routers/switches and access points on your network

## Detailed description

The entire image is build around packages. All custom packages have .deb and .pkg.tar.xz versions for Ubuntu and Archlinux.
The major difference (specially on headless systems) between Archlinux and Debian is the package manager. Other differences are really small. This makes the images for ArchLinux-ARM and Ubuntu almost identical. Because library versions can differ, all custom executables are build statically with musl, not depending on any library.

- bpirXX-atf-git package contains ATF binairies, command needed for writing. Customized all-in-one (bl2 + bl31), booting U-Boot or linux from fip- or fat32-boot partition.
- bpirXX-uboot-git package contains U-Boot binairies, command needed for writing. Customized to boot from extlinux conf or boot.scr.
- linux-bpirXX-git package contains kernel, automatically written when upgrading. Multiple linux kernel packages can be installed.
- hostapd-launch: helper for hostapd.conf, adding interface specifying bridge vlan id. Also implements bash substitution inside the .conf file.
- ssh-fix-reboot: shutdown ssh session quickly at reboot

Prebuild images:

[https://ftp.woudstra.mywire.org/images/](https://ftp.woudstra.mywire.org/images/)

UARTboot images:

[https://ftp.woudstra.mywire.org/uartboot/](https://ftp.woudstra.mywire.org/uartboot/)

Prebuild Nand images (still need to test, easier to use bpir-toolbox from sd-card instead):

[https://ftp.woudstra.mywire.org/nandimages/](https://ftp.woudstra.mywire.org/nandimages/)

## Command available from build-host as `./build.sh` or from board as `bpir-build` in linux and initramfs. It is mostly menu driven.
```text
Usage: build.sh [OPTION]...
  -F --format              format sd/emmc or image-file
  -l --loopdev             create file using loopdev instead of sd-card
  -n --noroot              create file without root acces instead of sd-card
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
  -S --enable-sandbox      enable sandbox for kernels supporting landlock
  --imagefile [FILENAME]   image file name, default bpir.img
  --imagesize [FILESIZE]   image file size in Mib, default 7456
  --rootstart [ROOTSTART]  sd/emmc: root partition start in MiB, default 256
  --rootend [ROOTEND]      sd/emmc: root partition end in MiB or %, default 100%
  --brlanip [default|IP]   ip for brlan
  --ddrsize [default|8]    ddr size in GB
  --setup [AP|RT|...]      setup for network
  --target [bpir64|bpir3|bpir3m|bpir4]   specify target
  --device [sdmmc|emmc|nvme|sata]        specify device```
```
Start with `--format` to format a sdcard/image.
Use `--loopdev` or `--noroot` to create an image instead of using a sd-card directly.
Use `--cachedir` when trying multiple times, but not downloading packages multiple times.

After building use `--chroot` (with --loopdev) to enter the image and do some more setting up manually.

## Custom commands available from board in linux and initramfs or chroot (and uartboot):
```text
Usage: bpir-toolbox [OPTION]...
  --default-bootcfg        Restore default bootcfg, adds --write2fip
  --fip2boot               Convert fip partition to boot partition bootchain (sd/emmc)
  --boot2fip               Convert boot partition to fip partition bootchain (sd/emmc)
  --download2root          Download files needed for nand-image (when started from initrd)
  --nand-force-erase       Force erase nand, including bad blocks and wear history
  --nand-format            Format the nand, also runs update
  --nand-image             Create nand image, also runs update
  --nand-update            Updates all files on nand, only writes when needed
  --write2dtb              Combine dtbos with dtb and create one dtb file
  --write2atf              Write arm-trusted-firmware
  --write2fip              Create all files needed for fip and write it, adds --write2dtb
  --write2extlinux         Create a new /boot/extlinux/extlinux.conf
  --uboot-install          Copies U-Boot to /boot/u-boot.bin (writes to fip if necessary),
                             also creates /boot/extlinux/extlinux.conf if not present
  --uboot-remove           Removes /boot/u-boot.bin
  --uartboot               Create a uartboot image
  --pkgbase ...            Specify linuxpkg to create files for
  --set-atf-linuxpkg       Set linuxpkg atf will directly boot, specified in pkgbase
  --remove-dtb             Remove dtb file
```
```text
Usage: bpir-rootfs [OPTION]...
  -i --brlanip [IP]                       specify ip for brlan
  -d --ddrsize [default|8]                specify ddr size
  -s --setup [AP|RT|...]                  specify setup for network
  -t --target [bpir64|bpir3|bpir3m|bpir4] specify target
     --device [sdmmc|emmc|nvme|sata]      specify device
  -S --disable-sandbox     disable pacman sandbox download
  -n --noask               don't ask to alter rootfs and reset passwords and root access
  -u --adduser [USER]      add user named USER
  -m --menuonly            menu only
```
`bpir-rootfs` is menu-driven, arguments can be used instead.
```text
Usage: bpir-initrd [OPTION]...
  -p --preset [PRESET]       specify preset
  -P --allpresets            build all presets
  -m --modulesonly           build only when image holds modules [to be implemented]
```
All other linux commands available, including bpir-build and fiptool.

## Commands available from board in initramfs (and uartboot):
```text
bpir-dhcpc <interface>
bpir-synctime
bpir-build
bpir-toolbox
reboot
bash, debootstrap, nano, parted, etc
```

## Building your own version of ATF, U-Boot or linux-kernel:

Basically all custom ATF, U-Boot or linux-kernel packages are build on Archlinux (aarch64 or x86_64). It can be done on a archlinux-chroot if preferred. Use [https://github.com/tokland/arch-bootstrap](https://github.com/tokland/arch-bootstrap) to setup an archlinux chroot on a debian system.

After running makepkg, run makedeb to create the .deb (and possibly update a repo). See: [makedeb](https://github.com/ericwoud/archlinuxarm-repo/blob/makedeb/makedeb)

Support to install linux-image.deb created with other tool when running on Ubuntu is also implemented, but hardly tested (also supporting to extract `Image` from `.itb` from the package).

## R64/R3 Build/Install emmc version using image [DEPRECATED]

Create an SD card for the R64/R3.
```text
./build.sh -F
```
Create an EMMC image for the R64/R3 and have it compressed.
```text
./build.sh -lFz
```
Then copy the bpir.img.gz to the SD card /tmp/ folder. It is accessable without root.

If using a pre-build image, rename it to `bpir.img.gz`

Boot the R64/R3 with the SD card with UART connected. When kernel starts keep 'shift E' keys pressed. When finised, you can reboot.

You can keep 'x' pressed instead if you want to enter a shell.

Note for R3: To run on EMMC, only the switch most near to powerplug (D) should be down, the rest up.
This is different from the normal switch settings. It is done so that you do not need mmcblk0boot0.

## R3-MINI & R4 Build/Install emmc version using image (openwrt on nand)

Create an EMMC card for the R3-MINI/R4 and have it compressed to a .gz file.
```text
./build.sh -lFz
```
Then copy the bpir.img.gz to a FAT formatted usb-stick and plug it in to the board.

Boot the board in NAND mode with UART connected. Boot to Openwrt Busybox command prompt.

```text
echo 0 > /sys/block/mmcblk0boot0/force_ro
gunzip -c /mnt/sda1/bpir.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync,sparse
dd if=/dev/mmcblk0 of=/dev/mmcblk0boot0 bs=17K seek=1 count=32 conv=fsync
mmc bootpart enable 1 1 /dev/mmcblk0
```

Switch boot-switch to EMMC and reboot.

## Using pre-build images for a quick try-out

On my site you will find downloadable images at the release branches. Prefer to use the script.

https://ftp.woudstra.mywire.org/images/

Write the image file for sd-card to the appropriate device, MAKE SURE YOU HAVE THE CORRECT DEVICE!
```text
gunzip -c ~/Downloads/bpir64-sdmmc.img.gz | sudo dd of=/dev/sda bs=4M conv=fsync,sparse
```

## TODO:

* Implement 802.11k 802.11r 802.11v.
* Guest WIFI


## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)
