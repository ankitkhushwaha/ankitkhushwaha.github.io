---
title: Stringification
weight: 2
---

## Stringification

`include/linux/stringify.h` defines:

```c
#define __stringify_1(x...)    #x
#define __stringify(x...)      __stringify_1(x)
```

Both use `#` to turn an argument into a string literal. They differ only when the argument is a macro.

`#` stringifies tokens *before* expanding any macros in them. So `__stringify_1(x)` gives you the literal text you passed, macro name included, unexpanded.

`__stringify(x)` adds one layer of indirection. Since `x` isn't touched directly by `#` inside `__stringify`, the preprocessor expands `x` first when it's passed down to `__stringify_1`, which then stringifies the *expanded* result.

Example:

```c
#define KVERSION 6

pr_info("%s\n", __stringify_1(KVERSION));
// "KVERSION"

pr_info("%s\n", __stringify(KVERSION));
// "6"

char *hello = "world";

pr_info("%s\n", __stringify_1(hello));
// "hello"

pr_info("%s\n", __stringify(hello));
// "hello"

```

For a non-macro token: a variable name, a plain string, there's nothing to expand, so both macros produce the same output. 

> **Note**: The indirection only work when the argument is a `#define`.