---
date: "2026-06-11T17:26:20+05:30"
draft: false
title: "Linux Device Driver Hacks"
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

### Stringification in the Kernel

`include/linux/stringify.h` defines:

```c
#define __stringify_1(x...)    #x
#define __stringify(x...)      __stringify_1(x)
```

Both use `#` to turn an argument into a string literal. They differ only when the argument is a macro.

`#` stringifies tokens *before* expanding any macros in them. So `__stringify_1(x)` gives you the literal text you passed, macro name included, unexpanded.

`__stringify(x)` adds one layer of indirection. Since `x` isn't touched directly by `#` inside `__stringify`, the preprocessor expands `x` first when it's passed down to `__stringify_1`, which then stringifies the *expanded* result.

Example:

```c
#define KVERSION 6

pr_info("%s\n", __stringify_1(KVERSION));
// "KVERSION"

pr_info("%s\n", __stringify(KVERSION));
// "6"

char *hello = "world";

pr_info("%s\n", __stringify_1(hello));
// "hello"

pr_info("%s\n", __stringify(hello));
// "hello"

```

For a non-macro token: a variable name, a plain string, there's nothing to expand, so both macros produce the same output. 

> **Note**: The indirection only work when the argument is a `#define`.

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

- **`ccflags-y`** - flags applied to _every_ `.o` in this Makefile (the module-wide equivalent of `CFLAGS`). Here it forces `gnu99` and defines `ENABLE_DEBUG` globally.

- **`proc_fs_basic-objs`** - when a module is built from more than one source file, this lists what gets linked into the final `.ko`. Pattern is `<module_name>-objs := a.o b.o c.o` (Kbuild also accepts `-y` instead of `-objs` in newer trees).

- **`obj-m`** - the actual build trigger. `obj-m` = build as a loadable module → `proc_fs_basic.ko`. Swap it for `obj-y` and it'd get compiled directly into the kernel image instead.

> Order of resolution: `obj-m` → Kbuild sees `proc_fs_basic.o` is wanted → checks for `proc_fs_basic-objs` → pulls in `main.o` → applies `CFLAGS_main.o` + `ccflags-y` while compiling it.

---

## Error Handling with Pointers in the Kernel

Many kernel functions return either a valid pointer on success or an encoded error code on failure. this lets a single return value carry both success and failure info, keeping the function signature clean.

In `include/linux/err.h`:

```c
#define MAX_ERRNO   4095
```

This is the largest error number the kernel uses. No kernel pointer will ever legitimately point into the very top of the address space,
that range is reserved to encode error codes instead, Because kernel reserves a small range of addresses at the very top of the virtual address space and these addresses are invalid as actual memory locations.

```c
#define IS_ERR_VALUE(x) \
    unlikely((unsigned long)(void *)(x) >= (unsigned long)-MAX_ERRNO)
```

Cast to `unsigned long`, a small negative error code like `-22` (`-EINVAL`) becomes a huge number close to `ULONG_MAX`. So checking `x >= -MAX_ERRNO` really give "is this value one of the last 4095 possible addresses?"  if yes, it's not a real pointer, it's an error.

**The three macros**

| Macro | What it does | Returns |
|---|---|---|
| `ERR_PTR(err)` | Encodes a negative error code as a pointer | `(void *)err` |
| `IS_ERR(ptr)` | Checks if a pointer is actually an encoded error | `true`/`false` |
| `PTR_ERR(ptr)` | Decodes the error number back to the pointer | `long` (the error code) |

**Typical usage**

```c
struct foo *p = some_kernel_function();

if (IS_ERR(p))
    return PTR_ERR(p);   // propagate the error code

// otherwise p is safe to use
```

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

## VFS

### Proc Interface

`/proc` is the classic way a driver hands kernel-side information to userspace without going through a real block device. There are three ways to implement the read side of a proc entry, depends on whether you're exposing a single fixed value or walking a list.

> Keep a note that this method is **depreciated** for device driver.

#### 1. Raw `file_operations` - the old way

This is the original method: you wire up `.read`, `.write`, `.open`, `.llseek`, and `.release` yourself, exactly like a normal character device.

```c
static struct proc_ops proc_ops = {
	.proc_open    = proc_open,
	.proc_read    = proc_read,
	.proc_write   = proc_write,
	.proc_lseek   = proc_lseek,
	.proc_release = proc_release,
};
```

Random access via `llseek` is supported, but this approach is also likely to more error-prone, which is why raw `file_operations` is rarely used for `/proc` today.

> In older tutorial: this struct used to be `struct file_operations`, the same one character devices use. Since Linux 5.6, `/proc` entries register against a dedicated `struct proc_ops` instead smaller surface, and it no longer inherits fields (like `mmap`-related security checks) that don't apply to proc files.

Function trace for this method:

```
Start (open) -> llseek -> read -> llseek -> read -> llseek -> read -> End (close)
```

#### 2. Using `seq_file` + `single_open`

A method to handle this by simply connecting the sequence file ( seq_file ) interface to file_operations and using `single_open()` which does not use seq_operations.

> [full example](https://github.com/ankitkhushwaha/Linux-Device-Driver/blob/master/eg_04_proc_fs_basic/v7.1.0/main.c)

```c
#include <linux/proc_fs.h>
#include <linux/seq_file.h>

static struct proc_ops proc_ops = {
	.proc_open = proc_open,
	.proc_read = seq_read,
	.proc_lseek = seq_lseek,
	.proc_release = proc_release,
};

static int proc_show(struct seq_file *m, void *v)
{
	long c = (m->private) ? (long)m->private : 1;

	for (int i = 0; i < c; ++i)
		seq_printf(m, "hello world\n");

	return 0;
}

static int proc_open(struct inode *inode, struct file *filp)
{
	return single_open(filp, proc_show, pde_data(inode));
}

static int proc_release(struct inode *inode, struct file *filp)
{
	return single_release(inode, filp);
}
```

`single_open()` allocates a `seq_file`, calls your `show()` once, and buffers the whole result, that's what lets `seq_read`/`seq_lseek` handle chunked reads and real `llseek` correctly without you writing any offset-tracking code.

Function trace:

```
Start (open) -> Show -> End (close)
```

```
[   62.587970] :proc_open: invoked
[   62.587996] :proc_show: invoked
[   62.588047] :proc_release: invoked
```

#### 3. Using `seq_file` + `seq_operations` - iterating output

> [Full example](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_05_proc_fs_iterator/v7.1.0)

```c
#define pr_fmt(fmt) ":%s: " fmt, __func__

#include <linux/proc_fs.h>
#include <linux/seq_file.h>

static const struct seq_operations proc_seq_ops = {
	.start = proc_seq_start,
	.next  = proc_seq_next,
	.stop  = proc_seq_stop,
	.show  = proc_seq_show,
};

static const struct proc_ops proc_fops = {
	.proc_open    = proc_open,
	.proc_read    = seq_read,
	.proc_lseek   = seq_lseek,
	.proc_release = seq_release,
};

int proc_open(struct inode *inode, struct file *filp)
{
	pr_debug("invoked\n");
	return seq_open(filp, &proc_seq_ops);
}

static char *data[DATA_BLOCK_NUM] = {
	"Day 1: God creates the heavens and the earth.",
	"Day 2: God creates the sky.",
	"Day 3: God creates dry land and all plant life both large and small.",
	"Day 4: God creates all the stars and heavenly bodies.",
	"Day 5: God creates all life that lives in the water.",
	"Day 6: God creates all the creatures that live on dry land.",
	"Day 7: God rests."
};

static void *proc_seq_start(struct seq_file *m, loff_t *pos)
{
	pr_debug("invoked, pos=%lld\n", *pos);
	if (*pos >= ARRAY_SIZE(data)) {
		pr_debug("position requested exceeds the maximum length\n");
		return NULL;
	}
	return *(data + *pos);
}

static void *proc_seq_next(struct seq_file *m, void *v, loff_t *pos)
{
	pr_debug("invoked, pos=%lld\n", *pos);

	(*pos)++;
	if (*pos >= ARRAY_SIZE(data)) {
		pr_debug("position requested exceeds the maximum length\n");
		return NULL;
	}

	return *(data + *pos);
}

static int proc_seq_show(struct seq_file *m, void *v)
{
	pr_debug("invoked\n");

	seq_printf(m, "%p: %s\n", v, (char *)v);
	return 0;
}

static void proc_seq_stop(struct seq_file *m, void *v)
{
	pr_debug("invoked\n");
}
```

> Note that when you're iterating over real kernel state rather than a static array: use locking mechanism in `start()`/`stop()` to protext the data. [see example](https://github.com/torvalds/linux/blob/master/kernel/module/procfs.c#L49)

> Also the `void *` from `start()/next()` doesn't have to be *pos. `seq_file` doesn't care what it is, as long as `show()` knows how to use it. In this example it's just a pointer into `data[]`. If you were walking a real linked list instead, it'd usually be a `struct list_head *` pointing at the current node.

Function trace:

```
Start (open) -> next -> show -> next -> show -> next -> show -> End (close)
```

```
[  899.261954] proc_fs_iterator is loaded
[  904.533344] :proc_open: invoked
[  904.533358] :proc_seq_start: invoked, pos=0
[  904.533359] :proc_seq_show: invoked
[  904.533362] :proc_seq_next: invoked, pos=0
[  904.533363] :proc_seq_show: invoked
[...]
[  904.533369] :proc_seq_next: invoked, pos=6
[  904.533369] :proc_seq_next: position requested exceeds the maximum length
[  904.533370] :proc_seq_stop: invoked
[  904.538378] :proc_seq_start: invoked, pos=7
[  904.538388] :proc_seq_start: position requested exceeds the maximum length
[  904.538388] :proc_seq_stop: invoked
```

> **Why does `proc_seq_start` get invoked twice at the end?**
> `read()` on a `/proc` file isn't a single call. `cat` keeps calling `read()` until it gets 0 bytes back, since that's the EOF signal. So after the iterator exhausts `data[]` and `stop()` runs, userspace issues one more `read()`, which reopens the sequence at the last `*pos` (here, 7) just to confirm there's really nothing left. `start()` returns `NULL`, `seq_read()` returns 0, and only then does `cat` stop calling.
> Putting the three side by side:

|                          | `file_operations`               | `single_show`          | `seq_operations`                        |
| ------------------------ | ------------------------------- | ---------------------- | --------------------------------------- |
| Random access (`llseek`) | Yes                             | No (single blob)       | No, sequential only                     |
| State management         | Manual (own position tracking)  | None needed            | `start`/`next`/`stop` cursor            |
| Use case                 | Legacy, arbitrary seek/read     | Fixed, one-shot output | Iterating kernel object lists           |
| Error surface            | High, positions/offsets by hand | Low                    | Low, but iterator logic must be correct |

**Rule of thumb**: if the output is a single formatted string, `single_show` is the least code for the same result. Use `seq_operations` only when you're iterating over data structure that userspace expects to read top to bottom.

## C Tricks

### `unsigned : 0` in C Bit-Fields

> Sometimes We have particular case, where a field must begin at the next word boundary, so a zero-width bit-field is used.

Consider the following structure:

```c
struct test {
    unsigned a : 3;
    unsigned b : 5;
    unsigned c : 6;
};
```

member of this struct uses only **14 bits** in total (3 + 5 + 6). However, on most systems, `sizeof(struct test)` gives **4 bytes**, not 14 bits.
Because unsigned bit-fields are allocated inside an unsigned int storage unit. If unsigned int is 32 bits, all 14 bits fit into a single 32-bit storage unit.

Typical layout:

```
| a(3) | b(5) | c(6) | unused(18) |
------------------------------------
            one 32-bit unit
```

Now consider:

```c
struct test {
    unsigned a : 3;
    unsigned b : 5;
    unsigned : 0;
    unsigned c : 6;
};
```

The unnamed zero-width bit-field (`unsigned : 0;`) tells the compiler:

> Start the next bit-field at the beginning of a new allocation unit.

Layout becomes:

```
32-bit unit #1:
| a(3) | b(5) | unused(24) |

32-bit unit #2:
| c(6) | unused(26) |
```

As a result, the structure typically occupies **8 bytes**.

**Important Note**

This behavior is **not a compiler optimization**. The C standard leaves bit-field layout as **implementation-defined**, and most compilers choose to allocate `unsigned` bit-fields inside `unsigned int` storage units.

So, `unsigned : 0;` acts as a **boundary marker**, forcing the next bit-field into a new storage unit.


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
>
> ```c
> #define LOG_DEBUG(msg) printk(KERN_DEBUG msg); debug_count++;
> ```
>
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
