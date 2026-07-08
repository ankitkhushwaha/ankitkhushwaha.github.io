---
title: "Variadic Macro"
---

In kernel you'll see two type of variaidic macro

```c
#define __stringify(x...)	   __stringify_1(x)
```

this is same as 

```c
#define __stringify(...)	   __stringify_1(__VA_ARGS__)
```

In standard C99 and later, a variadic macro must look like above one, 
However, GCC introduced an extension that allows you to give a name to the variable arguments by placing the ellipsis immediately after an identifier `(x...)`.
When you write `x...`, the compiler treats x as a named parameter that bundles everything passed into the macro (including any commas separating multiple arguments).

> Note: there is `ellipsis (...)` parameter for c function also, that allow the function to accept any number of pararmeters.