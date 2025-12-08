---
date: '2025-12-08T10:35:09+05:30'
draft: False
title: 'Linux Kernel Mentorship Program'
tags: ["kernel", "linux", "lfx", "linux-kernel", "mentorship"]
---
## Linux Kernel Mentorship Program

### Introduction

I’ve been using Linux for the last 2 years. At first, I was amazed how perfectly and smoothly it worked on my computer. Since then, I started using Linux as my primary machine for development work. Last summer, I gained interest in C. The Summer Application was open, but I decided not to apply and worked on improving my proficiency in C. The Fall '25 application opened in August, and I appiled. The prerequisites for the mentorship included some basic tasks like building and booting the Linux Kernel, writing the first "hello world" kernel module, learning to decode a stack trace, and changing the kernel version in source code and booting with that change.

Somehow, my application was accepted ;-). At first, the Linux Kernel seemed quite difficult to understand what was going on. We were initially told to choose two subsystems to work on.

However, I checked the syzbot website and randomly chose a simple [bug](https://syzkaller.appspot.com/bug?id=194151be8eaebd826005329b2e123aecae714bdb) related to the `trace` subsystem, specifically addressing the kernel ring buffer and somehow I ended up sending a [patch](https://lore.kernel.org/all/20251008172516.20697-1-ankitkhushwaha.linux@gmail.com/) for this fix. 

I **personally advise** not to do this.

I also tried to solve other bugs, but couldn’t, mainly because I wasn’t aware of the details – what was going on under the hood. So, I paused those attempts for some time. David Hunter first told us to solve the easy fixes, like warning fixes in the `kselftest` subsystem and kernel build warnings with `W=1`, and that working on them is quite easy for a beginner. Backporting can also be considered -- see **Hanne-Lotta's Blog -** [link](https://hannis.link/linux-kernel/backporting.html).

There are some key details that you have to look out for when working on kernel development, like sending the patch with a clear explanation: what the patch was for, what and how it is fixing the bug, and why you think your approach is right.

### The Patch Submission Flow

1. **Create the Patch:**  
```
git format-patch HEAD~1
```

**Check the Patch for Typographical Errors and Format Correctness:** (Run the check and then apply fixes if needed)  
```
./scripts/checkpatch.pl --strict --fix-inplace hello.patch
./scripts/checkpatch.pl --strict --fix-inplace -f --fix hello.patch  
```
2. **Find the List of Maintainers related to that Subsystem:**  
```
./scripts/get_maintainer.pl --separator=, --no-rolestats hello.patch  
```
2. Always make sure to **double** check the patch before sending it to the mailing list. I will recommend first sending the patch with `git send-email` using the `--dry-run` option.  
```
git send-email --to=<Maintainer Email> --cc=<Mailing list> hello.patch  
```
   *(**Note:** Replace `<Maintainer Email>` and `<CC Emails>` with the actual emails obtained from `get_maintainer.pl`.)*  
3. **Writing a Changelog for Previous Versions:**  
   see:  [https://lore.kernel.org/all/20251106095532.15185-1-ankitkhushwaha.linux@gmail.com/](https://lore.kernel.org/all/20251106095532.15185-1-ankitkhushwaha.linux@gmail.com/)

**Note:** For the `kselftest` subsystem, it is helpful to mention the compiler details with which you are getting the error/warning.

see: [https://lore.kernel.org/all/20251126163046.58615-1-ankitkhushwaha.linux@gmail.com/](https://lore.kernel.org/all/20251126163046.58615-1-ankitkhushwaha.linux@gmail.com/)

### Patch accepted

During the mentorship total of 7 patch was accepted in mainline kernel. 

```
0384c8ea96bfe49e82e624e53bfd5f80c3230ea9 selftests/mm/uffd: initialize char variable to Null
af7273cc7ae01f5b3e34e62f59588ce79fe50f79 selftests/net: initialize char variable to null
3b12a53b64d0c86cf68cab772bd4137e451b17a5 selftest/mm: fix pointer comparison in mremap_test
6ae0f2072768fb3db7846cee08b611a96310930d docs: parse-headers.rst: Fix a typo
216158f063fe24fb003bd7da0cd92cd6e2c4d48b selftests/user_events: fix type cast for write_index packed member in perf_test
afb8f6567a5b4bb4e673608048939fef854b8709 selftest: net: fix socklen_t type mismatch in sctp_collision test
de4cbd704731778a2dc833ce5a24b38e5d672c05 ring buffer: Propagate __rb_map_vma return value to caller
```

### Tips and Tools

One of the things that I learned is that whenever you are writing a patch for a fix, check the previous commits for that file before writing the patch header to ensure consistency with the file's existing style.

One difficulty I was experiencing was navigating the codebase and finding the definition for a particular macro in VS Code – it was taking too much time to process. However, I later found that `cscope` works fine.

**Using Cscope for Code Navigation:**  
```
cd linux/

# Generate Cscope Database:
make cscope \-j8  

# This will generate files like
ls csocpe*
cscope.files cscope.out cscope.out.in cscope.out.po

# Enter Cscope Interactive Mode
cscope -d
```

`cscope` works fine. The Sublime Text editor also works well for me. Additionally, Sublime Merge was helpful for quickly finding the previous commits of a particular file.

**Closing Thoughts**

The learning was very rewarding, especially the Office Hours meetings and Discord discussions. I learned that kernel development and becoming a kernel hacker isn't an easy task that you can just pick up quickly. It requires consistent, dedicated effort. We need to acquire a deeper understanding of systems programming, architecture, and a willingness to troubleshoot complex issues. 

It's certainly a long but ultimately rewarding journey. I also learned about the development cycle of the Linux kernel. This program was a strong beginning, and the work will continue.

I will recommend this mentorship program to anyone interested in Linux kernel development. You'll learn the basics and find out if kernel development interests you in the long term. What I find most valuable is that you get a feel for the supportive open source community.

I am very thankful to Shuah Khan, David Hunter, and Khalid for this wonderful mentorship program.