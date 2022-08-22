# buildR64arch

Install a minimal Arch-Linux on Banana Pi R64 from scratch.

Downloadable image for quick test located [HERE](https://github.com/ericwoud/buildR64arch/releases/download/v1.0/bpir64-sdmmc.img.xz)

Based on: [buildR64ubuntu](https://github.com/ericwoud/buildR64ubuntu.git)
, [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
and [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)

Now includes a patch so that temperature is regulated at 87 instead of 47 degrees!
Delete the file dtb-patch/dts-cpu-thermal.patch before building, if you do not want to.

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated through the AUR.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

## Getting Started

You need:

  - Banana Pi R64
  - SD card

### Prerequisites

Take a look with the script at the original formatting of the SD card. We use this info to determine it's page/erase size.

Your host's `/etc/resolv.conf` needs to contain a valid DNS nameserver entry, because it is used as base by [`ARCHBOOTSTRAP`](https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh). If you don't use it on your host, then you can temporarily add one, e. g. by:
```
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
```

You need to use the `bash` as shell (e. g. with the `zsh` you will run into trouble).

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
Check your SD card with the following command, write down where the original first partition starts! The script will first show you this info before formatting anything. Set `SD_BLOCK_SIZE_KB` and `SD_ERASE_SIZE_MB` in the script as described there. Don't format a brand new SD card before you find the original erase/block size. It is the best way to determine this.
```
./build.sh -SD
```
Now format your SD card with the same command.

Now build the root filesystem.

```
./build.sh -r
```
Optionally enter chroot environment on the SD card:

```
./build.sh
```

## Deployment

Insert the SD card,, powerup, connect to the R64 wireless, SSID: WIFI24, password: justsomepassword. To start ssh to R64, password admin

```
ssh root@192.168.5.1
```
IPforward is on, the system is setup as router.

After this, you are on your own. It is supposed to be a minimal installation of Arch Linux.


## Build/Install emmc version

When building on R64 (running on sd-card) start/re-enter a screen session with:
```
screen -R
```
Detach from the session if you want, with CTRL-A + D.

Change ATFDEVICE=`sdmmc` in the script to `emmc`. Now format the emmc:
```
./build.sh -SD
```

Make sure your internet connection is working on the R64. Ping 8.8.8.8 should work.

Now build the whole image, same as before.


## Using pre-build images for a quick try-out

On github you will find downloadable images at the release branches.

Write the image file for sd-card to the appropriate device, MAKE SURE YOU HAVE THE CORRECT DEVICE!
```
xz -dcv ~/Downloads/bpir64-sdmmc.img.xz | sudo dd of=/dev/sda
```

## Changing kernel commandline options or devicetree patches

When changing the kernel commandline options in `/boot/bootcfg/cmdline` or changing/adding/removing patches in `/boot/dtb-patch`
you should run the folling command on the bpir64 to write the changees so that they will be activated on the next boot:
```
bpir64-writefip
```

## Using port 5 of the dsa switch

Note: This does not work when running from emmc and the bootswitch is set to try from sdmmc first, position 1. Only onder these two conditions combined, it seems eth1 does not get initialised correctly. The eth1 gmac works fine running from emmc, with sw1 set to 0, try boot from emmc first.

Follow the steps below if you want to use a Router setup and run on emmc with sw1 set to 1. You will then not be using eth1 and port 5 of the dsa switch

Port 5 is available and named aux. Wan and aux port are in a separate vlan. Eth1 is setup as outgoing port instead of wan port.

One would expect the traffic goes a sort of ping pong slow software path: wan --- cpu --- eth0 --- dsa driver --- eth0 --- cpu --- aux --- eth1. But in fact it seems like hardware offloading kicks in and traffic is forwarded in the switch hardware from wan to aux, not taking the slow software path. Exactly what we want: wan --- aux --- eth1. ifstat shows us the traffic is not passing eth0 anymore.
```
ifstat -wi eth0,eth1
```
If you don't like this trick, then:

* Move 'DHCP=yes', under 'Network', from 10-eth1.network to 10-wan.network.
* Remove 'aux' from 10-wan.network file.
* Remove 'Bridge=brlan' from 10-wan.network file.
* Remove whole 'BridgeVLAN' section from 10-wan.network file.
* Remove 10-eth1.network file
* Adjust nftables.conf as described in the file.


## Setup as Access Point

When using a second or third R64ubuntu as Access Point, and connecting router-lan-port to AP-lan-port, do the following:

Change SETUP="RT" to SETUP="AP".

The Access Point has network address 192.168.1.33.

For vlan setup the lan ports which connect router and AP as lan-trunk port on both router and AP.

Some DSA drivers have a problem with this setup, but some are recently fixed with a fix wireless roaming fix in the kernel. You will need very recent drivers on all routers/switches and access points on your network


## TODO:

* Implement 802.11k 802.11r 802.11v.
* Guest WIFI

## Features

Command line options:

* -a   : Install necessairy packages.
* -SD  : Format SD card
* -r   : Build RootFS.
* -R   : Delete RootFS.
* none : Enter chroot

* Other variables to tweak also at top of build script.

## Acknowledgments

* [frank-w's atf](https://github.com/frank-w/BPI-R64-ATF)
* [frank-w's kernel](https://github.com/frank-w/BPI-R2-4.14/tree/5.12-main)
* [mtk-openwrt-atf](https://github.com/mtk-openwrt/arm-trusted-firmware)
* [u-boot](https://github.com/u-boot/u-boot)
* [McDebian](https://github.com/Chadster766/McDebian)
