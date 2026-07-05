---
title: do { ... } while (0)
weight: 2
---

### The Structural Wrapper: `do { ... } while (0)`

Standard macro design pattern. Forces the macro to behave like a single C statement, so it can't break syntax when used inside an `if/else` without braces.

```c
#define LOG_DEBUG(msg) do { \
    printk(KERN_DEBUG msg); \
    debug_count++; \
} while (0)

if (tmp)
    LOG_DEBUG("checking condition\n");
else
    do_something();
```

> Two statements is where this trick stops being a nice-to-have and becomes necessary. Without the wrapper:
>
> ```c
> #define LOG_DEBUG(msg) printk(KERN_DEBUG msg); debug_count++;
> ```
>
> expands the `if` branch into two separate statements, only the first one belongs to the `if`, the second runs unconditionally regardless of `tmp`. Wrap braces `{ }` around it instead and you hit the classic dangling-`;` problem: the trailing `;` after the macro call becomes an empty statement, and the `else` ends up with no matching `if`.

The `do { } while (0)` fixes both: it groups any number of statements into one block, and swallows the semicolon you put after the macro call. `while (0)` never loops, so the compiler optimizes it away, zero runtime cost.

