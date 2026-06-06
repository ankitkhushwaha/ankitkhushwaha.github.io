---
title: "klog | grep -i me"
description: "Here I usually write about my work. What i broke, How i detected it & How i Fixed it(Most Imp)"
draft: false
comments: false
ShowReadingTime: false
ShowToc: false
ShowBreadCrumbs: false
hideMeta: true
---
{{< kf title="Reading logs through serial debug console" date="2026-05-27" slug="4" >}}
Recently I was accessing my BeagleBone Black's logs through the serial debug console. Everything working great. Then on the second attempt, I opened minicom but nothing appeared. No boot messages, no login prompt.

I checked the hardware, board was fine. SSH worked perfectly.

I dug into the details and found something unexpected. Every time I connected the USB-to-TTL adapter, it created /dev/ttyUSB0 as usual. But this time it showed up as /dev/ttyUSB1. And in /var/lock/lockdev/, I found both LCK..ttyUSB0 and LCK..ttyUSB1 still lingering.

The actual cause was that I force-killed minicom in the first session. That's where everything went wrong.

When you kill minicom gracefully, it cleans up:
I/O buffers (sends pending data, reads remaining input)
Port settings (resets to a known state)
Lock files (removes them so the port is available again)

When you kill it forcefully, it abandons everything:
Stale data sits in the input buffer
The output buffer has half-written data
Lock files remain, claiming the port is in use
The port state becomes corrupted

So when minicom tried to reconnect, it got assigned the next available device (USB1 instead of USB0), and even then, It was reading garbage from the corrupted buffer.

Rebooting the BBB forced both sides to reset simultaneously, and everything worked again.

I tried to reproduce the issue by creating lock files manually and force-killing minicom, but I couldn't trigger it consistently. Interesting observation: I was able to access the same port /dev/ttyUSB0 with 2 minicom process instances running simultaneously. Writing to one console gave output in the other process. Both were competing for the same resource.

Picocom, however, locked the resource properly after accessing it.

tl'dr: Close the processes respectfully in Linux. Learned this the hard way.
{{< /kf >}}



{{< kf title="C Memory Layout--Understanding through Linux Kernel Patch" date="2026-05-05" slug="3"  >}}
One of the biggest advantages of contributing to the Linux kernel is the rigor it demands. Every patch requires rock-solid reasoning, clear documentation, and thorough review. During the Linux kernel mentorship program, I submitted a patch for the IPsec selftest that forced me to think deeply about C memory layout, structs, unions, and flexible array members.

The patch itself was small, but understanding why it worked required grasping how the compiler lays out memory when you combine these features. That patch taught me more about C memory layout than any tutorial ever could.

I've written a comprehensive blog post breaking down the fundamentals and walking through the real kernel patch step by step: [Link](https://www.ankitkdev.com/blog/c-memory-layout/)

If you've ever wondered how structs actually sit in memory, what flexible array members really are, or why the compiler complains about variable-sized types. This post is for you.
{{< /kf >}}



{{< kf title="Setup Uboot For Beaglebone Black" date="2026-04-23" slug="2" >}}
most of embedded devs surely went through this situtation:

You update the device tree overlay for a hardware config change, boot your ARM system with U-Boot and nothing changes. No error. No hint. Just the same behavior as before.

The culprit sometimes can be the U-Boot itself. Older versions simply don't support device tree overlays, and for newcomers, that's one of the most frustrating things to debug because there's nothing obviously broken.

So I wrote an end-to-end guide on building and installing U-Boot from source for the BeagleBone Black, covering everything from cross-compilation to autoboot via uEnv.txt.

What's inside:
- Cross-compiling U-Boot for the AM335x SoC
- SD card partition layout (FAT32 boot + ext4 rootfs)
- Installing MLO and u-boot.img correctly into the boot partition
- Manually booting from the U-Boot prompt
- Autoboot with uEnv.txt
- Common mistakes and how to avoid them

Read the full blog here: [Link](https://www.ankitkdev.com/blog/configure-uboot-bbb/)
{{< /kf >}}


{{< kf title="Started learning Device Driver Dev" date="2026-04-11" slug="1" >}}
Recently started learning driver development on the BeagleBone Black (TI AM335x, Cortex-A8).

I'm expected to spend most of my time understanding drivers. Instead, I found myself debugging problems I didn’t even know could exist.

Getting the board to boot properly was the first hurdle. Then came setting up the serial debug console, something I hadn’t worked with before. Once that worked, I installed Debian on the SD card, but the system kept randomly rebooting.

My first assumption was a power supply issue. I bought a new charger, checked the voltage, and convinced myself that had to be the cause.

It wasn’t.

The real problem was the SD card. Extremely slow write speeds were causing the instability. Replacing it fixed the issue.

That small detail cost me a lot of time, but it forced me to approach debugging more systematically instead of relying on guesses.

Compiling and installing the Linux kernel was another challenge. Things rarely worked on the first try, and errors didn’t always point to the real issue. Over time, though, the process started to make sense. 
I’ve written about that here: [Link](https://www.ankitkdev.com/blog/build-linux-kernel-bbb/)

This experience changed how I debug:

• Form hypotheses, but verify them quickly
• Always check the basics, even hardware
• If something looks random, it usually isn’t

Working close to the system teaches you a simple rule: the system is consistent, you just haven’t understood it yet.
{{< /kf >}}

