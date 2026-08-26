---
title: Tasklet
---

# _Tasklet_

See: [embetronicx tutorial](https://embetronicx.com/tutorials/linux/device-drivers/tasklet-static-method/)

```c
#include <linux/interrupt.h>

static struct tasklet_struct tlet;
static wait_queue_head_t wait;
static int loop = 5;
static int timeout = 0;

static void print_tasklet(unsigned long data)
{
	pr_debug("invoked from tasklet\n");

	if (!loop) {
		timeout = 1;
		wake_up_interruptible(wait);
		return;
	}

	loop--;
	tasklet_schedule(tlet);
}

static int read_tasklet(struct file *filp, char __user *buf, size_t size, loff_t *f_pos)
{
	tasklet_init(tlet, jiq_print_tasklet, (unsigned long)data);

	tasklet_schedule(tlet);
	wait_event_interruptible(jiq_wait, timeout);
	return 0;
}

static struct file_operations fops = {
	.read = read_tasklet,
};

```

Here u can assume that `wait_queue_head_t` is already initilized.

`tasklet` is linked to read call, when read call is triggered, `tasklet` gets schedule which schedule itself in `print_tasklet`. While read call sleep until `print_tasklet` triggered `loop` times and waked up by `print_tasklet`.

## _References_

- https://embetronicx.com/tutorials/linux/device-drivers/tasklet-static-method/
