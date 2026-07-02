---
date: "2026-06-11T17:26:20+05:30"
draft: false
title: 'Linux Device Driver Hacks'
tags:
  - Char-Device
  - Cdev
  - Module-Parameters
  - Kernel-Api
categories:
  - Linux Kernel
---

> This blog will contain the code snippets that are needed to implement particular feature in kernel.
> I'll mainly focus on code snippet rather than the explanation. 
> Again! this blog may not be fully correct. You're expected to "check the facts/code" before applying.
> Please correct me, if i'm wrong. I'll be more happy to accept the changes.

## Macros

### `container_of()`

#### Accessing a custom struct from `struct inode` via `struct cdev`

`container_of()` lets you walk backward from an embedded member (here, `struct cdev`) to the containing struct. This is how a driver recovers its private device context inside `file_operations` callbacks.

```c
#include <linux/kernel.h>   /* container_of() */
#include <linux/fs.h>       /* struct inode, struct file */
#include <linux/cdev.h>     /* struct cdev */

struct scull_dev {
	/* ... */
	struct cdev cdev;
};

int scull_open(struct inode *inode, struct file *filp)
{
	struct scull_dev *dev;

	dev = container_of(inode->i_cdev, struct scull_dev, cdev);
	filp->private_data = dev;

	/* ... */
}

ssize_t scull_read(struct file *filp, char __user *buff, size_t count,
		    loff_t *f_pos)
{
	struct scull_dev *dev = filp->private_data;

	/* ... */
}
```

> Pattern: stash the recovered pointer in `filp->private_data` on `open()` so every later callback (`read`, `write`, `ioctl`, `release`, ...) can grab it back in one line.

### `pr_fmt()`

#### Prefixing the `pr_*()` calls

`pr_fmt()` is a macro that rewrites the format string of every `pr_*()` call (`pr_info`, `pr_warn`, `pr_err`, ...) in the file. It has to be defined **before** any header that pulls in `<linux/printk.h>`, so it always sits at the very top, above your includes.

```c
#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/kernel.h>
#include <linux/module.h>

static int func(void)
{
	pr_warn("hello-world\n");
	return -1;
}
```
`pr_fmt()` line auto-adjusts to whichever function it's expanded in.

Expands to roughly:

```c
printk(KERN_WARNING "hello-world\n");
```

Without `pr_fmt()`, every `pr_*()` line falls back to the default `"%s"`, no module or function context, so you're stuck grepping `dmesg` blind. With it, every log line self-identifies:

```
[   12.482103] module_name:func: hello-world
```
> Default fallback is `#define pr_fmt(fmt) fmt`, just the format string, untouched, if you never define your own.
> and only affects the `pr_*()` family, not raw `printk(KERN_WARNING ...)` calls.

---

## Kernel Module

### Module Parameters

```c
#include <linux/module.h>
#include <linux/moduleparam.h>  /* not strictly needed, linux/module.h already pulls it in */
#include <linux/kernel.h>

module_param(name, type, perm);
MODULE_PARM_DESC(myarr, "this is my array of int");
```

Pass the value at load time:

```bash
insmod module.ko param=value
```

---

## Kbuild Makefile

> These aren't plain GNU Make, Kbuild (the kernel's build system) reads them with special meaning when you run `make -C /lib/modules/$(uname -r)/build M=$(pwd) modules`.

```makefile
CFLAGS_main.o := -DDEBUG

ccflags-y := -std=gnu99 -DENABLE_DEBUG

proc_fs_basic-objs := main.o

obj-m := proc_fs_basic.o
```

- **`CFLAGS_main.o`** - per-object compiler flags. Only `main.o` gets `-DDEBUG`; if you had `main.o` and `helper.o`, only the first sees the macro. Useful for debug-gating one file without recompiling the whole module noisily.

- **`ccflags-y`** - flags applied to *every* `.o` in this Makefile (the module-wide equivalent of `CFLAGS`). Here it forces `gnu99` and defines `ENABLE_DEBUG` globally.

- **`proc_fs_basic-objs`** - when a module is built from more than one source file, this lists what gets linked into the final `.ko`. Pattern is `<module_name>-objs := a.o b.o c.o` (Kbuild also accepts `-y` instead of `-objs` in newer trees).

- **`obj-m`** - the actual build trigger. `obj-m` = build as a loadable module → `proc_fs_basic.ko`. Swap it for `obj-y` and it'd get compiled directly into the kernel image instead.

> Order of resolution: `obj-m` → Kbuild sees `proc_fs_basic.o` is wanted → checks for `proc_fs_basic-objs` → pulls in `main.o` → applies `CFLAGS_main.o` + `ccflags-y` while compiling it.

---

## Char Devices

> There are 2 ways to create a char device node:
> 1. Automatically, via `class_create()` / `device_create()` (udev creates the `/dev` entry).
> 2. Manually, via the `mknod` command.

We'll go through both.

> **Note:** you must populate `struct file_operations` *before* binding it to `struct cdev` (i.e. before calling `cdev_init()`).
> See [example](https://github.com/niekiran/linux-device-driver-1/blob/54e818e345cc507730fe02008749f89eda262121/custom_drivers/002pseudo_char_driver/pcd.c#L146)

### Method 1 - `class_create()` / `device_create()` (udev)

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/err.h>      /* IS_ERR(), PTR_ERR() */

static dev_t device_number;
struct cdev pcd_cdev;
struct class *class_pcd;
struct device *device_pcd;

struct file_operations pcd_fops;

/* Init function */
static int __init func_init(void)
{
	int ret;

	/* 1. Dynamically allocate a device number */
	ret = alloc_chrdev_region(&device_number, 0, 1, "pcd_devices");
	if (ret < 0) {
		pr_err("Alloc chrdev failed\n");
		goto out;
	}

	pr_info("Device number <major>:<minor> = %d:%d\n",
		 MAJOR(device_number), MINOR(device_number));

	/* 2. Initialize the cdev structure with fops */
	cdev_init(&pcd_cdev, &pcd_fops);
	pcd_cdev.owner = THIS_MODULE;

	/* 3. Register the device (cdev structure) with the VFS */
	ret = cdev_add(&pcd_cdev, device_number, 1);
	if (ret < 0) {
		pr_err("Cdev add failed\n");
		goto unreg_chrdev;
	}

	/* 4. Create a device class under /sys/class/ */
	class_pcd = class_create(THIS_MODULE, "pcd_class");
	if (IS_ERR(class_pcd)) {
		pr_err("Class creation failed\n");
		ret = PTR_ERR(class_pcd);
		goto cdev_del;
	}

	/* 5. Populate sysfs with device information -> triggers udev to create /dev/pcd */
	device_pcd = device_create(class_pcd, NULL, device_number, NULL, "pcd");
	if (IS_ERR(device_pcd)) {
		pr_err("Device create failed\n");
		ret = PTR_ERR(device_pcd);
		goto class_del;
	}

	pr_info("Module init was successful\n");
	return 0;

class_del:
	class_destroy(class_pcd);
cdev_del:
	cdev_del(&pcd_cdev);
unreg_chrdev:
	unregister_chrdev_region(device_number, 1);
out:
	pr_info("Module insertion failed\n");
	return ret;
}

/* Cleanup function */
static void __exit func_cleanup(void)
{
	device_destroy(class_pcd, device_number);
	class_destroy(class_pcd);
	cdev_del(&pcd_cdev);
	unregister_chrdev_region(device_number, 1);
	pr_info("module unloaded\n");
}
```

### Method 2 - Manual node creation via `mknod`

No use of `class_create()` / `device_create()` here, the driver only reserves the major/minor and registers the `cdev`. You create the `/dev` entry yourself afterward, using the major/minor printed in `dmesg`.

```c
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/fs.h>
#include <linux/cdev.h>

static dev_t device_number;
struct cdev pcd_cdev;

struct file_operations pcd_fops;

/* Init function */
static int __init func_init(void)
{
	int ret;

	/* 1. Dynamically allocate a device number */
	ret = alloc_chrdev_region(&device_number, 0, 1, "pcd_devices");
	if (ret < 0) {
		pr_err("Alloc chrdev failed\n");
		goto out;
	}

	pr_info("Device number <major>:<minor> = %d:%d\n",
		 MAJOR(device_number), MINOR(device_number));

	/* 2. Initialize the cdev structure with fops */
	cdev_init(&pcd_cdev, &pcd_fops);
	pcd_cdev.owner = THIS_MODULE;

	/* 3. Register the device (cdev structure) with the VFS */
	ret = cdev_add(&pcd_cdev, device_number, 1);
	if (ret < 0) {
		pr_err("Cdev add failed\n");
		goto unreg_chrdev;
	}

	pr_info("Module init was successful\n");
	return 0;

unreg_chrdev:
	unregister_chrdev_region(device_number, 1);
out:
	pr_info("Module insertion failed\n");
	return ret;
}

/* Cleanup function */
static void __exit func_cleanup(void)
{
	cdev_del(&pcd_cdev);
	unregister_chrdev_region(device_number, 1);
	pr_info("module unloaded\n");
}
```

```bash
# Load the module, then check the major number it was assigned
insmod pcd.ko
cat /proc/devices | grep pcd_devices
dmesg | tail   # also prints <major>:<minor> from pr_info above

# Manually create the device node (replace <major>/<minor> with the printed values)
sudo mknod /dev/pcd c <major> <minor>
sudo chmod 666 /dev/pcd      # optional: open up permissions for testing

# Clean up
sudo rm /dev/pcd
rmmod pcd
```

> See: [embetronicx - Device File Creation for Character Drivers](https://embetronicx.com/tutorials/linux/device-drivers/device-file-creation-for-character-drivers/)

**Trade-off:** `mknod` is quick for bring-up/testing but the node doesn't survive a reboot and isn't reproducible across machines (major number can shift). `class_create()`/`device_create()` lets udev manage the node automatically and is what real drivers use.

## C Tricks

### The Structural Wrapper: `do { ... } while (0)`

Standard macro design pattern. Forces the macro to behave like a single C statement, so it can't break syntax when used inside an `if/else` without braces.

```c
#define LOG_DEBUG(msg) do { \
    printk(KERN_DEBUG msg); \
    debug_count++; \
} while (0)

if (tmp)
    LOG_DEBUG("checking condition\n");
else
    do_something();
```

> Two statements is where this trick stops being a nice-to-have and becomes necessary. Without the wrapper:
> ```c
> #define LOG_DEBUG(msg) printk(KERN_DEBUG msg); debug_count++;
> ```
> expands the `if` branch into two separate statements, only the first one belongs to the `if`, the second runs unconditionally regardless of `tmp`. Wrap braces `{ }` around it instead and you hit the classic dangling-`;` problem: the trailing `;` after the macro call becomes an empty statement, and the `else` ends up with no matching `if`.

The `do { } while (0)` fixes both: it groups any number of statements into one block, and swallows the semicolon you put after the macro call. `while (0)` never loops, so the compiler optimizes it away, zero runtime cost.


### Error Handling

Standard kernel pattern for unwinding partial allocations when a loop fails mid-way.

```c
int ret;
int i;

for (i = 0; i < count; i++)
{
    arr1[i] = kmalloc(size1, GFP_KERNEL);
    if (!arr1[i]) {
        ret = -ENOMEM;
        goto err;
    }
    arr2[i] = kmalloc(size2, GFP_KERNEL);
    if (!arr2[i]) {
		/* error handling in mid-way loop */
        kfree(arr1[i]);
        arr1[i] = NULL;
        ret = -ENOMEM;
        goto err;
    }
}

	return 0;

err:
	while (--i >= 0)
	{
		kfree(arr2[i]);
		kfree(arr1[i]);
	}
	return ret;
```
