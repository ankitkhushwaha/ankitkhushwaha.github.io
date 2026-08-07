---
title: Poll Method
---

## Poll Method

> Please first read the `lwn.net` explaination about Poll and Select Method [here](https://lwn.net/Kernel/LDD2/ch05.lwn#t3).

Poll method is one of method of `file_operations` that allow a process to determine whether it can read from or write to one or more open files without blocking.

see: [code example](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_10_poll/v7.1.0)

### Code explanation
This code is different from the [earlier version](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_10_poll/v5.10) in which a timer runs a function after particular interval of time.

- 1. This code uses a poll method to find whether it can read from or write to without blocking.
- 2. Read/Write methods are blocking in nature if there is no data to read/no space to write.
    - However if file open with `O_NONBLOCK` I/O is returned immediately instead of blocking.
- 3. Reading the `N` bytes from the buffer flushes the `N` bytes from buffer and that space is freed. Read call sleep if there is no data to read and wakes up the write wait queue at the end of read call.
- 4. Similarly Write call sleeps if there is no space to write. and wake up read wake queue if it has wrote some bytes to buffer.
- 5. Mutex is used to prevent data corruption.
- 6. read/write method doesn't support `seek` method.

#### Read Method

In the read method the following lines of code was most confusing to me. So i'll explaining it to my future self.

- 1. 
```c
	while (dev->buf_len == 0) {
		mutex_unlock(&dev->mutex);

		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;

		if (wait_event_interruptible(dev->inq, dev->buf_len > 0))
			return -ERESTARTSYS;

		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}
```


### *Kernelspace code*
```c
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/poll.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/device.h>

static struct poll_dev *poll_dev;
static dev_t dev__t;
struct class *class_poll;
struct device *device_poll;

int poll_open(struct inode *inode, struct file *filp)
{
	filp->private_data = container_of(inode->i_cdev, struct poll_dev, cdev);
	return 0;
}

ssize_t poll_read(struct file *filp, char __user *buff, size_t count,
		  loff_t *f_pos)
{
	int retval;
	struct poll_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;

	while (dev->buf_len == 0) {
		mutex_unlock(&dev->mutex);

		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;

		if (wait_event_interruptible(dev->inq, dev->buf_len > 0))
			return -ERESTARTSYS;

		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}

	if (count > dev->buf_len) {
		count = dev->buf_len;
	}

	if (copy_to_user(buff, dev->buff, count)) {
		retval = -EFAULT;
		goto cpy_user_error;
	}

	memmove(dev->buff, dev->buff + count, dev->buf_len - count);
	dev->buf_len -= count;
	retval = count;

	wake_up_interruptible(&dev->outq);
cpy_user_error:
	mutex_unlock(&dev->mutex);
	return retval;
}

ssize_t poll_write(struct file *filp, const char __user *buff, size_t count,
		   loff_t *f_pos)
{
	int retval;
	struct poll_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;

	while (dev->buf_len == BUFF_SIZE) {
		mutex_unlock(&dev->mutex);

		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;

		if (wait_event_interruptible(dev->outq,
					     dev->buf_len < BUFF_SIZE))
			return -ERESTARTSYS;

		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}

	if (count > (BUFF_SIZE - dev->buf_len))
		count = BUFF_SIZE - dev->buf_len;

	if (copy_from_user(dev->buff + dev->buf_len, buff, count)) {
		retval = -EFAULT;
		goto cpy_user_error;
	}

	dev->buf_len += count;
	retval = count;

	wake_up_interruptible(&dev->inq);
cpy_user_error:
	mutex_unlock(&dev->mutex);
	return retval;
}

unsigned int poll_poll(struct file *filp, poll_table *wait)
{
	struct poll_dev *dev = filp->private_data;
	unsigned int mask = 0;

	mutex_lock(&dev->mutex);

	poll_wait(filp, &dev->inq, wait);
	poll_wait(filp, &dev->outq, wait);

	if (dev->buf_len > 0) {
		pr_debug("Now fd can be read\n");
		mask |= POLLIN | POLLRDNORM;
	}

	if (dev->buf_len < BUFF_SIZE) {
		pr_debug("fd can be written\n");
		mask |= POLLOUT | POLLWRNORM;
	}
	mutex_unlock(&dev->mutex);

	pr_debug("return mask = 0x%x\n", mask);
	return mask;
}

static struct file_operations fops = {
	.open = poll_open,
	.read = poll_read,
	.write = poll_write,
	.poll = poll_poll,
};

static void __init init_dev(struct poll_dev *dev)
{
	mutex_init(&dev->mutex);
	init_waitqueue_head(&dev->inq);
	init_waitqueue_head(&dev->outq);

	cdev_init(&dev->cdev, &fops);
	dev->cdev.owner = THIS_MODULE;

	dev->buf_len = ARRAY_SIZE(DFT_MSG);
	memcpy(dev->buff, DFT_MSG, dev->buf_len);
}

static int __init m_init(void)
{
	int ret;
	poll_dev = kzalloc(sizeof(*poll_dev), GFP_KERNEL);

	ret = alloc_chrdev_region(&dev__t, 0, POLL_DEV_NR, MODULE_NAME);

	init_dev(poll_dev);
	ret = cdev_add(&poll_dev->cdev, dev__t, POLL_DEV_NR);

	class_poll = class_create(MODULE_NAME);
	device_poll = device_create(class_poll, NULL, dev__t, NULL, MODULE_NAME);
	return 0;
/* Error handling */
	return ret;
}
```

### *UserSpace code*:

```c
#include <stdio.h>
#include <poll.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#define DEV_PATH "/dev/poll"

#define BUF_LEN 1024

char buff[1024] = { 0 };

int main(void)
{
	int fd = open(DEV_PATH, O_RDWR);
	if (fd < 0) {
		printf("open %s error\n", DEV_PATH);
		return -1;
	}

	struct pollfd pollfd = { fd, POLLIN | POLLOUT, 0 };

	int c = 2;
	while (c--) {
		printf("polling ...\n");

		int err = poll(&pollfd, 1, -1);
		if (err < 0) {
			printf("poll error\n");
			break;
		}

		if (pollfd.revents & POLLIN) {
			read(pollfd.fd, buff, BUF_LEN);
			printf("[%d] read: %s\n", pollfd.fd, buff);
		}

		if (pollfd.revents & POLLOUT) {
			int len = sprintf(buff, "Hello world! -> %d", c);
			write(pollfd.fd, buff, len);
			printf("[%d] write: %s\n", pollfd.fd, buff);
		}
	}

	close(fd);

	return 0;
}
```
