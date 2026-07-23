---
title: Return value by Macro
---

code example of macro which returns a value.

```c
#include <stdio.h>

#define check(condition)                   \
    ({                                     \
        int __ret = 0;                     \
        if (!(condition))                  \
        {                                  \
            printf("Condition failed!\n"); \
            __ret = -1;                    \
        }                                  \
        __ret;                             \
    })

int main()
{
    int x = 10;
    int result = check(x > 15);

    printf("result: %d", result);
    return 0;
}
```