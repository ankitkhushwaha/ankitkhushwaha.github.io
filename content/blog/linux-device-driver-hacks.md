---
date: "2026-06-11T17:26:20+05:30"
draft: false
title: 'Linux Device Driver Hacks'
tags: 
categories:
---

> This blog will contain the code snippets that are needed to implement particular feature in kernel.
> I'll mainly focus on code snippet rather than the explanation. 
> Again! this blog may not be fully correct. You're expected to "check the facts/code" before applying.
> Please correct me, if i'm wrong. I'll be more happy to accept the changes.
> This Blog is not beginner friendly.

## Kernel MODULE MACRO

### Handling module parameters
```c
#include <linux/moduleparam.h>  // No need to include this. 'linux/module.h' included it.

module_param(name, type, perm);
MODULE_PARM_DESC(myarr,"this is my array of int");
```

```
inmod module.ko param=value
```
---

## Char Device

> There are 2 way to create char device.
> Creating the device node through 'kernel module' or using `mknod`

We will go through both way.

> Note: you have to populate the `strcut file_operations` before binding it `struct cdev`.
> See [example](https://github.com/niekiran/linux-device-driver-1/blob/54e818e345cc507730fe02008749f89eda262121/custom_drivers/002pseudo_char_driver/pcd.c#L146)

### Kernel Module

> **TODO**: Add header files. 
```c

static dev_t device_number;
struct cdev pcd_cdev;
struct class *class_pcd;
struct device *device_pcd;

struct file_operations pcd_fops;

/* Init function */
static int __init func_init(void)
{
	int ret;

	/*1. Dynamically allocate a device number */
	ret = alloc_chrdev_region(&device_number,0,1,"pcd_devices");
	if(ret < 0){
		pr_err("Alloc chrdev failed\n");
		goto out;
	}

	pr_info("Device number <major>:<minor> = %d:%d\n",MAJOR(device_number),MINOR(device_number));

	cdev_init(&pcd_cdev,&pcd_fops);
	pcd_cdev.owner = THIS_MODULE;

	/* 3. Register a device (cdev structure) with VFS */
	ret = cdev_add(&pcd_cdev,device_number,1);
	if(ret < 0){
		pr_err("Cdev add failed\n");
		goto unreg_chrdev;
	}
	/*4. create device class under /sys/class/ */
	class_pcd = class_create(THIS_MODULE,"pcd_class");
	if(IS_ERR(class_pcd)){
		pr_err("Class creation failed\n");
		ret = PTR_ERR(class_pcd);
		goto cdev_del;
	}

	/*5.  populate the sysfs with device information */
	device_pcd = device_create(class_pcd,NULL,device_number,NULL,"pcd");
	if(IS_ERR(device_pcd)){
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
	unregister_chrdev_region(device_number,1);
out:
	pr_info("Module insertion failed\n");
	return ret;
}

/* Cleanup function */
static void __exit func_cleanup(void)
{
	device_destroy(class_pcd,device_number);
	class_destroy(class_pcd);
	cdev_del(&pcd_cdev);
	unregister_chrdev_region(device_number,1);
	pr_info("module unloaded\n");
}
```

### Using `MKNOD`

> See [example]().
> **TODO**: Add header files. 

```c
```


```bash
```