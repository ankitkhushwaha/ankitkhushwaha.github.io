---
title: "Zero Padding in C"
---

# Zero Padding in C with `printf`

In C, `printf()` can add leading zeros to make a number occupy a fixed minimum width.

The syntax is:

```c 
%0<width><specifier>
```

For example:

```c
printf("%06d", 123);
```


Output:

```text
000123
```

Here:

* `0` → pad with zeros
* `6` → minimum field width is 6 characters
* `d` → print a signed decimal integer

### Zero padding vs space padding

```c
printf("%06d", 123);
```

Output:

```text
000123
```

while:

```c
printf("%6d", 123);
```

Output:

```text
   123
```

So:

```text
%06d → zero padding
%6d  → space padding
```

### Example: hexadecimal

```c
printf("0x%08lx\n", value);
```

For:

```c
value = 0x1234;
```

the output is:

```text
0x00001234
```

`%08lx` means:

* `0` → zero padding
* `8` → minimum width of 8 characters
* `l` → `long`
* `x` → hexadecimal

Zero padding is useful when displaying **IDs, hexadecimal values, timestamps, counters, or other fixed-width numbers** where aligned output is desirable.
