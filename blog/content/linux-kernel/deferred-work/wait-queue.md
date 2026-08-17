---
title: Wait Queue
---

# *Wait Queue*

`wait_queue` in the Linux kernel is a data structure to manage threads that are waiting for some condition to become true.

workflow for using `wait_queue` is to first initialize it, and sleep the 
thread using family of `wait_event*`. However driver writers should almost always use the `_interruptible` instances of these functions/macros.

Please read the [*lwn.net*](https://lwn.net/Kernel/LDD2/ch05.lwn#t2) explaination on wait queue.

## Code explanation

  - 1. This code uses `wait_queue_head_t` to let the thread sleep until there is some data availble to read from or space to write write to with blocking.
- 2. Read/Write methods are blocking in nature if there is no data to read/no space to write.
    - However if file open with `O_NONBLOCK`. I/O is returned immediately instead of blocking.
- 3. Reading the `N` bytes from the buffer reset the `f_pos` to start position and wakes up the write wait queue. Read call sleeps if there is no data to read.
- 4. Similarly Write call wake up read wake queue if it has wrote some bytes to buffer, sleeps if there is no space to write.
- 5. Mutex is used to prevent data corruption.

## *Simple usecase*

code example: [*example*](https://github.com/ankitkhushwaha/Linux-Device-Driver/blob/master/eg_08_pipe_simple_sleep/v7.1.0)

### *Read Method*

```c
ssize_t pipe_read(struct file *filp, char __user *buff, size_t count,
		  loff_t *f_pos)
{
	int ret;
	struct pipe_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;
	while (!dev->buff_len) {
		mutex_unlock(&dev->mutex);

		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;
		pr_debug("read: process %d(%s) going to sleep", current->pid,
			 current->comm);
		if (wait_event_interruptible(dev->rd_queue, dev->buff_len))
			return -ERESTARTSYS;
		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}
	if (count > dev->buff_len - *f_pos)
		count = dev->buff_len - *f_pos;
	if (copy_to_user(buff, dev->buff + *f_pos, count)) {
		pr_debug("copy to user error!\n");
		ret = -EFAULT;
		goto error;
	}
	pr_debug("read: f_pos=%lld, count=%lu, buff_len=%d\n", *f_pos, count,
		 dev->buff_len);
	*f_pos += count;
	if (*f_pos >= dev->buff_len) {
		dev->buff_len = 0;
		*f_pos = 0;
		pr_debug("read: process %d(%s) awakening the writers...\n",
			 current->pid, current->comm);
		wake_up_interruptible(&dev->wr_queue);
	}
	ret = count;
error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```
this method has similar workflow as [poll blog](/blog/linux-kernel/device-driver/poll#read-method) read method. Which sleeps when no data to read, which is done by `wait_event*`, and Wake up the write call path using `wake_up*`. The thread running this read method is waken up by write call.

### *Write Method*

```c
ssize_t pipe_write(struct file *filp, const char __user *buff, size_t count,
		   loff_t *f_pos)
{
	int ret;
	struct pipe_dev *dev = filp->private_data;

	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;
	while (dev->buff_len) {
		mutex_unlock(&dev->mutex);

		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;
		pr_debug("process %d(%s) is going to sleep\n", current->pid,
			 current->comm);
		if (wait_event_interruptible(dev->wr_queue, (!dev->buff_len)))
			return -ERESTARTSYS;
		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}
	if (count > BUFF_SIZE - *f_pos)
		count = BUFF_SIZE - *f_pos;
	if (copy_from_user(dev->buff + *f_pos, buff, count)) {
		pr_debug("write: copy to user error!\n");
		ret = -EFAULT;
		goto copy_error;
	}
	pr_debug("write: f_pos=%lld, count=%lu, buff_len=%d\n", *f_pos, count,
		 dev->buff_len);
	// we have successfully write something in the buff
	if (count > 0) {
		dev->buff_len = count;
		*f_pos = 0;
		pr_debug("write: process %d(%s) awakening the readers...\n",
			 current->pid, current->comm);
		wake_up_interruptible(&dev->rd_queue);
	}
	ret = count;
copy_error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```
Same as [read method](#read-method), but vice-versa in nature.

## Advanced usecase
