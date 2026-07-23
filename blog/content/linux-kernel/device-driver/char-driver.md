---
title: Char Driver
weight: 1
---

## `dev_t`
32 bit unsigned integer where first 20 used to store minor and rest 12 bit used to store major.

see:
- `include/linux/kdev_t.h`
- `include/linux/types.h`

## Char Devices

> There are 2 ways to create a char device node:
>
> 1. Automatically, via `class_create()` / `device_create()` (udev creates the `/dev` entry).
> 2. Manually, via the `mknod` command.

We'll go through both.

> **Note:** you must populate `struct file_operations` _before_ binding it to `struct cdev` (i.e. before calling `cdev_init()`).
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