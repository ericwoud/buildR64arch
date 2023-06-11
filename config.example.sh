#!/bin/bash
#	This file is an example showing how to override configuration values.  Set
#	appropriate values and rename to 'config.sh'
#
#	Any values that are not set here will use default values when build.sh is
#	run.


#	Add a few additional packages to the build.
#NEEDED_PACKAGES="base hostapd openssh wireless-regdb iproute2 nftables f2fs-tools dosfstools"
#NEEDED_PACKAGES+=' '"dtc mkinitcpio patch sudo evtest parted"
NEEDED_PACKAGES+=' '"tcpdump nmap traceroute"

#	Override the timezone
TIMEZONE="America/Los_Angeles"

#	Override the default username and password
USERNAME="brian"
USERPWD="Password123"

#	Override the default root password
ROOTPWD="SuperSecretPassword"
