---
title: pr_fmt()
weight: 2
---
## `pr_fmt()`

### Prefixing the `pr_*()` calls

`pr_fmt()` is a macro that rewrites the format string of every `pr_*()` call (`pr_info`, `pr_warn`, `pr_err`, ...) in the file. It has to be defined **before** any header that pulls in `<linux/printk.h>`, so it always sits at the very top, above your includes.

```c
#define pr_fmt(fmt) KBUILD_MODNAME ":%s: " fmt, __func__

#include <linux/kernel.h>
#include <linux/module.h>

static int func(void)
{
	pr_warn("hello-world\n");
	return -1;
}
```

`pr_fmt()` line auto-adjusts to whichever function it's expanded in.

Expands to roughly:

```c
printk(KERN_WARNING "hello-world\n");
```

Without `pr_fmt()`, every `pr_*()` line falls back to the default `"%s"`, no module or function context, so you're stuck grepping `dmesg` blind. With it, every log line self-identifies:

```
[   12.482103] module_name:func: hello-world
```

> Default fallback is `#define pr_fmt(fmt) fmt`, just the format string, untouched, if you never define your own.
> and only affects the `pr_*()` family, not raw `printk(KERN_WARNING ...)` calls.