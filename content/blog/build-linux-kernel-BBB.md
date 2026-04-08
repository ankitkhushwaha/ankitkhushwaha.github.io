---
date: '2026-04-08T22:31:16+05:30'
draft: true
title: 'Build and Install Linux Kernel For Beaglebone Black'
---

# Overview
The BeagleBone Black (BBB) uses an ARM Cortex-A8 32 bit processor, so the kernel must be cross-compiled on an x86 machine and then deployed to the board.

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

## 4. Copy the Board's config file
On Remote Machine(BBB)
    scp /boot/config-$(uname -r) ankit@10.42.0.17:~/linux/build/.config

## 5. Build the Kernel

    make O=build LOADADDR=0x82000000 -j$(nproc) | tee build.txt

We use `LOADADDR=0x82000000`, the load address expected by U-Boot on the BeagleBone Black, so the kernel boots correctly.


make ARCH=arm CROSS_COMPILE="ccache arm-linux-gnueabihf-" O=build INSTALL_MOD_PATH=/run/media/ankit/rootfs/ -j8 | tee module_install.txt
