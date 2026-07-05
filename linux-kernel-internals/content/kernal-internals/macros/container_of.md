---
title: container_of()
weight: 2
---

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

