---
title: Debugging Macros
BookComments: false
---

# Debugging Macros

This section will contain all macros related to kernel debugging.

## `might_sleep`

configs
- `CONFIG_DEBUG_ATOMIC_SLEEP`

this macros is useful to detect sleeping function called in Non sleeping code-paths,
and implies that code path should not be executed in atomic context, since it can sleep.

```c
/**
 * might_sleep - annotation for functions that can sleep
 *
 * this macro will print a stack trace if it is executed in an atomic
 * context (spinlock, irq-handler, ...). Additional sections where blocking is
 * not allowed can be annotated with non_block_start() and non_block_end()
 * pairs.
 *
 * This is a useful debugging help to be able to catch problems early and not
 * be bitten later when the calling function happens to sleep when it is not
 * supposed to.
 */
# define might_sleep() \
        do { __might_sleep(__FILE__, __LINE__); might_resched(); } while (0)
```
