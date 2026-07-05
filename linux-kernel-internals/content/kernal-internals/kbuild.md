---
title: Kbuild Makefile
weight: 2
---

## Kbuild Makefile

> These aren't plain GNU Make, Kbuild (the kernel's build system) reads them with special meaning when you run `make -C /lib/modules/$(uname -r)/build M=$(pwd) modules`.

```makefile
CFLAGS_main.o := -DDEBUG

ccflags-y := -std=gnu99 -DENABLE_DEBUG

proc_fs_basic-objs := main.o

obj-m := proc_fs_basic.o
```

- **`CFLAGS_main.o`** - per-object compiler flags. Only `main.o` gets `-DDEBUG`; if you had `main.o` and `helper.o`, only the first sees the macro. Useful for debug-gating one file without recompiling the whole module noisily.

- **`ccflags-y`** - flags applied to _every_ `.o` in this Makefile (the module-wide equivalent of `CFLAGS`). Here it forces `gnu99` and defines `ENABLE_DEBUG` globally.

- **`proc_fs_basic-objs`** - when a module is built from more than one source file, this lists what gets linked into the final `.ko`. Pattern is `<module_name>-objs := a.o b.o c.o` (Kbuild also accepts `-y` instead of `-objs` in newer trees).

- **`obj-m`** - the actual build trigger. `obj-m` = build as a loadable module → `proc_fs_basic.ko`. Swap it for `obj-y` and it'd get compiled directly into the kernel image instead.

> Order of resolution: `obj-m` → Kbuild sees `proc_fs_basic.o` is wanted → checks for `proc_fs_basic-objs` → pulls in `main.o` → applies `CFLAGS_main.o` + `ccflags-y` while compiling it.
