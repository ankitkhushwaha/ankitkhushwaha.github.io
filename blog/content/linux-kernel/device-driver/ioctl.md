---
title: Ioctl Interface
weight: 2
---

# ioctl

The ioctl() function manipulates the underlying device parameters of special
files. Most devices can perform operations beyond simple data transfers; user
space must often be able to request, for example, that the device lock its door,
eject its media, report error information, change a baud rate, or self destruct.
These operations are usually supported via the ioctl method.

> `lwn.net` have wonderful explaination on ioctl, i suggest you read it, [here](https://lwn.net/Kernel/LDD2/ch05.lwn#t1) to know the internals.

```c
#define IOCTL_IOC_MAGIC 'd'
#define IOCTL_MAXNR 2

struct ioctl_dev {
    struct cdev cdev;
};

int ioctl_open(struct inode *inode, struct file *filp)
{
	filp->private_data =
		container_of(inode->i_cdev, struct ioctl_dev, cdev);
	return 0;
}

long ioctl_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	int ret;
	struct ioctl_dev *ioctl_dev = filp->private_data;

	if (_IOC_TYPE(cmd) != IOCTL_IOC_MAGIC) {
		pr_warn("magic mismatch IOCTL failed\n");
		return -ENOTTY;
	}

	if (_IOC_NR(cmd) > IOCTL_MAXNR) {
		pr_warn("invalid ioctl call\n");
		return -ENOTTY;
	}

	ret = access_ok((void __user *)arg, _IOC_SIZE(cmd));
	if (!ret)
		return -EFAULT;

	switch (cmd) {
	case IOCTL_RESET:
		ret = ioctl_reset(ioctl_dev);
		break;
	case IOCTL_HOWMANY:
		ret = ioctl_howmany(ioctl_dev, (unsigned long)arg);
		break;
	case IOCTL_MESSAGE:
		ret = ioctl_message(ioctl_dev, (void *__user)arg);
		break;
	default:
		return -ENOTTY;
	}
	return  ret;
}

static struct file_operations fops = {
	.open = ioctl_open,
	.unlocked_ioctl = ioctl_ioctl,
};

static int __init m_init(void)
{
	int ret;

	ioctl_dev = kzalloc(sizeof(*ioctl_dev), GFP_KERNEL);

	ret = alloc_chrdev_region(&dev__t, 0, IOCTL_DEV_NR, MODULE_NAME);

	cdev_init(&ioctl_dev->cdev, &fops);
	ioctl_dev->cdev.owner = THIS_MODULE;

	ret = cdev_add(&ioctl_dev->cdev, dev__t, IOCTL_DEV_NR);
    [...]
}
```