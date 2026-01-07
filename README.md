# buildR64arch

Install a minimal ArchLinux-ARM or Ubuntu on Banana Pi R64, R3, R3mini and R4 from scratch.

Downloadable images for quick test located [HERE](https://www.woudstra.mywire.org/images/)

R64 Notes:
Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file rootfs/boot/dtbos/cpu-thermal.dts before building, if you do not want to.

R4 Notes:
Still in development stage, basics work, need more testing.

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated using `pacman` or `apt`.
It is also possible to build/alter a package yourself using makepkg (and makedeb), like any other Archlinux package.

Basic settings are prompted for, when running the script. Other tweaks can be written to config.sh in the
same directory as the script. There the environment variables can be set, that will override the default settings.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

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

```
git clone https://github.com/ericwoud/buildR64arch.git
```

Change directory

```
cd buildR64arch
```

Set `SD_ERASE_SIZE_MB` in build.sh if using a cardreader with naming /dev/sdX. Only from a cardreader with naming /dev/mmcblkX
it is possible to read the erase size. Using this kind of reader the script will automatically read the erase size.
The default value of 4MB is ok for most cards if you do not know the erase size. Later you can read it when the sd-card is inserted in a running bpir64/3.

Now format your SD card with:

```
./build.sh -F
```
After formatting the rootfs gets build.

Optionally enter chroot environment on the SD card:

```
./build.sh
```

This script is also available when running linux on the board. It is also available from the initramdisk.

## Deployment

Insert the SD card,, powerup, connect to the R64/R3 wireless, SSID: WIFI24, password: justsomepassword. To start ssh to R64/R3, password admin
```
ssh root@192.168.5.1
```
For standard router setup. IPforward is on.
```
ssh root@192.168.1.33
```
For standard access point setup.

After this, you are on your own. It is supposed to be a minimal installation of Arch Linux.

## Ubuntu instead of ArchLinuxARM (EXPERIMENTAL)

It is possible to build an image with Ubuntu instead. Any executables within my custom packages are build as static binaries, so they can be executed independantly of os.


## R64 Build/Install emmc version using script again

When building on R64 (running on sd-card) start/re-enter a screen session with:
```
screen -R
```
Detach from the session if you want, with CTRL-A + D.

When running on the R64, clone the script and run:
```
./build.sh -F
```
Make sure your internet connection is working on the R64. Ping 8.8.8.8 should work.

Choose `emmc` in the script instead of `sdmmc`. Now format the emmc and let it setup rootfs.


## Changing kernel commandline options or devicetree overlays

When changing the kernel commandline options in `/boot/bootcfg/cmdline` or changing/adding/removing devicetree overlays in `/boot/dtbos`
you should run the folling command on the bpir64/3 to write the changes so that they will be activated on the next boot:
```
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

```p
bpir-toolbox --nand-format
```
This will format and install the image.

I need to add more documentation about 'bpir-toolbox', but you can look into the file to see which options to use.

```p
bpir-toolbox --nand-force-erase
```
This will erase all blocks from nand, even erase all the bad blocks, all blocks are reset to normal.

'bpir-build' to install archlinuxarm (or experimental ubuntu) on nvme is added pretty recently also, so also needs documentation and testing. Basically the steps are:

`bpir-build` can be run from the sd-card image, but it can also be run when booted the initrd on nand. When booted from nand, first use `bpir-dhcpd` to connect to the internet again. Once connected to the internet you can use:

```
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

Make sure you have socat installed, edit /dev/ttyXXXX, and run :

```
sudo bash -c "./mtk_uartboot -p uart-bpir3m-atf.bin -f uart-bpir3m-fip.bin --aarch64 -s /dev/ttyUSB0 ; socat - /dev/ttyUSB0,raw,echo=0,b115200"
```

The files are quite large, so get a cup of coffee when uploading it to the board.

It has the initrd for emmc inside, which drops to a bash shell. The initrd can run my installscript and/or debootstrap. First setup your internet connection on eth0 or any other interface (defaults to wan):

```p
bpir-dhcpc eth0
```
Now you're ready to use 'bpir-build' 'bpir-toolbox' 'debootstrap' 'wget' 'curl' 'nano' 'parted' 'mkfs-btrfs' 'tar' 'xz' 'gzip' 'zstd', etc, etc.

You could use:
```p
bpir-toolbox --nand-format
```
It will download necessary files and install uboot on nand. This version of U-Boot uses the standard distroboot and is setup to scan sd/emmc - nvme - nand, for extlinux.conf in this order. Need to have the boot flag set on the partition where this file can be found. If nothing is found on sd/emmc/nvme, it loads the same rescue initrd, but now from nand.

I need to add more documentation about 'bpir-toolbox', but you can look into the file to see which options to use. 'bpir-build' to install on nvme is added pretty recently also, so also needs documentation and testing.

Run
```
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


## R64/R3 Build/Install emmc version using image [DEPRECATED]

Create an SD card for the R64/R3.
```
./build.sh -F
```
Create an EMMC image for the R64/R3 and have it compressed.
```
./build.sh -lFx
```
Then copy the bpir.img.gz to the SD card /tmp/ folder. It is accessable without root.

If using a pre-build image, rename it to `bpir.img.gz`

Boot the R64/R3 with the SD card with UART connected. When kernel starts keep 'shift E' keys pressed. When finised, you can reboot.

You can keep 'x' pressed instead if you want to enter a shell.

Note for R3: To run on EMMC, only the switch most near to powerplug (D) should be down, the rest up.
This is different from the normal switch settings. It is done so that you do not need mmcblk0boot0.

## R3-MINI & R4 Build/Install emmc version using image (openwrt on nand)

Create an EMMC card for the R3-MINI/R4 and have it compressed to a .gz file.
```
./build.sh -lFz
```
Then copy the bpir.img.gz to a FAT formatted usb-stick and plug it in to the board.

Boot the board in NAND mode with UART connected. Boot to Openwrt Busybox command prompt.

```
echo 0 > /sys/block/mmcblk0boot0/force_ro
gunzip -c /mnt/sda1/bpir.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
dd if=/dev/mmcblk0 of=/dev/mmcblk0boot0 bs=17K skip=1 count=32 conv=fsync
mmc bootpart enable 1 1 /dev/mmcblk0
```

Switch boot-switch to EMMC and reboot.

## Using pre-build images for a quick try-out

On my site you will find downloadable images at the release branches. Prefer to use the script.

https://ftp.woudstra.mywire.org/images/

Write the image file for sd-card to the appropriate device, MAKE SURE YOU HAVE THE CORRECT DEVICE!
```
gunzip -c ~/Downloads/bpir64-sdmmc.img.gz | sudo dd of=/dev/sda
```

## TODO:

* Implement 802.11k 802.11r 802.11v.
* Guest WIFI


## Features

Command line options:

Check the commands ./build.sh (bpir-build), bpir-toolbox and bpir-rootfs help function
for information how to use the commands.


## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)
