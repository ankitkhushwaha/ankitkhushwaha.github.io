---
title: Error Handling
weight: 5
---

### Error Handling for complex cases

Standard kernel pattern for unwinding partial allocations when a loop fails mid-way.

```c
int ret;
int i;

for (i = 0; i < count; i++)
{
    arr1[i] = kmalloc(size1, GFP_KERNEL);
    if (!arr1[i]) {
        ret = -ENOMEM;
        goto err;
    }
    arr2[i] = kmalloc(size2, GFP_KERNEL);
    if (!arr2[i]) {
		/* error handling in mid-way loop */
        kfree(arr1[i]);
        arr1[i] = NULL;
        ret = -ENOMEM;
        goto err;
    }
}

	return 0;

err:
	while (--i >= 0)
	{
		kfree(arr2[i]);
		kfree(arr1[i]);
	}
	return ret;
```
