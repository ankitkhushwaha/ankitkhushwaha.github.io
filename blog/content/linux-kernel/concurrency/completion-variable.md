---
title: Completion-Variable
weight: 2
---

# Completion-Variable

Completions are a simple synchronization mechanism that is preferable to
sleeping and waking up in some situations. If you have a task that must
simply sleep until some process has run its course, completions can do it
easily and without race conditions

```c
#include <linux/completion.h>

struct completion_dev {
    struct cdev cdev;
    struct completion completion; 
};

struct completion_dev completion_dev;

static int completion_open(struct inode *inode, struct file *filp)
{
	filp->private_data =
		container_of(inode->i_cdev, struct completion_dev, cdev);
	return 0;
}

static ssize_t completion_read(struct file *filp, char __user *buf,
			       size_t count, loff_t *pos)
{
	struct completion_dev *dev = filp->private_data;
    
	pr_debug("process %d(%s) going to sleep\n", current->pid, current->comm);
	wait_for_completion(&dev->completion);
	pr_debug("awoken %d(%s)\n", current->pid, current->comm);

	return 0;
}

static ssize_t completion_write(struct file *filp, const char __user *buf,
				size_t count, loff_t *pos)
{
	struct completion_dev *dev = filp->private_data;
	pr_debug("process %d(%s) awakening the readers...\n", current->pid, current->comm);

	complete(&dev->completion);
	return count;
}

static const struct file_operations completion_fops = {
	.owner = THIS_MODULE,
	.open = completion_open,
	.read = completion_read,
	.write = completion_write,
};

static int __init m_init(void)
{
	int ret;

	init_completion(&completion_dev.completion);

	ret = alloc_chrdev_region(&dev__t, 0, 1, MODULE_NAME);
	if (ret) {
		pr_debug("Error: %d -Cant't get major\n", ret);
		return ret;
	}
	cdev_init(&completion_dev.cdev, &completion_fops);

	ret = cdev_add(&completion_dev.cdev, dev__t, 1);
	[...],
}
```

**References**:
- https://elixir.bootlin.com/linux/v7.1.2/source/include/linux/completion.h