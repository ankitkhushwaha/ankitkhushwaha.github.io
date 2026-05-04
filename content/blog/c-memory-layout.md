---
date: '2026-05-04T13:30:05+05:30'
draft: false
title: 'C Memory Layout: Structs, Unions, and a Linux Kernel Patch'
tags: ["c-programming", "memory-layout", "linux-kernel", "flexible-array-members", "structs-unions", "compiler-warnings", "kernel-development", "low-level-c"]
---

# Overview

C memory layout looks simple in isolation: structs store fields sequentially, unions overlap memory, and flexible array members allow variable-sized trailing storage. But combining these features can create subtle layout issues.

While working on a Linux kernel selftest, I encountered a case where a union contained multiple structures, each ending with a flexible array member at different offsets. Although the code was functionally correct, this confused the compiler into treating the union as effectively variable-sized, triggering a layout warning.

This article tackles an unusual case: **what happens when you place variable-sized structs (structs with FAMs) inside a union?** The answer reveals elegant C patterns for memory aliasing and why `offsetof` is a zero-cost tool for precision.

We will start by understanding how structs, unions, and flexible array members are laid out in memory, then use a real Linux kernel patch to see how these rules interact in practice.

# 1. Struct Memory Layout

In C, a `struct` lays out its fields **sequentially** in memory, from top to bottom.
The compiler may insert invisible **padding bytes** between fields to satisfy alignment
requirements of the hardware.

```c
struct example {
    char  a;    // 1 byte
    // 3 bytes padding (to align 'b' to a 4-byte boundary)
    int   b;    // 4 bytes
    char  c;    // 1 byte
    // 3 bytes padding (to make total size a multiple of 4)
};
// sizeof(struct example) == 12, NOT 6
```

Memory picture:

```
Offset  0: [ a ][ pad ][ pad ][ pad ]
Offset  4: [ b ][ b   ][ b   ][ b   ]
Offset  8: [ c ][ pad ][ pad ][ pad ]
```

You can always ask the compiler where a field lives with `offsetof`:

```c
offsetof(struct example, b)  // -> 4
offsetof(struct example, c)  // -> 8
```

# 2. Union Memory Layout

A `union` is different. All members **share the same starting address** (offset 0).
The union is sized to fit the **largest** member.

```c
union variant {
    int   i;      // 4 bytes
    short s;      // 2 bytes
    char  c;      // 1 byte
};
// sizeof(union variant) == 4
```

Memory picture - all three members overlap:

```
Offset 0: [ i/s/c ][ i ][ i ][ i ]
           ^ same address, different interpretation
```

Unions are commonly used when you want one memory region to be interpreted as different types depending on context: a tagged union, a type-punning trick, or a protocol message that can carry different payloads.

```c
union data {
    int x;
    char bytes[4];
};

union data d = { .x = 65 };

printf("%d\n", d.x);        // interpret as int
printf("%d\n", d.bytes[0]); // interpret as first byte
```

All union members begin at offset 0, so the same memory can be interpreted in different ways.

# 3. Flexible Array Members (FAMs)

A **flexible array member** is a zero-length array declared as the **last field** of a struct.
It acts as a variable-length tail allowing you to allocate extra memory beyond the struct's fixed size and access it through the FAM.

Normally every field in a struct has a fixed, known size. But sometimes you don't know at compile time how much data a struct needs to carry. Think of a network packet, a kernel message, or a string with a length header.

The naive solution is to pre-allocate a large fixed buffer:

```c
struct message {
    int  length;
    char data[1024];   // wastes memory for small messages
};
```

This wastes memory for small messages and breaks for large ones. FAMs solve this cleanly.

### The Syntax

```c
struct message {
    int  length;
    char data[];    // <- flexible array member, no size given
};
```

`data[]` has no fixed size. It is a placeholder that says: "there will be bytes here, how many depends on how much memory you allocate."

### How You Use It

```c
int n = 5;
struct message *msg = malloc(sizeof(struct message) + n);

msg->length = n;
msg->data[0] = 'H';
msg->data[1] = 'e';
msg->data[2] = 'l';
msg->data[3] = 'l';
msg->data[4] = 'o';
```

Memory picture:

```
     sizeof(struct message)
     <-------------------->
[ length (4 bytes) ][ H ][ e ][ l ][ l ][ o ]
                     ^
                  data[] starts here
                  (extra bytes you malloc'd)
```

The struct's fixed part (`length`) is followed immediately by the extra bytes you allocated. `data[]` just gives you a typed pointer into that region. No copying, no indirection.

### The Hard Rule

The C standard requires FAMs to be the **last field** in a struct. This is not a style guideline; it is enforced by the compiler.

```c
struct broken {
    char data[];    // <- FAM not at end
    int  length;    // <- compiler error
};
```

This rule is the root of the problem we explore next.

# 4. The Problem: A Union of Structs, Each With a FAM

The Linux kernel's IPsec selftest (`tools/testing/selftests/net/ipsec.c`) needs to pack algorithm data into a netlink message. Three different algorithm families exist, each with a FAM at a **different offset**:

```c
struct xfrm_algo {
    char         alg_name[64];
    unsigned int alg_key_len;    /* in bits */
    char         alg_key[];      // FAM at offset 68
};

struct xfrm_algo_auth {
    char         alg_name[64];
    unsigned int alg_key_len;    /* in bits */
    unsigned int alg_trunc_len;  /* in bits */
    char         alg_key[];      // FAM at offset 72
};

struct xfrm_algo_aead {
    char         alg_name[64];
    unsigned int alg_key_len;    /* in bits */
    unsigned int alg_icv_len;    /* in bits */
    char         alg_key[];      // FAM at offset 72
};
```

Each struct ends with `alg_key[]`, but the FAM starts at a **different offset** because each fixed header is a different size.

The original code tried to combine them in a struct like this:

```c
static int xfrm_state_pack_algo(...) {
    struct {
        union {
            struct xfrm_algo      alg;
            struct xfrm_algo_aead aead;
            struct xfrm_algo_auth auth;
        } u;
        char buf[XFRM_ALGO_KEY_BUF_SIZE];  // <- intended key backing buffer
    } alg = {};
    ...
}
```

Memory picture of what was intended:

```
Offset 0                                                68          580
+---------------------------------------------------+------+----------+
| u.alg   [ alg_name(64) | key_len | pad ]  alg_key[]  |
+---------------------------------------------------+------+----------+
| u.aead  [ alg_name(64) | key_len | icv ]  alg_key[]  |  buf[512]
+---------------------------------------------------+------+----------+
| u.auth  [ alg_name(64) | key_len | trunc]  alg_key[] |
+---------------------------------------------------+------+----------+
                                      ↑
                              Different offsets!
                         Can one buf overlap all three?
```

The problem is that **the FAMs start at different offsets**, so `buf` cannot correctly overlap all of them simultaneously. More importantly, the compiler sees the variable-sized union in a non-terminal position and raises:

```
ipsec.c:835:5: warning: field 'u' with variable sized type 'union
(unnamed union at ipsec.c:831:3)' not at the end of a struct or class
is a GNU extension [-Wgnu-variable-sized-type-not-at-end]
```

## Why the Compiler Sees This as a Problem

Each struct with a FAM is **variable-sized** from the compiler's perspective. The fixed header has a known size, but the FAM can hold 0 bytes or 10000 bytes depending on runtime allocation. So `sizeof(struct xfrm_algo)` only counts the fixed part.

A union containing variable-sized members is itself variable-sized. When a variable-sized field is not the last field in an outer struct, the compiler cannot compute where subsequent fields live. It needs to know the offset of `buf`, which is `sizeof(u)`, but `sizeof(u)` is unknown at compile time.

**In short: when you place variable-sized structs in a union, the union becomes variable-sized, and the compiler forbids placing variable-sized fields in non-terminal positions.** Nothing can safely follow something whose size is unknown.

## Solution 1: Move the Union to the End

One approach is to place `union u` at the end of `struct alg`. But as Simon explains [here](https://lore.kernel.org/all/aQD8AOZduY4Fit3k@horms.kernel.org/), the intention of `char buf` is to provide buffer space for the variable-length trailing field of the preceding structure. Moving `u` to the end breaks that design.

## Solution 2: TRAILING_OVERLAP

Another solution is [TRAILING_OVERLAP](https://elixir.bootlin.com/linux/v7.0/source/include/linux/stddef.h#L118):

```c
/**
 * TRAILING_OVERLAP() - Overlap a flexible-array member with trailing members.
 *
 * @TYPE:    Flexible structure type name, including "struct" keyword.
 * @NAME:    Name for a variable to define.
 * @FAM:     The flexible-array member within @TYPE
 * @MEMBERS: Trailing overlapping members.
 */
#define TRAILING_OVERLAP(TYPE, NAME, FAM, MEMBERS)              \
    union {                                                     \
        TYPE NAME;                                              \
        struct {                                                \
            unsigned char __offset_to_FAM[offsetof(TYPE, FAM)];\
            MEMBERS                                             \
        };                                                      \
    }
```

Consider `struct asymmetric_key_id` with `unsigned char data[]` as FAM:

```c
struct asymmetric_key_id {
    unsigned short len;
    unsigned char  data[] __counted_by(len);
};
```

Naively embedding it triggers the same warning:

```c
static struct {
    struct asymmetric_key_id id;   // <- variable-sized, not at end
    unsigned char data[10];
} cakey;
```

The fix using `TRAILING_OVERLAP`:

```c
static struct {
    TRAILING_OVERLAP(struct asymmetric_key_id, id, data,
        unsigned char data[10];
    );
} cakey;
```

Which expands to:

```c
static struct {
    union {
        struct asymmetric_key_id id;
        struct {
            unsigned char __offset_to_FAM[offsetof(struct asymmetric_key_id, data)];
            unsigned char data[10];
        };
    };
} cakey;
```

Memory picture (`offsetof(struct asymmetric_key_id, data)` = 2):

```
Offset 0                            2        11
        |-------- 2 bytes ---------|----------|
id:     [  len  |  len  ][ data[] ]
anon:   [__offset_to_FAM][ data[10] ]
```

Both `id` and the anonymous struct overlap. The padding array pushes `data[10]` to exactly the byte where `id.data[]` begins.

## Solution 3: Custom Fix for Multiple FAMs at Different Offsets

`TRAILING_OVERLAP` works for a **single FAM at a known offset**. But our union has **three FAMs at three different offsets**. `TRAILING_OVERLAP` cannot handle that.

Here is the patch merged into the Linux kernel:

```c
static int xfrm_state_pack_algo(...) {
    union {                                      // <- outer union
        union {
            struct xfrm_algo      alg;
            struct xfrm_algo_aead aead;
            struct xfrm_algo_auth auth;
        } u;
        struct {                                 // <- anonymous overlay struct
            unsigned char __offset_to_FAM[offsetof(struct xfrm_algo_auth, alg_key)];
            char buf[XFRM_ALGO_KEY_BUF_SIZE];
        };
    } alg = {};
    ...
}
```

### Step 1: Outer `union` instead of outer `struct`

The key change is wrapping everything in an **outer `union`** instead of a `struct`. Both members of the outer union start at offset 0 and overlap completely.

### Step 2: Anonymous Overlay Struct

The second member of the outer union is an anonymous struct:

```c
struct {
    unsigned char __offset_to_FAM[offsetof(struct xfrm_algo_auth, alg_key)];
    char buf[XFRM_ALGO_KEY_BUF_SIZE];
};
```

`offsetof(struct xfrm_algo_auth, alg_key)` computes the byte distance from the start of `xfrm_algo_auth` to its `alg_key` FAM. Since `auth` has the largest fixed header, this is the biggest offset among all three structs.

The padding array `__offset_to_FAM` pushes `buf` forward by exactly that many bytes from the start of the outer union.

### Step 3: buf Now Overlaps Correctly

Here's why this works. The three FAM offsets are:

```
offsetof(struct xfrm_algo,      alg_key) = 68
offsetof(struct xfrm_algo_aead, alg_key) = 72  ← auth has same header
offsetof(struct xfrm_algo_auth, alg_key) = 72  ← largest, used for padding
```

Memory diagram of the full layout:

```
Offset 0                                                72          584
+---------------------------------------------------+---+----------+
| u.alg   [ alg_name(64) | key_len ][ pad ] | alg_key[]  |
+---------------------------------------------------+---+----------+
| u.aead  [ alg_name(64) | key_len | icv  ] | alg_key[]  | buf[512]
+---------------------------------------------------+---+----------+
| u.auth  [ alg_name(64) | key_len | trunc] | alg_key[]  |
+---------------------------------------------------+---+----------+
| anon    [       __offset_to_FAM[72]       ][ buf[512]  |
+---------------------------------------------------+---+----------+
                                              ↑
                                All alg_key[] and buf
                                meet here at offset 72
```

Since `auth` has the largest fixed header, `buf` correctly covers the key region for `auth`. **For `alg` and `aead`, whose FAMs start earlier, the key bytes still fall inside `buf` because the code already knows which union member is active and reads from the correct offset within the buffer.** The calling code handles partial overlaps correctly.

### Step 4: Adding offsetof When Missing

The patch also adds a guard:

```c
#ifndef offsetof
#define offsetof(TYPE, MEMBER) __builtin_offsetof(TYPE, MEMBER)
#endif
```

`__builtin_offsetof` is a GCC/Clang built-in that computes the offset at compile time with **zero runtime cost**. This guard ensures portability across compilers that may not provide the standard `offsetof` macro.

# 5. Key Takeaways

**Structs** lay fields out sequentially with padding for alignment.

**Unions** overlay all members at offset 0, sized to the largest member.

**Flexible array members** must be the last field in a struct. This is a hard language rule enforced by the compiler.

When you have a union of structs each carrying a FAM, **the union is itself variable-sized**. Placing that union in a non-terminal position inside an outer struct violates the standard.

`offsetof` is a compile-time constant. You can use it as an array size to create precisely-sized padding. A portable, zero-cost way to express "start this field at exactly byte N."

**The anonymous struct inside an outer union is a classic low-level C pattern for creating an aliased view of memory at a specific offset without casts or undefined behaviour.** When `TRAILING_OVERLAP` cannot handle mismatched FAM offsets, this manual approach is the right tool.

The final code no longer triggers the compiler warning because the outer `union` makes the variable-sized issue disappear: both union members are variable-sized, and the union itself is the last field. All pieces align perfectly.

# 6. The Patch

```diff
diff --git a/tools/testing/selftests/net/ipsec.c b/tools/testing/selftests/net/ipsec.c
index 0ccf484b1d9d..f4afef51b930 100644
--- a/tools/testing/selftests/net/ipsec.c
+++ b/tools/testing/selftests/net/ipsec.c
@@ -43,6 +43,10 @@
 
 #define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))
 
+#ifndef offsetof
+#define offsetof(TYPE, MEMBER)	__builtin_offsetof(TYPE, MEMBER)
+#endif
+
 #define IPV4_STR_SZ	16
 #define MAX_PAYLOAD	2048
 #define XFRM_ALGO_KEY_BUF_SIZE	512
@@ -827,13 +831,16 @@ static int xfrm_fill_key(char *name, char *buf,
 static int xfrm_state_pack_algo(struct nlmsghdr *nh, size_t req_sz,
 		struct xfrm_desc *desc)
 {
-	struct {
+	union {
 		union {
 			struct xfrm_algo	alg;
 			struct xfrm_algo_aead	aead;
 			struct xfrm_algo_auth	auth;
 		} u;
-		char buf[XFRM_ALGO_KEY_BUF_SIZE];
+		struct {
+			unsigned char __offset_to_FAM[offsetof(struct xfrm_algo_auth, alg_key)];
+			char buf[XFRM_ALGO_KEY_BUF_SIZE];
+		};
 	} alg = {};
```

**Reviewed-by:** Simon Horman <horms@kernel.org>  
**Signed-off-by:** Ankit Khushwaha <ankitkhushwaha.linux@gmail.com>

---

## Further Reading

- [GCC offsetof documentation](https://gcc.gnu.org/onlinedocs/gcc/Alternate-Keywords.html#index-_005F_005Fbuiltin_005Foffsetof)
- [Linux kernel TRAILING_OVERLAP macro](https://elixir.bootlin.com/linux/v7.0/source/include/linux/stddef.h#L118)
- [Original kernel discussion](https://lore.kernel.org/all/aQD8AOZduY4Fit3k@horms.kernel.org/)
- [C11 Standard - Flexible Array Members](https://en.cppreference.com/w/c/language/struct)