---
date: '2025-08-16T14:30:04+05:30'
draft: False
title: 'Install Ubuntu Server on Qemu'
tags: ["qemu", "ubuntu-server", "linux", "linux-kernel"]
---

# Installation of ubuntu server on qemu-x86_64

At First I want to run the custom modules on linux. But this is something that is not good to do on host machine. So i searched a lot of stuff. Tinkering with buildroot, after some days i was able to run the build on qemu. 

But i found out build actually didn’t have my basic tool like `gnu make`. Everytime i try to do something i need to find particular tool on `menuconfig` then make the build again. Learning was so slow.

Then thankfully i found this [article](https://programmador.com/posts/2024/linux-kernel-development-using-qemu/). Which explains to install the arch linux on qemu. I followed it booted the custom kernel in image. But i was not aware of updating the grub config. So i got kernel mismatch issues. I tried to install the arch linux on GNOME Boxes. 

Eventually i decided to leave the arch linux for now -> package dependency in arch breaks easily :).

**Note** : Most of cmds used are well explained in article given above. Check out that too!

## Download the iso file

You can download it from [here](https://ubuntu.com/download/server).

## Create qemu image

```
qemu-img create -f raw <MY_IMAGE> 10G
```

example: `kush.img, myimage.qcow2`

the creates a image file for the qemu.

This cmd create the image file with 10 Gb. You can choose according to your requirement.

Worth mentioning is the alternative qcow2 image format. While slower than a raw formatted image, the qcow2 image size increases during VM usage. You set a limit in gigabytes on the size of the qcow2 image during creation.


## Installting the Distro

```
qemu-system-x86_64 \
    -enable-kvm \
    -cdrom <ubuntu_server_ISO> \
    -boot order=d \
    -drive file=<MY_IMAGE>,format=raw \
    -m 4G
```

Do not give space between `file=<MY_IMAGE>,format=raw`.  Otherwise it will fail.

| **Option**    | **Description**                                                    |
| ------------- | ------------------------------------------------------------------ |
| `-enable-kvm` | Enable hypervisor support using the Linux KVM.                     |
| `-cdrom`      | Points to what image will be inserted into the emulated CD slot.   |
| `-boot`       | Tells QEMU to boot from CD-ROM.                                    |
| `-drive`      | Specifies a drive on the system (e.g., image file and its format). |
| `-m`          | Sets the amount of RAM allocated to the VM (the more, the better). |


After complete installtion it asks for reboot and remove the bootable medium -> you can safely kill the process.

## Running the ubuntu-server

```
qemu-system-x86_64 \
  -enable-kvm \
  -drive file=kush.img,format=raw,if=virtio \
  -m 4G \
  -nic user,hostfwd=tcp::2222-:22 \
  -serial stdio
```


![alt text](/qemu.png)