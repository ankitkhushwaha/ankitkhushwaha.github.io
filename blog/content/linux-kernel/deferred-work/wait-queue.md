---
title: Wait Queue
---

# _Wait Queue_

`wait_queue` in the Linux kernel is a data structure to manage threads that are waiting for some condition to become true.

workflow for using `wait_queue` is to first initialize it, and sleep the
thread using family of `wait_event*`. However driver writers should almost always use the `_interruptible` instances of these functions/macros.

Please read the [_lwn.net_](https://lwn.net/Kernel/LDD2/ch05.lwn#t2) explaination on wait queue.

## Code explanation

- 1. This code uses `wait_queue_head_t` to let the thread sleep until there is some data availble to read from or space to write write to with blocking.
- 2. Read/Write methods are blocking in nature if there is no data to read/no space to write.
  - However if file open with `O_NONBLOCK`. I/O is returned immediately instead of blocking.
- 3. Reading the `N` bytes from the buffer reset the `f_pos` to start position and wakes up the write wait queue. Read call sleeps if there is no data to read.
- 4. Similarly Write call wake up read wake queue if it has wrote some bytes to buffer, sleeps if there is no space to write.
- 5. Mutex is used to prevent data corruption.

## _Simple usecase_

see: [_example_](https://github.com/ankitkhushwaha/Linux-Device-Driver/blob/master/eg_08_pipe_simple_sleep/v7.1.0)

### _Read Method_

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

		if (wait_event_interruptible(dev->rd_queue, dev->buff_len))
			return -ERESTARTSYS;
		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}
	[...]

	if (*f_pos >= dev->buff_len) {
    [...]
		wake_up_interruptible(&dev->wr_queue);
	}
	ret = count;
error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```

this method has similar workflow as [poll blog](/blog/linux-kernel/device-driver/poll#read-method) read method. Which sleeps when no data to read, which is done by `wait_event*`, and Wake up the write call path using `wake_up*`. The thread running this read method is waken up by write call.

### _Write Method_

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

		if (wait_event_interruptible(dev->wr_queue, (!dev->buff_len)))
			return -ERESTARTSYS;

		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}
	[...]
	// we have successfully write something in the buff
	if (count > 0) {
	  [...]
		wake_up_interruptible(&dev->rd_queue);
	}
	ret = count;
copy_error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```

Same as [read method](#read-method), but vice-versa in nature.

---

## _Advanced usecase_

this usecase uses the underlying mechanism of the `wait_event*` function.

see: [_example_](https://github.com/ankitkhushwaha/Linux-Device-Driver/blob/master/eg_09_pipe_advanced_sleep/v7.1.0)

### _Read Method_

```c
ssize_t pipe_read(struct file *filp, char __user *buff, size_t count,
		  loff_t *f_pos)
{
	int ret;
	struct pipe_dev *dev = filp->private_data;
	if (mutex_lock_interruptible(&dev->mutex))
		return -ERESTARTSYS;

	while (!dev->buff_len) {
		DEFINE_WAIT(wait);

		mutex_unlock(&dev->mutex);
		if (filp->f_flags & O_NONBLOCK)
			return -EAGAIN;

		prepare_to_wait(&dev->rd_queue, &wait, TASK_INTERRUPTIBLE);
		if (!dev->buff_len)
			schedule();

		finish_wait(&dev->rd_queue, &wait);

		if (signal_pending(current))
			return -ERESTARTSYS;

		if (mutex_lock_interruptible(&dev->mutex))
			return -ERESTARTSYS;
	}

	[...]

	// all data in the buff have been read
	if (*f_pos >= dev->buff_len) {
	  [...]
		wake_up_interruptible(&dev->wr_queue);
	}
	ret= count;
copy_error:
	mutex_unlock(&dev->mutex);
	return ret;
}
```

Here read call first check if there is any data to read. If not it define and initilizes a `wait_queue_entry` using `DEFINE_WAIT`. About Mutex locks and `O_NONBLOCK` already discussed in [poll method](/blog/linux-kernel/device-driver/poll#read-method).
Now it calls `prepare_to_wait`, which add the `wait_queue_entry` node into the queue of `wait_queue_head`. and checks the condition again then yield the cpu, so schedular can run other tasks.
And when this thread is waked up by another thread by calling `wake_up*` family function. It calls `finish_wait`, which basically set the process state to `TASK_RUNNING` and remove the `wait_queue_entry` node from the queue.
At the end, Now buffer has some space availble to write. So it wakes up the thread running the write call.

### Write Method

this method is also similar to [read method](#read-method). But vice-versa in nature.

---

> **Note**: You can see that the `prepare_to_wait` function does the initial wait queue setup, while `finish_wait` cleans up. However for the default cases, when `wait_queue_entry` is initlized by
> `DEFINE_WAIT`. It attaches its `func` member to `autoremove_wake_function` function. Which is eventually
> called by `wake_up*` function and if the function is successfully woken up. It removes the `wait_queue_entry` node from the queue.

```c
#define DEFINE_WAIT_FUNC(name, function)                                        \
        struct wait_queue_entry name = {                                        \
                .private        = current,                                      \
                .func           = function,                                     \
                .entry          = LIST_HEAD_INIT((name).entry),                 \
        }
#define DEFINE_WAIT(name) DEFINE_WAIT_FUNC(name, autoremove_wake_function)
```

Here it initilizes the `wait_queue_entry` with `autoremove_wake_function` function.

And if you underlying core wake function `__wake_up_common`. which calls

```c
list_for_each_entry_safe_from(curr, next, &wq_head->head, entry) {
    [...],
    ret = curr->func(curr, mode, wake_flags, key);
    [...],
}


```

so now `autoremove_wake_function` function wake up the process.

```c
int autoremove_wake_function(struct wait_queue_entry *wq_entry, unsigned mode, int sync, void *key)
{
    int ret = default_wake_function(wq_entry, mode, sync, key);
    if (ret)
            list_del_init_careful(&wq_entry->entry);
    return ret;
}
```

If the function is woken up then it removes the node from queue.

And if you check the `finish_wait`

```c
void finish_wait(struct wait_queue_head *wq_head, struct wait_queue_entry *wq_entry)
{
        unsigned long flags;
        __set_current_state(TASK_RUNNING);
        if (!list_empty_careful(&wq_entry->entry)) {
                spin_lock_irqsave(&wq_head->lock, flags);
                list_del_init(&wq_entry->entry);
                spin_unlock_irqrestore(&wq_head->lock, flags);
        }
}
```

which set the current running process state to `TASK_RUNNING` and try to remove the node from queue, if it is not removed (in case when custom `wait_queue_func_t` func is used).

## **References:**

- https://lwn.net/Kernel/LDD2/ch05.lwn#t2
- https://lwn.net/Articles/22913/
- https://lwn.net/Articles/83633/
- https://lwn.net/Articles/628628/
- https://static.lwn.net/images/pdf/LDD3/ch06.pdf - `Advanced Sleeping` section
