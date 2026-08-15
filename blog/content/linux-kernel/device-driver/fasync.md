---
title: fasync Method
---

# Asynchronous Notification aka `fasync`

In userspace apps, We can have some usecases, where we have to wait for I/O to occur.
In simple case we
read a file either it is NON_BLOCKING (with `O_NONBLOCK` flag) or BLOCKING
in nature. This waste a lot of cpu resources. To prevent this we can use various
methods. Here we'll talk about `.fasync` method of `file_operations`. This method
similary work like `poll` method, sending signal to userspace usually `SIGIO`.

_**References**_: please read lwn.net blog before proceding,
[here](https://lwn.net/Kernel/LDD2/ch05.lwn#t4).

## Internals Worflow

```
Application
    |
`fcntl(O_ASYNC)`
    |
driver->fasync()
    |
Registers process with `fasync_helper`
    |
Interrupt / New data
    |
`kill_fasync()`
    |
Kernel sends `SIGIO`
    |
Application receives signal
```

*see*: 
[*code example*](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_11_asynchronous_notification/v7.1.0


## *Read Method*

```c
ssize_t async_notify_read(struct file *filp, char __user *buff, size_t count,
			  loff_t *f_pos)
{
	int ret;
	struct async_notify_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;

	if (count > dev->buf_len - *f_pos)
		count = dev->buf_len - *f_pos;

	if (copy_to_user(buff, dev->buff + *f_pos, count)) {
		ret = -EFAULT;
		goto cpy_user_error;
	}
	*f_pos += count;
	ret = count;
cpy_user_error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```

Normal read function nothing fancy.

## *Async and Release Method*

```c
int async_notify_fasync(int fd, struct file *filp, int mode)
{
	struct async_notify_dev *dev = filp->private_data;

	return fasync_helper(fd, filp, mode, &dev->async_queue);
}

int async_notify_release(struct inode *inode, struct file *filp)
{
	// remove the async_queue from the file
	struct async_notify_dev *dev = filp->private_data;
	return fasync_helper(-1, filp, 0, &dev->async_queue);
}
```

*fasync_helper()* registers/unregisters a file for asynchronous notification
using the *async_queue*.
mode = 1 → add the file's fasync entry to *async_queue*
mode = 0 → remove the file's fasync entry from *async_queue*

## *Write Method*

```c
ssize_t async_notify_write(struct file *filp, const char __user *buff,
			   size_t count, loff_t *f_pos)
{
	int retval;
	struct async_notify_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;

	if (count > BUFF_SIZE - *f_pos)
		count = BUFF_SIZE - *f_pos;

	if (copy_from_user(dev->buff + *f_pos, buff, count)) {
		retval = -EFAULT;
		goto cpy_user_error;
	}
	*f_pos += count;
	dev->buf_len = *f_pos;
	retval = count;

	if (dev->async_queue) {
	    kill_fasync(&dev->async_queue, SIGIO, POLL_IN);
	}
cpy_user_error:
	mutex_unlock(&dev->mutex);
	return retval;
}
```

At the end of write method, When Buffer has some data. `kill_fasync` is called,
which will send the signal(notification/interrupt) usually `SIGIO` to all of
the file owner process that are registered with `fasync_helper`.

## *UserSpace Code*

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <fcntl.h>

#define DEV_FILE "/dev/async_notify"

static int gotdata = 0;
static char buffer[4096] = { 0 };

void sighandler(int signo)
{
	if (signo == SIGIO)
		gotdata++;
	return;
}

int main(int argc, char **argv)
{
	int count, fd;
	struct sigaction action;

	memset(&action, 0, sizeof(action));
	action.sa_handler = sighandler;
	action.sa_flags = 0;

	sigaction(SIGIO, &action, NULL);

	fd = open(DEV_FILE, O_RDONLY);
	fcntl(fd, F_SETOWN, getpid());

	int flags = fcntl(fd, F_GETFL);
	fcntl(fd, F_SETFL, flags | FASYNC);

	while (1) {
		sleep(1);

		if (!gotdata) {
			printf("no signal, continue!\n");
			continue;
		}
		printf("signal is catched\n");
		gotdata = 0;

		count = read(fd, buffer, 4096);
		printf("%s\n", buffer);
	}

	return 0;
}
```

We can see that process running this code is registered with custom signal
handler function `sighandler` using `sigaction` for signal `SIGIO`. And
set process to file as owner of this file using `F_SETOWN`. and update the
file descriptor to add `FASYNC` for asynchronous notification. When `SIGIO`
signal is recieved to process, signer handler runs which increments the
`gotdata` and read call is invoked.

## Summary

Asynchronous notification is useful in cases when we userspace want to be notified when
a device event occurs without continuously blocking in read() or repeatedly polling
the device.
