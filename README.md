# buildR64arch

Install a minimal Arch-Linux on Banana Pi R64 or R3 from scratch.

Old: Downloadable image for quick test located [HERE](https://github.com/ericwoud/buildR64arch/releases/download/v1.2/bpir64-sdmmc.img.xz)

Based on: [buildR64ubuntu](https://github.com/ericwoud/buildR64ubuntu.git)
, [openwrt atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
and [frank-w's kernel](https://github.com/frank-w/BPI-Router-Linux)

R64 Notes:
Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file rootfs/boot/dtbos/cpu-thermal.dts before building, if you do not want to.

R3 Notes:
Still in development stage, basics work, need more testing.

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated through the AUR.
It is also possible to build/alter a package yourself, like any other Archlinux AUR package.

Basic settings are prompted for, when running the script. Other tweaks can be written to config.sh in the
same directory as the script. There the environment variables can be set, that will override the default settings.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

R3: [Download v1.3 SD card version Router setup (301MB)](https://github.com/ericwoud/buildR64arch/releases/download/v1.3/bpir3-RTnoSFP.img.xz) Kernel version v6.3.10 (linux-rolling-stable)

R64: [Download v1.3 SD card version Router setup (301MB)](https://github.com/ericwoud/buildR64arch/releases/download/v1.3/bpir64-RT.img.xz) Kernel version v6.3.10 (linux-rolling-stable)


## Getting Started

You need:

  - Banana Pi R64 or R3
  - SD card


### Installing

Clone from Git

```
git clone https://github.com/ericwoud/buildR64arch.git
```

Change directory

```
cd buildR64arch
```

Install all necessary packages with:
```
./build.sh -a
```
Set `SD_ERASE_SIZE_MB` in config.sh if using a cardreader with naming /dev/sdX. Only from a cardreader with naming /dev/mmcblkX
it is possible to read the erase size. Using this kind of reader the script will automatically read the erase size. 
4MB is ok for most cards if you do not know the erase size. Later you can read it when the sd-card is inserted in a running bpir64/3.

Now format your SD card with:

```
./build.sh -F
```
After formatting the rootfs gets build.

Optionally enter chroot environment on the SD card:

```
./build.sh
```


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


## R64/R3 Build/Install emmc version using image

Create an SD card for the R64/R3.
```
./build.sh -F
```
Create an EMMC image for the R64/R3 and have it compressed.
```
./build.sh -lFx
```
Then copy the bpir.img.xz to the SD card /tmp/ folder. It is accessable without root.

If using a pre-build image, rename it to `bpir.img.xz`

Boot the R64/R3 with the SD card with UART connected. When kernel starts keep 'shift E' keys pressed. When finised, you can reboot. 

You can keep 'x' pressed instead if you want to enter a busybox ash.

Note for R3: To run on EMMC, only the switch most near to powerplug (D) should be down, the rest up.

## R3-MINI & R4 Build/Install emmc version using image

Create an EMMC card for the R3-MINI and have it compressed to a .gz file.
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

On github you will find downloadable images at the release branches. R64 only for now, image can be quite old. Prefer to use the script.

Write the image file for sd-card to the appropriate device, MAKE SURE YOU HAVE THE CORRECT DEVICE!
```
xz -dcv ~/Downloads/bpir64-sdmmc.img.xz | sudo dd of=/dev/sda
```


## Changing kernel commandline options or devicetree overlays

When changing the kernel commandline options in `/boot/bootcfg/cmdline` or changing/adding/removing devicetree overlays in `/boot/dtbos`
you should run the folling command on the bpir64/3 to write the changes so that they will be activated on the next boot:
```
bpir-writefip
```
If something goes wrong and you cannot boot, insert the card in your laptop/computer and use the chroot option to undo the changes. Then use the `bpir-writefip` command again. On EMMC (specially on the R3) it will be much more complicated.


## Different bootchains supported

There are now 4 different bootchains supported, tested on R3 (R64 not yet tested, but should work). First make sure you are using the latest 'atf' with the following command: `pacman -Sy bpir64-atf-git`

1. ATF - KERNEL using `fip` partition. Default boot method.

2. ATF - KERNEL using `boot` partition. The latest atf can boot from `boot` partition instead of `fip` partition, see https://forum.banana-pi.org/t/bpi-r3-bpi-r64-atf-with-fat32-load-capabilities/15345 . ATF will directly load the kernel from the boot (fat32) partition. Change your setup with the following command: `bpir-writefip --fip2boot`. It will rename the fip partiion to the boot partition and move all files from boot folder to boot partition. Change back to `fip` with `bpir-writefip --boot2fip`

3. ATF - UBOOT - KERNEL using `boot` partition. U-Boot uses distro-boot to keep the package simple, using a flexible startup environment. With `boot` partition present execute the following command:`pacman -Sy bpir-uboot-git` . U-Boot will be loaded from `/boot/u-boot.bin`

4. ATF - UBOOT - KERNEL using `fip` partition. When still booting with `fip` partition and having u-boot installed, change the contents of `/boot/bootcfg/linux` to read `/boot/u-boot.bin` and emtpy  `/boot/bootcfg/initrd`, then run `bpir-writefip`


## R64: Using port 5 of the dsa switch

Note: This does not work when running from emmc and the bootswitch is set to try from sdmmc first, position 1. Only under these two conditions combined, it seems eth1 does not get initialised correctly. The eth1 gmac works fine running from emmc, with sw1 set to 0, try boot from emmc first.

Follow the steps below if you want to use a Router setup and run on emmc with sw1 set to 1. You will then not be using eth1 and port 5 of the dsa switch

Port 5 is available and named aux. Wan and aux port are in a separate vlan. Eth1 is setup as outgoing port instead of wan port.

One would expect the traffic goes a sort of ping pong slow software path: wan --- cpu --- eth0 --- dsa driver --- eth0 --- cpu --- aux --- eth1. But in fact it seems like hardware offloading kicks in and traffic is forwarded in the switch hardware from wan to aux, not taking the slow software path. Exactly what we want: wan --- aux --- eth1. ifstat shows us the traffic is not passing eth0 anymore.
```
ifstat -wi eth0,eth1
```
If you don't like this trick, then chose setup RTnoAUX.


## Setup as Access Point

When using a second or third R64/R3 as Access Point, and connecting router-lan-port to AP-lan-port, do the following:

Choose Setup "AP" in stead of "RT".

The Access Point has network address 192.168.1.33.

For vlan setup the lan ports which connect router and AP as lan-trunk port on both router and AP.

Some DSA drivers have a problem with this setup, but some are recently fixed with a fix wireless roaming fix in the kernel. You will need very recent drivers on all routers/switches and access points on your network


## TODO:

* Implement 802.11k 802.11r 802.11v.
* Guest WIFI


## Features

Command line options:

* -a   : Install necessairy packages.
* -A   : Remove necessairy packages.
* -F   : Format SD card or image, then setup rootfs (adds -r)
* -l   : Add this option to use an image-file instead of an SD card
* -r   : Build RootFS.
* -c   : Execute chroot
* -R   : Delete RootFS.
* -p   : Set boot with FIP partition (default for sdmmc/emmc).
* -P   : Set boot with FAT partition. (default for nand).
* -b   : Create backup of rootfs
* -B   : Restore backup of rootfs
* -x   : Create archive from image-file .xz
* -z   : Create archive from image-file .gz
* none : Enter chroot, same as option `-c`

* Other variables to tweak also at top of build script.


## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)
