---
date: '2026-04-08T22:31:16+05:30'
draft: false
title: 'Build and Install Linux Kernel For Beaglebone Black'
---

# Overview
The BeagleBone Black (BBB) uses an ARM Cortex-A8 32 bit processor, so the kernel must be cross-compiled on an x86 machine and then deployed to the board. This blog will assume that you already have a os[debian/ubuntu] installed on your sd card.  

We’ll:
- set up toolchain
- fetch kernel source
- configure for BBB
- build kernel + modules
- deploy to SD card / board

## 1. Prerequisites

Make sure you have:

- Ubuntu (or any Linux host)
- Cross compiler for ARM (arm)

Install required tools:

    sudo apt update
    sudo apt install gcc-arm-linux-gnueabihf build-essential bc bison flex libssl-dev u-boot-tools

## 2. Get Linux Kernel Source

You can use mainline or TI’s kernel. For stability on BBB, We will use `beagleboard/linux` Kernel, since it already includes the board-specific patches and fixes.

    git clone https://github.com/beagleboard/linux.git
    cd linux
    mkdir build

Checkout a stable branch:

    git checkout 6.6.20-ti-arm64-r3

Note: Choose the kernel repository based on your board’s processor architecture. Since the BeagleBone Black uses a 32-bit ARM processor, we’ll use the corresponding ARM (armhf) kernel.

## 3. Set Cross Compilation Environment

    export ARCH=arm
    export CROSS_COMPILE=arm-linux-gnueabihf-

## 4. Configure the default Board's config file
    make bb.org_defconfig

Optional: Customize configuration:
    make menuconfig

## 5. Build the Kernel

    make O=build LOADADDR=0x82000000 -j$(nproc) | tee build.txt

We use `LOADADDR=0x82000000`, the load address expected by U-Boot on the BeagleBone Black, so the kernel boots correctly.

This will Build the zImage, modules, and device tree blobs:

## 6. Connect the sd card with host machine.

check whether it mounted or not.

    lsblk
        sda           8:0    1  29.7G  0 disk 
        ├─sda1        8:1    1    36M  0 part /run/media/ankit/BOOT
        ├─sda2        8:2    1   512M  0 part 
        └─sda3        8:3    1  29.2G  0 part 

In our case sda3 has rootfs partition, mount it.

    sudo mkdir -p /mnt/rootfs
    sudo mount /dev/sda3 /mnt/rootfs

## 7. Install Modules

    make O=build INSTALL_MOD_PATH=/mnt/rootfs/ -j$(nproc)

    ➜ $ ls /mnt/rootfs/lib/modules/6.6.6
            build                      modules.dep          modules.weakdep
            config                     modules.dep.bin      source
            kernel                     modules.devname      symvers.xz
            modules.alias              modules.drm          System.map
            modules.alias.bin          modules.modesetting  systemtap
            modules.block              modules.networking   updates
            modules.builtin            modules.order        vdso
            modules.builtin.alias.bin  modules.softdep      vmlinuz
            modules.builtin.bin        modules.symbols      weak-updates
            modules.builtin.modinfo    modules.symbols.bin

Note: build is symlink that points to build directory of kernel source. copy that build/ dir inside it. If you want to compile module on BBB itself or maybe keep this as backup.

    cd /mnt/rootfs/lib/modules/6.6.6
    rm build    # dont add the /, it can delete the files in build/ dir.
    mkdir -p build
    sudo cp -r linux-src/build .  

## 8. Copy the zImage and dtb blob files

### Get the Kernel release Version

    # make O=build/ kernelrelease
        make[1]: Entering directory '~/linux-src/build'
        6.6.20
        make[1]: Leaving directory '~/linux-src/build'

Use this kernel Build verison while copying the zImage file.

### Copy the zImage file

    cd linux-src/build/arch/arm/boot/
    sudo cp zImage /mnt/rootfs/boot/vmlinuz-6.6.20

### Copy the dts file

    sudo mkdir -p /mnt/rootfs/boot/dtbs/6.6.20/
    
    cd linux-src/build/arch/arm/boot/dts/ti/omap/
    sudo cp * /mnt/rootfs/boot/dtbs/6.6.20/

## 9. Build the Initramfs File

Boot the BBB

### Install dracut
    sudo apt install dracut
    sudo dracut -v -f --kver 6.6.20 /boot/initrd.img-6.6.20

this cmd will build Initramfs inside /boot.

## 10. Update /boot/uEnv.txt file

    diff --git a/uEnv.txt b/uEnv.txt
    index b79d3c4..b88f904 100644
    --- a/uEnv.txt
    +++ b/uEnv.txt
    @@ -1,6 +1,6 @@
    #Docs: http://elinux.org/Beagleboard:U-boot_partitioning_layout_2.0
    
    -uname_r=6.19.11-bone14
    +uname_r=6.6.20
    #uuid=
    #dtb=

## 11. Reboot the BBB

    $ sudo reboot
        
    $ uname -r
        6.6.20

    $ echo Voilà
        Voilà
