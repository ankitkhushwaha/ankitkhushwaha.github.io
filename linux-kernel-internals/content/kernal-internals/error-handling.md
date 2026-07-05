---
title: Error Handling with Pointers
weight: 2
---

## Error Handling with Pointers in the Kernel

Many kernel functions return either a valid pointer on success or an encoded error code on failure. this lets a single return value carry both success and failure info, keeping the function signature clean.

In `include/linux/err.h`:

```c
#define MAX_ERRNO   4095
```

This is the largest error number the kernel uses. No kernel pointer will ever legitimately point into the very top of the address space,
that range is reserved to encode error codes instead, Because kernel reserves a small range of addresses at the very top of the virtual address space and these addresses are invalid as actual memory locations.

```c
#define IS_ERR_VALUE(x) \
    unlikely((unsigned long)(void *)(x) >= (unsigned long)-MAX_ERRNO)
```

Cast to `unsigned long`, a small negative error code like `-22` (`-EINVAL`) becomes a huge number close to `ULONG_MAX`. So checking `x >= -MAX_ERRNO` really give "is this value one of the last 4095 possible addresses?"  if yes, it's not a real pointer, it's an error.

**The three macros**

| Macro | What it does | Returns |
|---|---|---|
| `ERR_PTR(err)` | Encodes a negative error code as a pointer | `(void *)err` |
| `IS_ERR(ptr)` | Checks if a pointer is actually an encoded error | `true`/`false` |
| `PTR_ERR(ptr)` | Decodes the error number back to the pointer | `long` (the error code) |

**Typical usage**

```c
struct foo *p = some_kernel_function();

if (IS_ERR(p))
    return PTR_ERR(p);   // propagate the error code

// otherwise p is safe to use
```