---
title: Poll Method
---

# Poll Method

> Please first read the [*lwn.net*](https://lwn.net/Kernel/LDD2/ch05.lwn#t3) explaination about Poll and Select method.

Poll method is one of method of `file_operations` that allow a process to determine whether it can read from or write to one or more open files without blocking.

see: [*code example*](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_10_poll/v7.1.0)

## Code explanation
This code is different from the [*earlier version*](https://github.com/ankitkhushwaha/Linux-Device-Driver/tree/master/eg_10_poll/v5.10) in which a timer runs a function after particular interval of time.

- 1. This code uses a poll method to find whether it can read from or write to without blocking.
- 2. Read/Write methods are blocking in nature if there is no data to read/no space to write.
    - However if file open with `O_NONBLOCK` I/O is returned immediately instead of blocking.
- 3. Reading the `N` bytes from the buffer flushes the `N` bytes from buffer and that space is freed and wakes up the write wait queue at the end of read call. Read call sleeps if there is no data to read.
- 4. Similarly Write call wake up read wake queue if it has wrote some bytes to buffer, sleeps if there is no space to write.
- 5. Mutex is used to prevent data corruption.
- 6. This read/write method doesn't support `seek` method.

## *Read Method*

```c
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
```

conditon check if no data to read in while loop, unlock the mutex,
so other thread can access it. setup wait queue and goes to sleep,
which will wake up when buffer has some data by `wake_up{,_interruptible}`.
Now Buffer has some data to read, but we can have other threads that can read
the buffer, and data flushes out from buffer. So again check the buffer
conditon, then lock with the mutex. remove the data that has been read.
wake up the write wait queue, so write call can write the data. 

## *Write Method*

```c
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
```
Same internals as read method. 

## *Poll Method*
```c
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
```

UserSpace call the poll function -> driver poll method is called. Poll Method
register the process with wake queues `dev->{inq,outq}`, And check the buffer
state. If neither of conditon is true, it return 0, and this process eventually
sleeps and wakes up when some other process call `wake_up*` family function
on it. So process associated with poll method wakes up again, and
check the buffer state and return the mask value to userspace.
