---
title: "Forward Declarations"
# tags:
#   - forward-declaration
#   - c-programming
#   - compiler
#   - kernel-api
# categories:
#   - C Programming
#   - Linux Kernel
#   - Embedded Systems
---

# Understanding Forward Declarations in C

One of the best ways to learn systems programming is by reading real-world code. Recently, while reading the Linux kernel source, I noticed something interesting inside `drivers/pinctrl/core.h`:

```c
#include <linux/kref.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/radix-tree.h>
#include <linux/types.h>

#include <linux/pinctrl/machine.h>

struct dentry;
struct device;
struct device_node;
struct module;
```

At first glance, these lines seem incomplete. We see declarations like `struct device;` but no actual definition. Where is the complete structure with all its members? Why didn't file defining this structure isn't included?

This technique is called a forward declaration, and understanding it is key to writing efficient C code, especially in large projects.

---

## What Are Forward Declarations?

A forward declaration tells the compiler that a type exists, but does not provide its full definition yet. Here is a simple example:

```c
struct device;  // Forward declaration
```

This is different from including a full definition:

```c
#include <device.h>  // Full definition with all members
```

When you write a forward declaration, the compiler learns:

- `struct device` is a valid type name
- you can create pointers to it
- you can pass references to it

However, the compiler still does not know:

- the size of the structure
- what fields it contains
- how it is laid out in memory

Because of this limited knowledge, you can only perform certain operations with forward declared types.

---

## Benefits of Forward Declarations

### Dramatically Reduce Compilation Time

This is perhaps the most important benefit. When you include a header file, you do not just get one definition. You trigger an entire cascade of dependencies.

Consider what happens when you include a device.h file:

```
core.h includes device.h
  includes kobject.h
    includes list.h
    includes spinlock.h
      includes irqflags.h
        (and more files)
  includes atomic.h
    includes compiler.h
```

Each file gets parsed, tokenized, and processed. For large projects like the Linux kernel:

- A single include can expand to thousands of lines of code
- In projects with thousands of header files, this expansion can make compilation take minutes or even hours
- Using forward declarations breaks these chains and reduces recompilation time significantly

In large C projects, forward declarations can reduce compile times by 20 to 40 percent in some cases.

### Break Circular Dependencies

Forward declarations are the only way to handle circular dependencies elegantly in C:

Without forward declarations, this creates a problem:

```c
// header1.h
#include "header2.h"
struct Type1 {
    struct Type2 *ptr;
};

// header2.h
#include "header1.h"
struct Type2 {
    struct Type1 *ptr;
};
```

Each file tries to include the other. This causes infinite recursion and compilation fails.

With forward declarations, the problem disappears:

```c
// header1.h
struct Type2;  // Forward declaration
struct Type1 {
    struct Type2 *ptr;  // Works fine
};

// header2.h
struct Type1;  // Forward declaration
struct Type2 {
    struct Type1 *ptr;  // Works fine
};
```

Now both files can refer to each other without problems.

### Improve Code Design

Forward declarations encourage better API design. When a header only uses forward declarations, it signals that these types are used as opaque pointers. This means the internal structure is hidden from users.

This leads to better encapsulation:

```c
// Bad practice: requires full definition
struct device dev;
dev.parent = &dev_p;  // Direct member access

// Good practice: with forward declaration
struct device *dev = device_create();
device_set_active(dev);  // Function based access
```

---

## When Should You Use Forward Declarations?

Use forward declarations in these situations:

1. You only need pointers or references

```c
struct device;
void func(struct device *dev);  // Only passing pointer
void setup(struct device **dev_ptr);  // Pointer to pointer
```

2. Breaking compilation dependencies is important

In large projects or libraries where compilation speed matters, forward declarations become part of the architecture design.

3. Handling circular dependencies between files

```c
struct A { struct B *b; };
struct B { struct A *a; };
```

4. Hiding implementation details with opaque types

Users see only the pointer, not what is inside:

```c
// Public header
struct FileHandle;  // Users do not need to know what is inside
struct FileHandle *file_open(const char *name);
int file_read(struct FileHandle *handle, char *buf);
```

5. Creating stable public APIs

When internal struct members change, you do not need to recompile all user code.

---

## When Should You NOT Use Forward Declarations?

Do not use forward declarations when you need to:

1. Access struct members

```c
struct device;
void setup(struct device *dev) {
    dev->parent = NULL;  // ERROR: need full definition
}
```

2. Create instances of the struct

```c
struct device;
void func() {
    struct device dev;  // ERROR: need full definition
}
```

3. Use the sizeof operation

```c
struct device;
size_t size = sizeof(struct device);  // ERROR: compiler does not know size
```

In these cases, you must include the full definition.

---

## A Simple Rule to Follow

Here is a practical rule that works well:

In header files:

> prefer forward declarations when possible

In source files:

> include the actual headers when you need full definitions

This keeps your interfaces small and clean while allowing implementation code full access to what it needs.

---

## Real World Example: The Linux Kernel

The Linux kernel uses this approach consistently. Let's look at two files side by side to understand the strategy.

In the header file `drivers/pinctrl/core.h`, you see:

```c
// Include what is actually embedded in our structures
#include <linux/kref.h>        // Reference counting
#include <linux/list.h>        // Linked lists
#include <linux/mutex.h>       // Synchronization
#include <linux/radix-tree.h>  // Data structure
#include <linux/types.h>       // Basic types

// Only include our own definitions
#include <linux/pinctrl/machine.h>

// Forward declarations for opaque pointers
struct dentry;      // For debugfs operations
struct device;      // For driver model
struct device_node; // For device tree
struct module;      // For module information
```

But in the actual implementation file `drivers/pinctrl/core.c`, all the full definitions are included:

```c
#include <linux/debugfs.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/export.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kref.h>
#include <linux/list.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
[...]
```

This shows the pattern clearly:

- In the header file: use forward declarations for types you only pass as pointers
- In the source file: include everything you actually need to work with those types

This design:

- Keeps the header file minimal and stable
- Allows the implementation full access to all definitions it needs
- Reduces recompilation when other files change
- Makes the public interface cleaner and more maintainable
- Lets developers using the library avoid unnecessary includes

---

## Final Thoughts

Forward declarations are a small C feature that becomes increasingly important as projects grow larger.

In tiny projects, they may feel unnecessary. You can include everything and not worry about compilation time.

In large systems like the Linux kernel, they become part of architecture design itself. Understanding when and how to use them becomes essential.

The goal is not simply to use fewer includes.

The real goal is to control dependencies intentionally.

That is the actual value of forward declarations. By choosing what information you expose and what you hide, you create better designed code that compiles faster and changes more safely.
