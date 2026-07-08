---
title: Proc-Interface
weight: 5
---

## Proc Interface

`/proc` is the classic way a driver hands kernel-side information to userspace without going through a real block device. There are three ways to implement the read side of a proc entry, depends on whether you're exposing a single fixed value or walking a list.

> Keep a note that this method is **depreciated** for device driver.

### 1. Raw `file_operations` - the old way

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

### 2. Using `seq_file` + `single_open`

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

### 3. Using `seq_file` + `seq_operations` - iterating output

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
