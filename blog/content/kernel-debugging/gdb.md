---
title: "Debug Kernel Modules with GDB"
---

## Set up the kernel and QEMU

Build the kernel boot with debug info:

- `CONFIG_DEBUG_INFO` (pick a DWARF option under Kernel hacking, the toolchain default is fine)
- `CONFIG_GDB_SCRIPTS`, which gives you the `lx-*` helper commands
- `CONFIG_RANDOMIZE_BASE` off, or boot with `nokaslr`, otherwise kernel addresses never match `vmlinux`

```bash
scripts/config --file build-qemu/.config -e DEBUG_KERNEL -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
               -e GDB_SCRIPTS -d RANDOMIZE_BASE
make O=build-qemu olddefconfig
make O=build-qemu -j$(nproc)
make O=build-qemu scripts_gdb        # creates vmlinux-gdb.py next to vmlinux in build-dir
```

Then boot under QEMU with the gdb stub. `-s` listens on TCP port 1234 and `-S` freezes the CPU until gdb says continue.

```bash
qemu-system-x86_64 \
    -m 2048 \
    -smp 2 \
    -machine q35,accel=kvm \
    -cpu host \
    -kernel $LINUX_BZIMAGE \
    -append "root=/dev/sda1 console=ttyS0 nokaslr" \
    -drive file=$DISK,format=raw \
    -nographic -s -S
```

example For an ARM `virt` board:

```bash
qemu-system-arm \
    -M virt -cpu cortex-a15 -m 2048M \
    -kernel linux-7.2.8/build-qemu/arch/arm/boot/zImage \
    -initrd rootfs-cpio.gz \
    -append "root=/dev/tty0 nokaslr" \
    -nographic -dtb virt-custom.dtb -s -S
```

## Build the module with debug info

Build the module against the same configured tree you boot. Because `CONFIG_DEBUG_INFO` is on, Kbuild already passes `-g` to module sources, so the `.ko` carries DWARF.

```make
# Kbuild
obj-m += mymod.o
mymod-y := main.o hw.o
ccflags-y += -Og -I$(src)/include
```

```make
# Makefile
KDIR ?= /path/to/linux/build
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules
```

## Attach gdb and load module symbols

*Start gdb from the kernel build directory* so it finds `vmlinux-gdb.py` beside `vmlinux`. If gdb refuses to auto-load it, add `add-auto-load-safe-path /path/to/linux/build` to `~/.gdbinit`, or run `source vmlinux-gdb.py` by hand.

you may also use the`~/.gdbinit` file, which is executed automatically every time you start the GNU Debugger (GDB). It is primarily used to automate repetitive debugging setups, define custom commands.

```
$ cat ~/.gdbinit
add-auto-load-safe-path ~/linux-src/build-qemu/
target remote :1234
```

```
$ gdb vmlinux                    # gdb-multiarch for ARM
(gdb) hbreak start_kernel
(gdb) c                          # qemu starts booting the kernel
(gdb) lx-symbols /path/to/mymod  # directory that holds your unstripped .ko
(gdb) set breakpoint pending on
(gdb) c
```

Run `lx-symbols` after the kernel has reached `start_kernel`, not at the very first instruction. Before the MMU is on, kernel virtual addresses cannot be read and the command fails with `Cannot access memory`.

`lx-symbols` searches the directory you give it, plus the current directory, for `<module>.ko`. It also sets an internal breakpoint on `do_init_module()`. Each time you run `insmod` in the guest, that breakpoint fires, gdb runs `add-symbol-file` with the addresses the kernel just chose, and the guest resumes. It reloads on every insert, so you can `rmmod`, rebuild and `insmod` again without restarting gdb.

### The manual route

If the helper scripts are not available, load symbols yourself once the module is in memory. Read each section address in the guest, then pass them to gdb:

```
~ # cat /sys/module/mymod/sections/.text
~ # cat /sys/module/mymod/sections/.data
~ # cat /sys/module/mymod/sections/.bss
```

```
(gdb) add-symbol-file mymod.ko <text> -s .data <data> -s .bss <bss>
```

While `insmod` is still blocked inside the module's init function you cannot read these files from the guest, so this route cannot help with code that runs during init.

## Debug init code

best way to debug init code i found so far, is to compile the module into the kernel itself. Built-in code is part of `vmlinux`, so gdb already has correct addresses for every section.

1. Copy the module source into the tree, for example `drivers/mymod/`.
2. Add a `Kconfig` in that directory:

```
config MYMOD
	tristate "My module"
	depends on OF
	help
	  Debug build of my module.
```

3. Replace the external `obj-m` Kbuild file with an in-tree `Makefile` that keys on the config symbol:

```make
obj-$(CONFIG_MYMOD) += mymod.o
mymod-y := main.o hw.o
ccflags-y += -Og -I$(src)/include
```

4. Hook the directory into its parent. In `drivers/Kconfig` add `source "drivers/mymod/Kconfig"` before the final `endmenu`, and in `drivers/Makefile` add `obj-$(CONFIG_MYMOD) += mymod/`.
5. Select it as built-in and rebuild:

```bash
scripts/config --file build-qemu/.config -e MYMOD        # =y
make O=build-qemu olddefconfig
make O=build-qemu -j$(nproc)
```

6. Boot under QEMU with `-s -S`, as before, and break before init runs:

```
$ gdb vmlinux
(gdb) target remote :1234
(gdb) hbreak mymod_init
(gdb) c
```
