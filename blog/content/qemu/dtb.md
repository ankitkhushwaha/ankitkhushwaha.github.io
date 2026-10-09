---
title: Handle DTB Files in QEMU
---

When working with Linux kernel drivers in QEMU, you may need to inspect or modify the Device Tree Blob (DTB) to test device configurations.

### 1. Dump the generated DTB

Use a separate filename to avoid overwriting existing files:

```bash
-machine dumpdtb=virt-generated.dtb
```

For example:

```bash
qemu-system-arm -M virt -machine dumpdtb=virt-generated.dtb
```

### 2. Convert DTB to DTS

A DTB is a binary file, while a DTS is a human-readable Device Tree source file.

```bash
dtc -I dtb -O dts -o virt-generated.dts virt-generated.dtb
```

### 3. Edit and compile

Edit `virt-generated.dts` to modify the device configuration or add Device Tree nodes.

Compile it into a new DTB:

```bash
dtc -I dts -O dtb -o virt-custom.dtb virt-generated.dts
```

### 4. Boot Linux with the modified DTB

Pass the custom DTB to QEMU using `-dtb`:

```bash
qemu-system-arm \
    -M virt \
    -kernel path/to/zImage \
    -dtb virt-custom.dtb \
    -nographic
```

This workflow is useful for testing Device Tree changes and Linux driver probing without modifying QEMU's source code.
