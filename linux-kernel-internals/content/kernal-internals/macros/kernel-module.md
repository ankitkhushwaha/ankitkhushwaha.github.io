---
title: Module Parameters
weight: 2
---

## Module Parameters

```c
#include <linux/module.h>
#include <linux/moduleparam.h>  /* not strictly needed, linux/module.h already pulls it in */
#include <linux/kernel.h>

module_param(name, type, perm);
MODULE_PARM_DESC(myarr, "this is my array of int");
```

Pass the value at load time:

```bash
insmod module.ko param=value
```
