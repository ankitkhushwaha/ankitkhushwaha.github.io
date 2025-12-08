---
date: '2025-12-01T22:32:00+05:30'
draft: false
title: 'Misc Kernel Driver'
---

# How to Write Your First Linux Kernel Driver Using the Misc Device Framework

## Introduction

 This article explains how to write a simple Linux kernel driver using the misc device framework. The misc framework is a good starting point because it automatically creates the device node when the driver registers, reducing setup complexity. In this example driver, a PID written from user space is stored in the kernel, and reading from the device triggers the driver to look up and display information about the corresponding task.

### What is a Linux Device Driver?

 A device driver is kernel-level code that allows the operating system to interact with hardware or virtual devices. Instead of accessing hardware directly, user-space applications interact with a device file in /dev, and the kernel routes those operations to the driver’s functions.

 Drivers can be:

- Built-in: compiled into the main kernel image, or  
- Loadable modules: compiled separately and inserted/removed at runtime with tools like insmod and rmmod.  
 Using loadable modules makes development and testing much easier because you don’t need to rebuild and reboot the entire kernel for each change.

### Why Use the Misc Device Framework?

 The misc framework provides a lightweight way to create simple character devices without manually managing major numbers, device classes, and udev rules.

 When you register a misc device:
- The kernel assigns a minor number dynamically (MISC_DYNAMIC_MINOR).  
- It automatically creates the corresponding device node under /dev (for example, /dev/task_display).  
-  You only need to define your file_operations and a struct miscdevice.  

 This makes it ideal for:
-  Small utilities  
-  Debug or monitoring interfaces  
-  Experimental or educational drivers  

### The File Operations (open/read/write)

User-space interacts with a character device through standard system calls like open(), read(), and write(). The kernel maps these calls to the driver’s file_operations structure.

For example: 

when any user space process (or thread) opens a device file registered to this
driver, the kernel Virtual Filesystem Switch (VFS) layer will take over. Without going into
deep detail, suffice it to say that the VFS allocates and initializes that process's open
file data structure (struct file) for the device file. 

-  open()  
    Called when a process opens the device file (e.g. open("/dev/task_display", ...)).  
-  read()  
    Transfers data from the kernel to user space. The driver is responsible for copying data into the user buffer and updating the file offset.  
-  write()  
    Receives data from user space, typically via copy_from_user(), and processes or stores it inside the driver.  

 Defining these functions correctly ensures the driver behaves like a regular file from the user’s perspective. The **function signatures** must match the prototypes the kernel expects.

### **Understanding copy_from_user() and copy_to_user()**

When user space interacts with a kernel driver through `read()` or `write()`, the data passed in those system calls cannot be accessed directly inside the kernel due to different address spaces.

Linux provides two helper APIs:
#### **1. copy_from_user()**

Used inside `write()`  
It copies data **from user space → to kernel space**.

```
if (copy_from_user(kbuf, ubuf, count))
	return -EFAULT;
```

You must always validate the size and ensure you don’t read beyond user memory.

#### **2. copy_to_user()**

Used inside `read()`  
It copies data **from kernel space → to user space**.

```
if (copy_to_user(ubuf, kbuf, len))
	return -EFAULT;
```

### Implementing the Minimal Misc Driver

 Our example driver will:

-  Expose a device /dev/task_display.  
-  Accept a PID written from user space via write().  
-  On read(), look up the corresponding task_struct and print task details into the kernel log.  

#### Internal State

 We keep a small per-driver structure to store the device pointer and the PID:

```
#include <linux/device.h>

struct tsk_display
{
 struct device *dev;
 pid_t tsk_pid;
};

static struct tsk_display *tskd;
```

#### open() system-call

```
 int open_tsk_display(struct inode *inode, struct file *filp)
 {
     char *buf = kzalloc(PATH_MAX, GFP_KERNEL);
     if (unlikely(!buf))
         return -ENOMEM;
     pr_info("opening '%s' now; wrt open file: f_flags = 0x%x\n",
             file_path(filp, buf, PATH_MAX), filp->f_flags);
     kfree(buf);
     /* mark this file as non-seekable */
     return nonseekable_open(inode, filp);
 }
```

#### read() system-call

The read() function looks up the task corresponding to the stored PID and prints its information to the kernel log.

##### cat internals
It continously read and write the file with returning the numbers of bytes, it reads and write and returns 0 when EOF reached.
Here we are always returing 0. so `cat command` thinks end-of-file has reached. and read `ubuf` and writes `stdout` only one time.
```
 ssize_t read_tsk_display(struct file *filp, char __user *ubuf,
                          size_t count, loff_t *off)
 {
     void *kbuf = NULL;
     int len, ret = count;
     pid_t tpid_t = tskd->tsk_pid;
     struct pid *pid = NULL;
     struct device *dev = tskd->dev;
     struct task_struct *task = NULL;

	dev_info(dev, "reading tsk info for pid: %d", tpid_t);
	pid = find_get_pid(tpid_t);
	if (!pid)
	{
		 dev_warn(dev, "Invalid pid: %d", tpid_t);
		 goto out_nomem;
	}
	if (pid_has_task(pid, PIDTYPE_PID))
	{
		task = get_pid_task(pid, PIDTYPE_PID);
		if (IS_ERR(task))
		{
			 ret = PTR_ERR(task);
			 goto out_nomem;
		}
	}
    if (*off > 0)
        return 0;

    len = snprintf(kbuf, sizeof(kbuf),
                   "PID: %d\nTGID: %d\nComm: %s\nrecent_used_cpu: %d\non_rq: %d\n",
                   task->pid, task->tgid, task->comm,
                   task->recent_used_cpu, task->on_rq);

    if (copy_to_user(ubuf, kbuf, len))
        return -EFAULT;

    *off += len;
    return len;
 out_nomem:
     return ret;
 }
```

 **Note**:  This is not a proper read() implementation from a userspace point of view, because it doesn’t actually return any data in ubuf. It just logs to dmesg. For a real driver, you’d build a string with the task info and use copy_to_user().

#### write() system-call

 The write() function receives PID input from user space, converts it to an integer, and stores it in tskd->tsk_pid.
```
 ssize_t write_tsk_display(struct file *filp, const char __user *ubuf,
		                           size_t count, loff_t *off)
 {
     int ret = count;
     int tpid = 0;
     void *kbuf = NULL;
     struct device *dev = tskd->dev;

     if (unlikely(count > MAXBYTES))
     {
         dev_warn(dev, "exceeds write bytes limit\n");
         goto out_nomem;
     }
     kbuf = kvmalloc(count, GFP_KERNEL);
     if (unlikely(!kbuf))
         goto out_nomem;

     memset(kbuf, 0, count);
     if (copy_from_user(kbuf, ubuf, count))
     {
         ret = -EFAULT;
         dev_warn(dev, "copy_from_user failed\n");
         goto out_cfu;
     }
     dev_info(dev, "kbuf: %s\n", (char *)kbuf);

     ret = kstrtoint(kbuf, 0, &tpid);
     if (ret)
     {
         dev_warn(dev, "failed to convert kbuf to int");
         goto out_cfu;
     }
     tskd->tsk_pid = tpid;
     dev_info(dev, "pid: %d written to /dev/task_display", tpid);

     ret = count;
 out_cfu:
     kvfree(kbuf);
 out_nomem:
     return ret;
 }
```
  
#### file_operations Structure

The file_operations structure connects the VFS to your driver’s functions:

```
 static const struct file_operations tsk_display_fops = {
     .open  = open_tsk_display,
     .read  = read_tsk_display,
     .write = write_tsk_display,
     .owner = THIS_MODULE;
 };
```

 Whenever user space calls open(), read(), or write() on /dev/task_display, the kernel Virtual Filesystem Switch (VFS) layer will take over and allocates and initializes that process's open file data structure (struct file) for the device file

 **Note**: the function signatures must match the kernel’s expected prototypes for open, read, write, etc.

#### miscdevice Structure

```
 static struct miscdevice tsk_display_dev = {
     .minor = MISC_DYNAMIC_MINOR,
     .name  = "task_display",
     .mode  = 0666,             /*readable and writable*/
     .fops  = &tsk_display_fops,
 };
```
  
-  MISC_DYNAMIC_MINOR → kernel picks a free minor number.  
-  name → used to create /dev/task_display file.  
-  mode → file permissions (here: 0666 -> readable and writable).  

#### Init and Exit Functions

The module’s init function registers the misc device and allocates the driver’s internal structure. The exit function deregisters it.

```
 static int __init task_display_init(void)
 {
     int ret;
     struct device *dev;

     ret = misc_register(&tsk_display_dev);
     if (ret)
     {
         pr_notice("task display device registration failed, aborting\n");
         return ret;
     }

     dev = tsk_display_dev.this_device;
     tskd = devm_kzalloc(dev, sizeof(struct tsk_display), GFP_KERNEL);

     if (unlikely(!tskd))
         return -ENOMEM;

     tskd->dev = dev;

     tskd->tsk_pid = 0;
     pr_info("task display driver registered\n");
     return 0;
 }

 static void __exit task_display_exit(void)
 {
     misc_deregister(&tsk_display_dev);
     pr_info("task display driver deregistered, bye\n");
 }
 

 module_init(task_display_init);
 module_exit(task_display_exit);
```

### Testing the Driver from User Space


```
insmod task_display.ko

ls -l /dev/task_display

echo 1 > /dev/task_display

cat /dev/task_display

dmesg | tail -n 20
```


 You should see log lines showing the PID, TGID, and other task details. That confirms that your write() stored the PID and your read() successfully looked up the task_struct.

#### Summary

 This example demonstrates how to build a small Linux kernel module using the misc device framework. By defining only a few file operations and relying on the kernel to create the device node, the driver stays minimal and easy to understand.

 The driver shows how to:
-  Accept input (a PID) from user space via write().  
-  Use that value inside the kernel to look up a task_struct.  
-  Connect user-space system calls to kernel functions through file_operations and a miscdevice.  
From here, you can extend the example by returning formatted task information to user space with copy_to_user(), adding proper error paths, or exposing more fields from task_struct.