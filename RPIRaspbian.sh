#!/bin/bash

# 2013-04-20 by Eddy Beaupre, 
#            https://github.com/EddyBeaupre/RPIRaspbian/

#            based on an original script made by Klaus M Pfeiffer, 
#            http://blog.kmp.or.at/ 

# Usage sudo ./RPIRaspbian [/path/to/sd]
#
# With no [/path/to/sd], create an image.
#
# The script will try to figure out if the device is removable will refuse to work if it's not.
# But, it can be wrong and may do nasty things to your system (like wiping out all your disks...)
# Read carefully and be cautious. You are responsible of wathever this script does...
#
# Copyright (c) 2013 Eddy Beaupre. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted provided 
# that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, 
#    this list of conditions and the following disclaimer.
#  
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation 
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
# SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, 
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; 
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
# IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.


# ---------------------
# --- CONFIGURATION ---
# ---------------------

DEB_MIRROR="http://mirrordirector.raspbian.org/raspbian"
DEB_RELEASE="wheezy"

BOOT_SIZE="64"
SWAP_SIZE="384"

DEB_HOSTNAME="RPIDebian"
DEB_PASSWORD="raspberry"

DEB_DEVICE=$1
DEB_ENV="./${DEB_HOSTNAME}"
DEB_ROOTFS="${DEB_ENV}/root"
DEB_BOOTFS="${DEB_ROOTFS}/boot"

DEB_IMAGE=""
DEB_IMAGE_SIZE=1024
DEB_IMAGE_DATE=`date +%Y%m%d`

ETH0_MODE="dhcp"

# If you want a static IP, use the following
#ETH0_MODE="static"
#ETH0_IP="192.168.0.100"
#ETH0_MASK="255.255.255.0"
#ETH0_GW="192.168.0.1"
#ETH0_DNS1="8.8.8.8"
#ETH0_DNS2="8.8.4.4"
#ETH0_DOMAIN="localhost.com"

# ----------------------------
# --- END OF CONFIGURATION ---
# ----------------------------

function testInstall {
  local IN=(`dpkg-query -W -f='${Status} ${Version}\n' $1 2> /dev/null`)
  if [ "${IN[0]}" != "install" ]; then
    echo "          $1 not found, installing..."
    apt-get -y install $1
  fi
}

function partSync {
  sync
  partprobe
}

function showState {
  echo "--- $1"
}

promptyn () {
  while true; do
    read -p "$1 " yn
    case $yn in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer yes or no.";;
    esac
  done
}

echo "
RPIRaspbian by Eddy Beaupre.
----------------------------
"

if [ $EUID -ne 0 ]; then
  showState "this tool must be run as root"
  exit 1
fi

if ! [ -b ${DEB_DEVICE} ]; then
  showState "${DEB_DEVICE} is not a block DEB_DEVICE"
  exit 1
fi

if [ "${DEB_DEVICE}" != "" ]; then
  bDEB_DEVICE=`basename ${DEB_DEVICE}`
  if [ `cat /sys/block/${bDEB_DEVICE}/removable` != "1" ]; then
    showState "${DEB_DEVICE} is not a removable DEB_DEVICE"
    exit 1
  fi
fi
  
echo "
Configuration :
                     Hostname : ${DEB_HOSTNAME}
                Root Password : ${DEB_PASSWORD}
                      Release : ${DEB_RELEASE}
                       Source : ${DEB_MIRROR}
                      
          Boot partition size : ${BOOT_SIZE}MB
               Swap file size : ${SWAP_SIZE}MB"

if [ "${ETH0_MODE}" = "dhcp" ]; then
  echo "
                   IP Address : Assigned by DHCP"
else
  echo "
                   IP Address : ${ETH0_IP}
                  Subnet Mask : ${ETH0_MASK}
              Default Gateway : ${ETH0_GW}
                          DNS : ${ETH0_DNS1} ${ETH0_DNS2}
                Search Domain : ${ETH0_DOMAIN}"
fi

if [ "${DEB_DEVICE}" == "" ]; then
  echo "
                   Image file : ${DEB_HOSTNAME}_${DEB_RELEASE}_${DEB_IMAGE_DATE}.img (${DEB_IMAGE_SIZE}MB)
  "
else
  echo "
     Content of target DEB_DEVICE : "
  fdisk -l ${DEB_DEVICE}
  echo ""
fi

promptyn "Shall we proceed?"
if [ $? -ne 0 ]; then
  echo "Aborting..."
  exit 1
fi

showState "Setting up build environment"

for i in binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools; do testInstall $i; done

if [ "${deb_local_mirror}" == "" ]; then
  deb_local_mirror=${DEB_MIRROR}  
fi

if [ "${DEB_DEVICE}" == "" ]; then
  showState "No block DEB_DEVICE given, creating an DEB_IMAGE of ${DEB_IMAGE_SIZE}mb"
  mkdir -p ${DEB_ENV}
  DEB_IMAGE="${DEB_HOSTNAME}_${DEB_RELEASE}_${DEB_IMAGE_DATE}.img"
  dd if=/dev/zero of=${DEB_IMAGE} bs=1MB count=${DEB_IMAGE_SIZE} 
  DEB_DEVICE=`losetup -f --show ${DEB_IMAGE}` 
  showState "Image ${DEB_IMAGE} created and mounted as ${DEB_DEVICE}"
else
  showState "Erasing ${DEB_DEVICE}"
  dd if=/dev/zero of=${DEB_DEVICE} bs=512 count=1 
fi

partSync

showState "Creating partitions on ${DEB_DEVICE}"
fdisk ${DEB_DEVICE} << EOF 
n
p
1

+${BOOT_SIZE}M
t
c
n
p
2


w
EOF

partSync

if [ "${DEB_IMAGE}" != "" ]; then
  losetup -d ${DEB_DEVICE}
  DEB_DEVICE=`kpartx -va ${DEB_IMAGE} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
  DEB_DEVICE="/dev/mapper/${DEB_DEVICE}"
  bootp=${DEB_DEVICE}p1
  rootp=${DEB_DEVICE}p2
else
  if ! [ -b ${DEB_DEVICE}1 ]; then
    bootp=${DEB_DEVICE}p1
    rootp=${DEB_DEVICE}p2
    if ! [ -b ${bootp} ]; then
      showState "Something went wrong, can't find bootpartition neither as ${DEB_DEVICE}1 nor as ${DEB_DEVICE}p1, exiting."
      exit 1
    fi
  else
    bootp=${DEB_DEVICE}1
    rootp=${DEB_DEVICE}2
  fi  
fi

showState "Creating fat filesystem on ${bootp}"
mkfs.vfat ${bootp} 

showState "Creating ext4 filesystem on ${rootp}"
mkfs.ext4 ${rootp} 

sync

showState "Mounting ${rootp} in ${DEB_ROOTFS}"
mkdir -p ${DEB_ROOTFS}
mount ${rootp} ${DEB_ROOTFS}

showState "Installing debian ${DEB_RELEASE} in ${DEB_ROOTFS} from ${deb_local_mirror}"
debootstrap --foreign --arch armhf ${DEB_RELEASE} ${DEB_ROOTFS} ${deb_local_mirror}
cp /usr/bin/qemu-arm-static ${DEB_ROOTFS}/usr/bin/
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} /debootstrap/debootstrap --second-stage
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} dpkg --configure -a

showState "Mounting ${bootp} in ${DEB_BOOTFS}"
mount ${bootp} ${DEB_BOOTFS}

showState "Configuring sources.list"
cat > ${DEB_ROOTFS}/etc/apt/sources.list <<EOF
deb ${deb_local_mirror} $DEB_RELEASE main contrib non-free rpi
deb-src ${deb_local_mirror} ${DEB_RELEASE} main contrib non-free rpi
EOF

showState "Setting up cmdline.txt"
cat > ${DEB_ROOTFS}/boot/cmdline.txt <<EOF
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 elevator=deadline rootwait
EOF

showState "Setting up config.txt"
cat > ${DEB_ROOTFS}/boot/config.txt <<EOF
# uncomment if you get no picture on HDMI for a default "safe" mode
#hdmi_safe=1

# uncomment this if your display has a black border of unused pixels visible
# and your display can output without overscan
#disable_overscan=1

# uncomment the following to adjust overscan. Use positive numbers if console
# goes off screen, and negative if there is too much border
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# uncomment to force a console size. By default it will be display's size minus
# overscan.
#framebuffer_width=1280
#framebuffer_height=720

# uncomment if hdmi display is not detected and composite is being output
#hdmi_force_hotplug=1

# uncomment to force a specific HDMI mode (this will force VGA)
#hdmi_group=1
#hdmi_mode=1

# uncomment to force a HDMI mode rather than DVI. This can make audio work in
# DMT (computer monitor) modes
#hdmi_drive=2

# uncomment to increase signal to HDMI, if you have interference, blanking, or
# no display
#config_hdmi_boost=4

# uncomment for composite PAL
#sdtv_mode=2

#uncomment to overclock the arm. 700 MHz is the default.
#arm_freq=800

# for more options see http://elinux.org/RPi_config.txt
EOF

showState "Setting up fstab"
cat > ${DEB_ROOTFS}/etc/fstab <<EOF
#<file system>	<mount point>	<type>	<options>	<dump>	<pass>
proc		/proc		proc	defaults	0	0
/dev/mmcblk0p1	/boot		vfat	defaults	0	0
EOF

showState "Setting up hostname"
cat > ${DEB_ROOTFS}/etc/hostname <<EOF
${DEB_HOSTNAME}
EOF

showState "Setting up eth0"

cat > ${DEB_ROOTFS}/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet ${ETH0_MODE}
EOF

if [ "${ETH0_MODE}" != "dhcp" ]; then
cat >> ${DEB_ROOTFS}/etc/network/interfaces <<END
  address ${ETH0_IP}
  netmask ${ETH0_MASK}
  gateway ${ETH0_GW}
END
cat > ${DEB_ROOTFS}/etc/resolv.conf <<END
search ${ETH0_DOMAIN}
nameserver ${ETH0_DNS1}
nameserver ${ETH0_DNS2}
END
fi

showState "Setting up modules"
cat >> ${DEB_ROOTFS}/etc/modules <<EOF
vchiq
snd_bcm2835
EOF

showState "Configuring dphys-swapfile for a ${SWAP_SIZE}mb swapfile"
cat > ${DEB_ROOTFS}/etc/dphys-swapfile <<EOF
CONF_SWAPSIZE=${SWAP_SIZE}
EOF

showState "Installing extra packages"

# Avoid starting up services after they are installed.
cat > ${DEB_ROOTFS}/usr/sbin/policy-rc.d <<EOF
#!/bin/sh
exit 101
EOF

chmod +x ${DEB_ROOTFS}/usr/sbin/policy-rc.d

LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} apt-get update
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} apt-get upgrade 
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} apt-get -y install git-core binutils ca-certificates nvi locales ntp ssh ssh-client console-common whiptail parted lua5.1 triggerhappy

# If we don't delete this, services will never start...
rm -f ${DEB_ROOTFS}/usr/sbin/policy-rc.d

showState "Installing raspi-config"
wget https://raw.github.com/asb/raspi-config/master/raspi-config -O ${DEB_ROOTFS}/usr/bin/raspi-config 
chmod +x ${DEB_ROOTFS}/usr/bin/raspi-config

showState "Installing Kernel"
wget http://goo.gl/1BOfJ -O ${DEB_ROOTFS}/usr/bin/rpi-update
chmod +x ${DEB_ROOTFS}/usr/bin/rpi-update
mkdir -p ${DEB_ROOTFS}/lib/modules
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} rpi-update

showState "Configuring locales and timezone"
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} dpkg-reconfigure locales tzdata

showState "Setting up root password for ${DEB_HOSTNAME}"
LC_ALL=C LANGUAGE=C LANG=C chroot ${DEB_ROOTFS} echo "root:${DEB_PASSWORD}" | chpasswd

showState "Cleaning up"
LANG=C chroot ${DEB_ROOTFS} aptitude update
LANG=C chroot ${DEB_ROOTFS} aptitude clean
LANG=C chroot ${DEB_ROOTFS} apt-get clean
rm -rf ${DEB_ROOTFS}/root/.rpi-firmware
rm -rf ${DEB_ROOTFS}/lib/*.bak
rm -rf ${DEB_ROOTFS}/boot.bak
rm ${DEB_ROOTFS}/usr/bin/qemu-arm-static

showState "Unmounting ${bootp}"
umount ${bootp}
showState "Unmounting ${rootp}"
umount ${rootp}

if [ "${DEB_IMAGE}" != "" ]; then
  kpartx -d ${DEB_IMAGE} 
  showState "Created DEB_IMAGE ${DEB_IMAGE}"
else
  showState "${DEB_HOSTNAME} installed into ${DEB_DEVICE}"
fi

if [ -d "${DEB_ENV}" ]; then
  rm -rf ${DEB_ENV}
fi

showState "done."
