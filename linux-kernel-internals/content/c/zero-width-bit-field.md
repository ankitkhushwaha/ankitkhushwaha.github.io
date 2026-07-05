---
title: unsigned :\ 0 Bit-Fields in c
weight: 1
---

### `unsigned : 0` in C Bit-Fields

> Sometimes We have particular case, where a field must begin at the next word boundary, so a zero-width bit-field is used.

Consider the following structure:

```c
struct test {
    unsigned a : 3;
    unsigned b : 5;
    unsigned c : 6;
};
```

member of this struct uses only **14 bits** in total (3 + 5 + 6). However, on most systems, `sizeof(struct test)` gives **4 bytes**, not 14 bits.
Because unsigned bit-fields are allocated inside an unsigned int storage unit. If unsigned int is 32 bits, all 14 bits fit into a single 32-bit storage unit.

Typical layout:

```
| a(3) | b(5) | c(6) | unused(18) |
------------------------------------
            one 32-bit unit
```

Now consider:

```c
struct test {
    unsigned a : 3;
    unsigned b : 5;
    unsigned : 0;
    unsigned c : 6;
};
```

The unnamed zero-width bit-field (`unsigned : 0;`) tells the compiler:

> Start the next bit-field at the beginning of a new allocation unit.

Layout becomes:

```
32-bit unit #1:
| a(3) | b(5) | unused(24) |

32-bit unit #2:
| c(6) | unused(26) |
```

As a result, the structure typically occupies **8 bytes**.

**Important Note**

This behavior is **not a compiler optimization**. The C standard leaves bit-field layout as **implementation-defined**, and most compilers choose to allocate `unsigned` bit-fields inside `unsigned int` storage units.

So, `unsigned : 0;` acts as a **boundary marker**, forcing the next bit-field into a new storage unit.