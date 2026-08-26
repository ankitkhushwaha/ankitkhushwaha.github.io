---
title: Timers
---

# Kernel timers

See: [embetronicx tutorial](https://embetronicx.com/tutorials/linux/device-drivers/using-kernel-timer-in-linux-device-driver/)

```c
#include <linux/timer.h>

static struct timer_list *timer;
static int loop = 5;

static void timer_fn(struct timer_list *t)
{
    pr_info("timer function invoked\n");
    if (loop--) {
        timer.expires = jiffies + HZ;
        add_timer(timer);
    }
}

static void init_dev(void)
{
    [...]
    timer_setup(timer, timer_fn, 0);
    timer.expires = jiffies + HZ;
   	add_timer(&timer);
    [...]
}
```

## _References_

- https://embetronicx.com/tutorials/linux/device-drivers/using-kernel-timer-in-linux-device-driver/
- https://lwn.net/Articles/646950/
- https://static.lwn.net/images/pdf/LDD3/ch07.pdf
- https://lwn.net/Articles/913568/
