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

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

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
Set `SD_ERASE_SIZE_MB` in the script if using a cardreader with naming /dev/sdX. Only from a cardreader with naming /dev/mmcblkX
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
./build.sh -lFX
```
Then copy the bpir.img.xz to the SD card /tmp/ folder. It is accessable without root.

Boot the R64/R3 with the SD card with UART connected. When kernel starts keep 'shift E' keys pressed. When finised, you can reboot. 

You can keep 'x' pressed instead if you want to enter a busybox ash.

Note for R3: To run on EMMC, only the switch most near to powerplug (D) should be down, the rest up. Still in development, but should work. Writing at HS200 speed, could be faster.

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
* -b   : Create backup of rootfs
* -B   : Restore backup of rootfs
* -x   : Create archive from image-file
* none : Enter chroot, same as option `-c`

* Other variables to tweak also at top of build script.

## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)
